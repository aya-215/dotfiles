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
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from xml.sax.saxutils import escape, quoteattr

MCP_JSON = os.path.expanduser("~/.dotfiles/.mcp.json")
TIMEOUT = 300


class SomuError(Exception):
    pass


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
        raise SomuError(f"eB-API に接続できへん: {e}")


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
