#!/usr/bin/env python3
"""課題DB (eB-PM ボリューム 02043) から、自分のコメント・自分宛てのお知らせ・自分担当の課題を読む（読み取り専用）。

  ebpm_issues.py --since YYYY-MM-DD [--me NAME]

標準出力に JSON {"me", "comments", "notices", "assigned", "failed"}。
接続失敗・タイムアウト・呼び出し上限超過は failed に理由を入れ、取れた分を返して exit 0。
"""
import argparse
import json
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

ENDPOINT = "http://192.168.234.19:8080/ebase-net/eb-api"
VOLUME = "02043"
# コメント登録者・担当者名・お知らせ先に入る表記（スペース無し）。"森 彪人" で検索すると別人の 森俊博 まで拾うため既定は詰める
DEFAULT_ME = "森彪人"
MAX_CALLS = 40
CHUNK = 30
LOOKUP_BATCH = 25
DONE_STATUSES = {"完了", "終了", "クローズ", "完了済", "対応済", "取下", "取り下げ", "却下", "中止", "対応不要"}
TEXT_LIMIT = 1000
DETAIL_URL = "https://ebpm.ebase-jp.com/ebase-web-v3/DispDetail.do?volumeName=02043&itemID="


class EbpmError(Exception):
    pass


def norm(s):
    return re.sub(r"\s+", "", s or "")


def to_date(s):
    m = re.search(r"(\d{4})[/-](\d{1,2})[/-](\d{1,2})", s or "")
    return f"{int(m[1]):04d}-{int(m[2]):02d}-{int(m[3]):02d}" if m else None


def _root(text):
    try:
        root = ET.fromstring(text.lstrip("﻿").encode("utf-8"))
    except ET.ParseError as e:
        raise EbpmError(f"応答を解析できない: {e}")
    status = (root.findtext("status") or "").strip()
    if status == "404" and root.find("data/error") is not None:
        return None  # 該当なし
    if status != "200":
        raise EbpmError(f"eB-API が status={status} を返した")
    return root


def parse_item_ids(text):
    root = _root(text)
    if root is None:
        return []
    return [(e.text or "").strip() for e in root.findall("data/item/item_id")]


def parse_records(text):
    root = _root(text)
    if root is None:
        return []
    records = []
    for item in root.findall("data/item"):
        rec = {}
        for s in item.findall("spec"):
            key = s.findtext("spec_title") or s.findtext("target")
            if key:
                # 課題DBは改行を \n という文字列で持つ
                rec[key.strip()] = (s.findtext("value") or "").replace("\\n", "\n").strip()
        records.append(rec)
    return records


def curl_post(xml):
    # Python の urllib は連続呼び出しで connect timeout になった（curl は通る）
    try:
        p = subprocess.run(
            ["curl", "-s", "-S", "--connect-timeout", "10", "-m", "60", "-X", "POST", "-H", "Content-Type: text/plain; charset=utf-8",
             "--data-binary", "@-", ENDPOINT],
            input=xml.encode("utf-8"), capture_output=True, timeout=75)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise EbpmError(f"curl 失敗: {e}")
    if p.returncode != 0:
        raise EbpmError(f"curl exit {p.returncode}: {p.stderr.decode('utf-8', 'replace').strip()}")
    return p.stdout.decode("utf-8", "replace")


class Client:
    def __init__(self, post, max_calls):
        self.post, self.max_calls, self.calls = post, max_calls, 0

    def call(self, xml):
        if self.calls >= self.max_calls:
            raise EbpmError(f"call cap {self.max_calls} exceeded")
        if self.calls:
            time.sleep(1)  # 本番の課題サーバなので間隔を空け、並列にしない
        self.calls += 1
        return self.post('<?xml version="1.0" encoding="utf-8"?>' + xml)

    def search(self, conds, match="part"):
        c = "".join(f"<spec target=\"spec\" spec_type={quoteattr(t)} spec_title={quoteattr(k)} value={quoteattr(v)}/>"
                    for t, k, v in conds)
        return parse_item_ids(self.call(
            f'<request><command name="getItems"/><data><volume voldbname="{VOLUME}"/>'
            f'<search match={quoteattr(match)}>{c}</search></data></request>'))

    def fetch(self, ids, spec_types):
        assert len(ids) <= CHUNK
        items = "".join(f"<item><item_id>{i}</item_id></item>" for i in ids)
        targets = '<targets><spec target="basic"/>' + "".join(
            f'<spec target="spec" spec_type={quoteattr(t)} spec_title="*"/>' for t in spec_types) + "</targets>"
        return parse_records(self.call(
            f'<request><command name="getSpecDataLite"/><data><volume voldbname="{VOLUME}"/>{items}{targets}</data></request>'))


