"""総務パック（ミラー）を eB-API 直叩きで読み、ボリュームを手元に保存して検索する。

usage:
  somu.py volumes [語] [--all]
  somu.py specs <vol>
  somu.py search <vol> <語...> [--refresh] [--yes] [--limit N]
  somu.py files <vol> <item_id>
  somu.py text <vol> <item_id> [file_id...] [--old] [--max-chars N]

設定:
  - 接続先は ~/.dotfiles/.mcp.json の mcpServers["eb-api-somu"].headers から読む（gitignore 済み）
  - 保存先は ~/.cache/somu-search/（環境変数 SOMU_SEARCH_CACHE で差し替え可）
"""
import argparse
import datetime
import json
import os
import re
import sys
import tempfile
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from xml.sax.saxutils import escape, quoteattr

MCP_JSON = os.path.expanduser("~/.dotfiles/.mcp.json")
TIMEOUT = 300
LARGE_THRESHOLD = 10000
BATCH = 200
WORK_SUFFIXES = ("_WK", "_DEF", "_WF")


class SomuError(Exception):
    pass


class ConnectError(SomuError):
    pass


class NeedsConfirm(Exception):
    def __init__(self, count):
        super().__init__(count)
        self.count = count


@dataclass
class Config:
    api_url: str
    viewer_url: str
    file_base: str


def load_config(path=MCP_JSON):
    try:
        with open(path) as f:
            headers = json.load(f)["mcpServers"]["eb-api-somu"]["headers"]
        api_url, viewer_url = headers["ebase-api-url"], headers["ebase-viewer-url"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError):
        raise SomuError(f"{path} に eb-api-somu の ebase-api-url / ebase-viewer-url が無い")
    u = urllib.parse.urlsplit(viewer_url)
    return Config(api_url, viewer_url, f"{u.scheme}://{u.netloc}/volume/")


def norm_vol(v):
    m = re.fullmatch(r"(\d{1,5})(_.*)?", v.strip())
    if not m:
        raise SomuError(f"ボリュームIDの形がおかしい: {v}")
    return m.group(1).zfill(5) + (m.group(2) or "")


def _http_post(url, body):
    req = urllib.request.Request(url, body, {"Content-Type": "text/plain; charset=utf-8"})
    try:
        return urllib.request.urlopen(req, timeout=TIMEOUT).read()
    except (urllib.error.URLError, OSError) as e:
        raise ConnectError(f"eB-API に接続できへん: {e}")


class Api:
    def __init__(self, api_url, post=None):
        self.api_url = api_url
        self.post = post or _http_post

    def _call(self, command, data):
        xml = (f'<?xml version="1.0" encoding="utf-8"?><request><command name="{command}"/>'
               f"<data>{data}</data></request>")
        raw = self.post(self.api_url, xml.encode("utf-8"))
        try:
            root = ET.fromstring(raw)
        except ET.ParseError as e:
            raise SomuError(f"{command} の応答が XML やない: {e}")
        status = root.findtext("status")
        if status != "200":
            raise SomuError(f"{command} が status={status} を返した")
        return root.find("data")

    @staticmethod
    def _vol(vol):
        return f"<volume voldbname={quoteattr(vol)}/>"

    def volumes(self):
        data = self._call("getVolume", "")
        return [(v.findtext("voldbname"), v.findtext("volname") or "") for v in data.iter("volume")]

    def spec_info(self, vol):
        data = self._call("getSpecInfo", self._vol(vol) + '<spec all="true" invisible="false"/>')
        return [{k: s.findtext(k) for k in ("spec_type", "spec_title", "data_type")}
                for s in data.iter("spec") if s.findtext("spec_title")]

    def item_ids(self, vol):
        data = self._call("getItems", self._vol(vol) + '<search target="SPEC"></search>')
        return [e.text for e in data.iter("item_id")]

    def spec_values(self, vol, ids, spec_type):
        items = "".join(f"<item><item_id>{escape(i)}</item_id></item>" for i in ids)
        target = f'<targets><spec target="spec" spec_type={quoteattr(spec_type)} spec_title="*"/></targets>'
        data = self._call("getSpecDataLite", self._vol(vol) + items + target)
        out = {}
        for it in data.iter("item"):
            iid, vals = None, {}
            for s in it.findall("spec"):
                title, value = s.findtext("spec_title"), s.findtext("value")
                if s.findtext("target") == "item_id":
                    iid = value
                elif title and value and not title.startswith("inv"):
                    vals[title] = value
            if iid:
                out[iid] = vals
        return out

    def item_files(self, vol, item_id):
        data = self._call("getItemImage", self._vol(vol) + f"<item><item_id>{escape(item_id)}</item_id></item>")
        return [{c.tag: (c.text or "") for c in img} for img in data.iter("image")]


def make_api(cfg):
    return Api(cfg.api_url)


def cache_path(vol):
    root = os.environ.get("SOMU_SEARCH_CACHE") or os.path.expanduser("~/.cache/somu-search")
    return os.path.join(root, f"{vol}.json")


