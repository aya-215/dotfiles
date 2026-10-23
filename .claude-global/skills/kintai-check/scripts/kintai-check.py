"""総務パック 00296（勤務時間記録・勤怠えびす）から、月の実働が「出社日数×8h」に届いているかを判定する。

usage:
  kintai-check.py [YYYY/MM] [--fiscal-year]

  YYYY/MM        対象月（省略時は今月）
  --fiscal-year  対象月を含む年度（4月始まり）で、未達月の30分以上遅刻を数える

設定:
  - MCP の接続先は ~/.dotfiles/.mcp.json の mcpServers["eb-api-somu"] から読む（gitignore 済み）
  - 自分のアイテムIDは同じフォルダの config.local.json {"item_id": "t0001..."} に置く（gitignore 済み）
"""
import argparse
import calendar
import datetime
import json
import os
import sys
import urllib.request

MCP_JSON = os.path.expanduser("~/.dotfiles/.mcp.json")
CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config.local.json")
VOLUME = "00296"
WD = "月火水木金土日"
LATE_MIN = 30
DAY_MIN = 480


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def load_settings():
    try:
        server = json.load(open(MCP_JSON))["mcpServers"]["eb-api-somu"]
    except (OSError, KeyError, json.JSONDecodeError):
        die(f"{MCP_JSON} に eb-api-somu の定義が無い")
    try:
        item_id = json.load(open(CONFIG))["item_id"]
    except (OSError, KeyError, json.JSONDecodeError):
        die(f"{os.path.normpath(CONFIG)} に item_id が無い。00296 で自分の氏名を検索して item_id を書くこと")
    return server["url"], server.get("headers", {}), item_id


def fetch_month(url, headers, item_id, year, month):
    days = [datetime.date(year, month, d) for d in range(1, calendar.monthrange(year, month)[1] + 1)]
    titles = [f"{d:%Y/%m/%d}（{WD[d.weekday()]}）" for d in days]
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": "eb_api_getSpecDataLite",
                       "arguments": {"volume_id": VOLUME, "item_ids": [item_id], "no_cache": True,
                                     "specs": [{"spec_type": "勤務時間記録", "spec_title": t} for t in titles]}}}
    req = urllib.request.Request(url, json.dumps(body).encode(), {
        "Content-Type": "application/json", "Accept": "application/json, text/event-stream", **headers})
    try:
        raw = urllib.request.urlopen(req, timeout=120).read().decode()
    except OSError as e:
        die(f"MCP に接続できへん: {e}")
    data = next((l[5:] for l in raw.splitlines() if l.startswith("data:")), None)
    if data is None:
        die("MCP の応答に data 行が無い")
    text = json.loads(data)["result"]["content"][0]["text"]
    specs = json.loads(text)["response"]["data"]["item"]["spec"]
    vals = {s["spec_title"]: s.get("value", "") for s in specs if "spec_title" in s}
    return [(d, vals.get(t, "")) for d, t in zip(days, titles)]


def mins(hhmm):
    if not hhmm:
        return 0
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def fmt(m):
    sign = "-" if m < 0 else "+"
    m = abs(m)
    return f"{sign}{m // 60}:{m % 60:02d}"


def summarize(rows, today):
    """日別値を 実績（昨日まで）と予定（今日以降）に分けて集計する。

    日別値はカンマ区切りで [0]出社 [1]退社 [2]理由 [4]実働(休憩控除後) [18]所定開始。
    今日以降の日は打刻前でも所定時刻が予定値として埋まっているため実績に混ぜない。
    """
    s = {"days": 0, "work": 0, "plan_days": 0, "plan_work": 0, "lates": []}
    for d, raw in rows:
        f = raw.split(",") + [""] * 30
        cin, note, work, sched_in = f[0], f[2], mins(f[4]), f[18] or "09:30"
        if not cin and not work:
            continue
        if d >= today:
            s["plan_days"] += 1
            s["plan_work"] += work
            continue
        s["days"] += 1
        s["work"] += work
        late = mins(cin) - mins(sched_in) if cin else 0
        if late >= LATE_MIN:
            s["lates"].append((d, cin, late, note))
    s["diff"] = s["work"] - s["days"] * DAY_MIN
    s["plan_diff"] = s["diff"] + s["plan_work"] - s["plan_days"] * DAY_MIN
    return s


def print_month(ym, s, is_current):
    print(f"## {ym}")
    verdict = "足りている" if s["diff"] >= 0 else "足りていない"
    print(f"実績: 出社{s['days']}日 実働{fmt(s['work'])[1:]} 基準{fmt(s['days'] * DAY_MIN)[1:]} 差{fmt(s['diff'])} → {verdict}")
    if is_current and s["plan_days"]:
        pv = "足りる" if s["plan_diff"] >= 0 else "足りない"
        print(f"見込み: 残り{s['plan_days']}日を勤怠えびすの予定値どおり働いた場合 差{fmt(s['plan_diff'])} → {pv}")
    print(f"30分以上の遅刻: {len(s['lates'])}回（月末で差がマイナスなら、この回数が年度の遅刻カウントに入る）")
    for d, cin, late, note in s["lates"]:
        print(f"  {d:%m/%d}({WD[d.weekday()]}) 出社{cin} 遅刻{fmt(late)[1:]} {note}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("month", nargs="?")
    ap.add_argument("--fiscal-year", action="store_true")
    args = ap.parse_args()

    today = datetime.date.today()
    if args.month:
        try:
            y, m = map(int, args.month.split("/"))
            datetime.date(y, m, 1)
        except ValueError:
            die("月は YYYY/MM で指定する")
    else:
        y, m = today.year, today.month
    url, headers, item_id = load_settings()
    is_current = (y, m) == (today.year, today.month)

    s = summarize(fetch_month(url, headers, item_id, y, m), today)
    print_month(f"{y}/{m:02d}", s, is_current)

    if not args.fiscal_year:
        return
    fy = y if m >= 4 else y - 1
    print(f"\n## {fy}年度（{fy}/04〜）未達月の30分以上遅刻")
    total = 0
    cy, cm = fy, 4
    while (cy, cm) < (y, m):
        ms = summarize(fetch_month(url, headers, item_id, cy, cm), today)
        counted = len(ms["lates"]) if ms["diff"] < 0 else 0
        total += counted
        mark = f"未達 → {counted}回カウント" if ms["diff"] < 0 else "達成 → 0回"
        print(f"{cy}/{cm:02d}: 差{fmt(ms['diff'])} 遅刻{len(ms['lates'])}回 {mark}")
        cy, cm = (cy + 1, 1) if cm == 12 else (cy, cm + 1)
    this = len(s["lates"]) if s["diff"] < 0 else 0
    print(f"{y}/{m:02d}: 差{fmt(s['diff'])}（実績時点） 遅刻{len(s['lates'])}回 → 現時点で{this}回カウント")
    print(f"年度累計: {total + this}回（10回以上でNG）。今月が未達で終わると {total + len(s['lates'])}回")


if __name__ == "__main__":
    main()