COMMENT_TYPES = ["データ管理", "EBITS基本情報", "EBCMTコメント情報"]
ISSUE_TYPES = ["データ管理", "EBITS基本情報", "EBITS課題管理情報"]


def _at(rec):
    return rec.get("登録時刻") or rec.get("registered_date") or ""


def collect(since, me, post=None, max_calls=MAX_CALLS):
    post = post or curl_post
    out = {"me": me, "comments": [], "notices": [], "assigned": [], "failed": None, "notes": []}
    cl = Client(post, max(1, max_calls))
    try:
        _collect(cl, since, norm(me), out)
    except EbpmError as e:
        out["failed"] = str(e)
        out["truncated"] = True  # 途中で止まったので、以降のデータは含まれない
    out.setdefault("truncated", False)
    rows = out["comments"] + out["notices"]
    try:
        _attach_issue_ids(cl, rows)
    except EbpmError as e:
        out["failed"] = out["failed"] or str(e)
        out["truncated"] = True
    for row in rows:
        row["url"] = DETAIL_URL + row["issue_item_id"] if row["issue_item_id"] else ""
    for k in ("comments", "notices"):
        out[k].sort(key=lambda r: r["at"], reverse=True)
    return out


ID_RE = re.compile(r"^t\d{12}$")


def _collect(cl, since, me, out):
    mine = cl.search([("EBCMTコメント情報", "コメント登録者", me)])
    to_me = cl.search([("EBCMTコメント情報", "お知らせ先担当者", me)])
    assigned_ids = cl.search([("EBITS課題管理情報", "担当者名", me)])  # 実測: 件数上限なし（全件1回で返る）

    ids = sorted(set(mine) | set(to_me), reverse=True)
    # 固定幅 t+12桁・登録順に増える（実測で日付の逆転0件）ときだけ、古いチャンクで打ち切る
    early_ok = all(ID_RE.match(i) for i in ids)
    for i in range(0, len(ids), CHUNK):
        recs = cl.fetch(ids[i:i + CHUNK], COMMENT_TYPES)
        dates = [to_date(_at(r)) for r in recs]
        for r, d in zip(recs, dates):
            if r.get("属性") != "コメント" or r.get("削除済みフラグ") == "1" or not d or d < since:
                continue
            by = r.get("コメント登録者", "")
            row = {"issue_no": r.get("課題No", ""), "issue_title": r.get("課題名", ""), "issue_item_id": "",
                   "comment_item_id": r.get("item_id", ""), "at": _at(r), "text": r.get("コメント", "")[:TEXT_LIMIT]}
            if norm(by) == me:
                out["comments"].append(row)
            elif me in norm(r.get("お知らせ先担当者", "")):
                row.update(by=by, to=r.get("お知らせ先担当者", ""))
                out["notices"].append(row)
        if early_ok and recs and all(d and d < since for d in dates):
            out["notes"].append(f"stopped early at {ids[i]} (chunk older than {since})")
            break

    for i in range(0, len(assigned_ids), CHUNK):
        for r in cl.fetch(assigned_ids[i:i + CHUNK], ISSUE_TYPES):
            if r.get("属性") == "課題" and norm(r.get("担当者名", "")) == me and r.get("状況", "") not in DONE_STATUSES:
                out["assigned"].append({"issue_no": r.get("課題No", ""), "issue_title": r.get("課題名", ""),
                                        "status": r.get("状況", ""), "item_id": r.get("item_id", ""),
                                        "url": DETAIL_URL + r.get("item_id", "")})


def _attach_issue_ids(cl, rows):
    """コメントのレコードは課題本体の item_id を持たないので、課題No をまとめて引く（part 検索は空白区切りで OR になる）"""
    nos = sorted({r["issue_no"] for r in rows if r["issue_no"]})
    found = {}
    for i in range(0, len(nos), LOOKUP_BATCH):
        batch = nos[i:i + LOOKUP_BATCH]
        try:
            hits = cl.search([("EBITS基本情報", "課題No", " ".join(batch)), ("データ管理", "属性", "課題")])
            for j in range(0, len(hits), CHUNK):
                for r in cl.fetch(hits[j:j + CHUNK], ["データ管理", "EBITS基本情報"]):
                    if r.get("属性") == "課題":
                        found[r.get("課題No", "")] = r.get("item_id", "")
        finally:
            for r in rows:
                r["issue_item_id"] = found.get(r["issue_no"], "")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--since", required=True, help="YYYY-MM-DD")
    ap.add_argument("--me", default=DEFAULT_ME)
    ap.add_argument("--max-calls", type=int, default=MAX_CALLS)
    a = ap.parse_args(argv)
    if not to_date(a.since):
        ap.error("--since は YYYY-MM-DD")
    out = collect(to_date(a.since), a.me, max_calls=a.max_calls)
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