def load_cache(vol):
    try:
        with open(cache_path(vol)) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def _save_cache(vol, data):
    path = cache_path(vol)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # 取得途中で落ちても前回の保存を壊さないよう、書き切ってから置き換える
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def dump_volume(api, vol, confirmed=False):
    ids = api.item_ids(vol)
    if len(ids) > LARGE_THRESHOLD and not confirmed:
        raise NeedsConfirm(len(ids))
    specs = api.spec_info(vol)
    rows = {i: {"item_id": i} for i in ids}
    for spec_type in dict.fromkeys(s["spec_type"] for s in specs if s["spec_type"]):
        try:
            for k in range(0, len(ids), BATCH):
                for iid, vals in api.spec_values(vol, ids[k:k + BATCH], spec_type).items():
                    if iid in rows:
                        rows[iid].update({f"{spec_type}:{t}": v for t, v in vals.items()})
        except ConnectError:
            raise
        except SomuError as e:
            print(f"WARN: {spec_type} を飛ばした: {e}", file=sys.stderr)
    data = {"vol": vol, "fetched_at": datetime.datetime.now().isoformat(timespec="seconds"),
            "specs": specs, "items": list(rows.values())}
    _save_cache(vol, data)
    return data


def get_or_dump(api, vol, refresh=False, confirmed=False):
    data = None if refresh else load_cache(vol)
    return data or dump_volume(api, vol, confirmed)


def normalize(s):
    return unicodedata.normalize("NFKC", s).casefold()


def search(items, words):
    words = [normalize(w) for w in words if w.strip()]
    hits = []
    for it in items:
        fields = {k: normalize(v) for k, v in it.items() if k != "item_id"}
        if all(any(w in v for v in fields.values()) for w in words):
            keys = [k for k, v in fields.items() if any(w in v for w in words)]
            exact = any(v.strip() in words for v in fields.values())
            hits.append((not exact, it["item_id"], it, keys))
    hits.sort(key=lambda h: (h[0], h[1]))
    return [(it, keys) for _, _, it, keys in hits]


def snippet(text, word, width=60):
    n, w = normalize(text), normalize(word)
    # NFKC で長さが変わった文字列は位置がずれるので、正規化後の文字列から切り出す
    src = text if len(n) == len(text) else n
    pos = max(n.find(w), 0)
    start, end = max(pos - width, 0), min(pos + len(w) + width, len(src))
    s = src[start:end].replace("\r", "").replace("\n", " ")
    return ("…" if start > 0 else "") + s + ("…" if end < len(src) else "")


def detail_url(viewer_url, vol, item_id):
    return f"{viewer_url.rstrip('/')}/DispDetail.do?volumeName={vol}&itemID={item_id}"


def _volname(api, vol):
    try:
        return dict(api.volumes()).get(vol, "")
    except SomuError:
        return ""


def cmd_volumes(api, cfg, args):
    for vid, name in api.volumes():
        if not args.all and vid.endswith(WORK_SUFFIXES):
            continue
        if args.word and normalize(args.word) not in normalize(f"{vid} {name}"):
            continue
        print(f"{vid}\t{name}")


def cmd_specs(api, cfg, args):
    for s in api.spec_info(norm_vol(args.vol)):
        print(f"{s['spec_type']}\t{s['spec_title']}\t{s['data_type'] or ''}")


def cmd_search(api, cfg, args):
    vol = norm_vol(args.vol)
    data = get_or_dump(api, vol, args.refresh, args.yes)
    hits = search(data["items"], args.words)
    print(f"{vol} {_volname(api, vol)} / {data['fetched_at']} 時点 / "
          f"{len(data['items'])}件中 {len(hits)}件ヒット")
    for it, keys in hits[:args.limit]:
        print(f"=== {it['item_id']}  {detail_url(cfg.viewer_url, vol, it['item_id'])}")
        for k in keys:
            word = next(w for w in args.words if normalize(w) in normalize(it[k]))
            print(f"  [{k}] {snippet(it[k], word)}")
        for k, v in it.items():
            if k != "item_id" and k not in keys and len(v) <= 80:
                print(f"  [{k}] {v}")
    if len(hits) > args.limit:
        print(f"（残り {len(hits) - args.limit} 件は --limit で増やす）")


def build_parser():
    p = argparse.ArgumentParser(prog="somu.py", description="総務パック（ミラー）を検索する")
    sub = p.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("volumes", help="ボリューム一覧")
    v.add_argument("word", nargs="?")
    v.add_argument("--all", action="store_true", help="_WK などの作業用ボリュームも出す")
    v.set_defaults(func=cmd_volumes)
    s = sub.add_parser("specs", help="項目定義")
    s.add_argument("vol")
    s.set_defaults(func=cmd_specs)
    q = sub.add_parser("search", help="手元の保存データを AND 検索")
    q.add_argument("vol")
    q.add_argument("words", nargs="+")
    q.add_argument("--refresh", action="store_true", help="全件を取り直す")
    q.add_argument("--yes", action="store_true", help=f"{LARGE_THRESHOLD}件超でも取る")
    q.add_argument("--limit", type=int, default=20)
    q.set_defaults(func=cmd_search)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        cfg = load_config()
        args.func(make_api(cfg), cfg, args)
    except NeedsConfirm as e:
        print(f"CONFIRM: このボリュームは {e.count}件ある。全件取るならユーザーに確認して --yes を付けて再実行",
              file=sys.stderr)
        return 3
    except SomuError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
