#!/usr/bin/env python3
"""Thunderbird のメールを収集し、日報向けに整形して stdout へ出す。

thunderbird.sh から環境変数経由で呼ばれる実装本体。
シェルで JSON-RPC とスレッド集約を書くと可読性が落ちるため Python に分離した。

採用は2段構え:
  1. to/cc/bcc に自分または ai-team が入っているもの（＋Sent は無条件）で母集団を絞る
  2. そこから既知のノイズ送信元・件名パターンを引く

除外リストの調整はこのファイル先頭の定数だけで済むようにしてある。
"""
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from datetime import date, timedelta

MCP_ENTRY = os.environ["TB_MCP_ENTRY"]

# 自分を指す識別子。gloda の recipients は表示名だけでアドレスが落ちるケースが
# あるため（実データで確認済み）、アドレスと表示名の両方を見る。
ME_PATTERNS = ("mori.a@ebase.co.jp", "森 彪人", "森彪人")
# AIチームML。自分が to/cc から漏れてもチーム宛なら拾う保険。
TEAM_PATTERNS = ("ai-team@ebase.co.jp",)

# --- 除外リスト（ここを足し引きすれば調整できる） ---

# 自動送信・通知系の送信元。1ヶ月1303件のうち773件がこの5つだった。
EXCLUDE_AUTHORS = {
    "notifications@github.com",   # GitHub通知。gitログと重複する
    "info-001@ebase.co.jp",       # 社内一斉配信（不具合DB件数・仕入先説明会等）
    "notice-pdmebase@ebase.co.jp",  # PDMeBASE案件通知
    "kintai@ebase.co.jp",         # 勤怠集約通知（1日4通ペース）
    "no-reply@ebase.co.jp",       # GitBucket の PR 通知
    "schedule@ebase.co.jp",       # グループウェア予定通知。更新1回ごとに飛ぶ
    "noreply@atcoder.jp",         # AtCoder コンテスト告知
}

# SaaS からのサービス通知。本文を見ても作業実績にならない送信元ドメイン。
EXCLUDE_AUTHOR_DOMAINS = (
    "@mail.anthropic.com",
    "@email.claude.com",
    "@coderabbit.ai",
    "coderabbitai@",
    "@github.com",           # notifications@ 以外の GitHub 通知（permissions 等）
    "@langchain.dev",
    "@mail.langchain.com",
    "@tm.openai.com",
)

# 庶務・社内行事。件名で落とす（送信元は人間なのでアドレスでは切れない）。
EXCLUDE_SUBJECT_RE = re.compile(
    r"掃除当番|懇親会|忘年会|新年会|歓迎会|備品等発注|健康診断|"
    r"早退連絡|早退報告|遅刻連絡|欠勤連絡"
)

# claude-code@ / claude-code2@ の受信箱。Anthropic のマジックリンクが大半。
EXCLUDE_FOLDERS = {"受信トレイ", "ごみ箱", "Trash", "Drafts", "Unsent Messages"}

SENT_FOLDER = "Sent"

# search_messages は query 必須かつ 100件上限。日本語メールで頻出の語を複数投げて
# 和集合を取り、2日窓で回すことで上限を回避する。
# （list_recent の days は上限が日付フィルタより先に効くため1ヶ月取得に使えない）
QUERIES = ("の", "を", "ます", "した", "eBASE", "com", "ご", "お", "件", "test")
WINDOW_DAYS = 2

# 自分が返信したスレッドは本文を全文取得する（日報で「何を相談され何を答えたか」を
# 残すため）。参考スレッドは snippet のみ。1通あたりの本文はこの長さで切る。
BODY_CHARS = 700
# 「一度でも返信したスレッド」判定のために遡る日数。
SENT_LOOKBACK_DAYS = 60
# --full-thread 時の1通あたり本文長。要約層に渡す用途では切り詰めを緩める
# （日報ペイロードに直接載せる BODY_CHARS とは別枠）。
BODY_CHARS_FULL = 3000
# 日本語メールの定型末尾。ここ以降は署名なので落とす。
SIGNATURE_RE = re.compile(
    r"\n\s*(--\s*\n|::::+|-----Original Message-----|"
    r"^\s*(?:eBASE株式会社|以上、?\s*(?:宜しく|よろしく)))",
    re.MULTILINE,
)
QUOTE_RE = re.compile(r"^\s*(?:>|＞)", re.MULTILINE)


def call_mcp(tool, args):
    """MCP サーバを stdio で叩いて結果の配列を返す。"""
    msgs = [
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "thunderbird.sh", "version": "1"}}}),
        json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}),
        json.dumps({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                    "params": {"name": tool, "arguments": args}}),
    ]
    try:
        p = subprocess.run(["node", MCP_ENTRY], input="\n".join(msgs) + "\n",
                           capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return []
    for line in p.stdout.splitlines():
        if '"id":3' in line:
            try:
                return json.loads(json.loads(line)["result"]["content"][0]["text"])
            except (KeyError, ValueError, IndexError):
                return []
    return []


def fetch(from_d, to_d):
    """期間内のメールを messageId で重複排除して集める。"""
    seen = {}
    cur = from_d
    while cur <= to_d:
        nxt = min(cur + timedelta(days=WINDOW_DAYS), to_d + timedelta(days=1))
        for q in QUERIES:
            for m in call_mcp("search_messages", {
                    "query": q, "after": cur.isoformat(),
                    "before": nxt.isoformat(), "limit": 100}):
                seen[m["messageId"]] = m
        cur = nxt
    return list(seen.values())


def addr(author):
    m = re.search(r"<([^>]+)>", author or "")
    return (m.group(1) if m else (author or "")).strip().lower()


def display_name(author):
    name = re.sub(r"\s*<[^>]*>.*$", "", author or "").replace("undefined", "").strip()
    return name or addr(author)


def addressed_to_me(msg):
    """to/cc/bcc に自分または ai-team が入っているか。"""
    field = (msg.get("recipients") or "")
    low = field.lower()
    if any(p.lower() in low for p in ME_PATTERNS if "@" in p):
        return True
    if any(p in field for p in ME_PATTERNS if "@" not in p):
        return True
    return any(p.lower() in low for p in TEAM_PATTERNS)


def clean_body(text, limit=None):
    """署名・引用行・空行の連続を落として本文の要点だけ残す。"""
    if not text:
        return ""
    limit = BODY_CHARS if limit is None else limit
    body = SIGNATURE_RE.split(text)[0]
    lines = [ln.rstrip() for ln in body.splitlines() if not QUOTE_RE.match(ln)]
    out, blank = [], False
    for ln in lines:
        if not ln.strip():
            if blank or not out:
                continue
            blank = True
        else:
            blank = False
        out.append(ln.strip())
    joined = "\n".join(out).strip()
    if len(joined) > limit:
        joined = joined[:limit].rstrip() + "…"
    return joined


def fetch_body(message_id, limit=None):
    """get_message で本文を取る。取得できなければ空文字を返す。"""
    r = call_mcp("get_message", {"messageId": message_id})
    if isinstance(r, dict):
        return clean_body(r.get("body") or r.get("text") or "", limit)
    if isinstance(r, list) and r:
        first = r[0]
        if isinstance(first, dict):
            return clean_body(first.get("body") or first.get("text") or "", limit)
    return ""


def fetch_thread(conversation_id):
    """get_thread でスレッド全体を取る。対象日より前の経緯も含める用途。"""
    r = call_mcp("get_thread", {"conversationId": conversation_id})
    if isinstance(r, dict):
        r = r.get("messages") or []
    return r if isinstance(r, list) else []


def normalize_subject(subject):
    s = re.sub(r"^((RE|Re|FW|Fw|Fwd|返信|転送)\s*:\s*)+", "", subject or "")
    return s.strip() or "(件名なし)"


def main():
    from_d = date.fromisoformat(os.environ["TB_FROM"])
    to_d = date.fromisoformat(os.environ["TB_TO"])
    budget = int(os.environ.get("TB_BUDGET") or 0)

    allm = fetch(from_d, to_d)

    if os.environ.get("TB_RAW") == "1":
        json.dump(allm, sys.stdout, ensure_ascii=False, indent=1)
        return

    # 「一度でも返信したスレッド」を最優先扱いにするため、対象期間より前の Sent も
    # 遡って conversationId を集める。日次実行だと前日に返信したスレッドの続きが
    # 参考扱いに落ちてしまうため（実データ: 8/6 のシフトオン6通）。
    #
    # ここは fetch() を使わない。fetch() は全フォルダを対象に2日窓×10クエリで回すため
    # 60日遡ると数百回の呼び出しになり cron で使える速度に収まらない。Sent は
    # 流量が桁違いに少ない（1ヶ月17通）ので、folder 絞り込みで一括取得できる。
    replied_conv = set()
    for q in QUERIES:
        for m in call_mcp("search_messages", {
                "query": q, "folder": SENT_FOLDER,
                "after": (from_d - timedelta(days=SENT_LOOKBACK_DAYS)).isoformat(),
                "before": from_d.isoformat(), "limit": 100}):
            replied_conv.add(m.get("conversationId"))

    # 1. 母集団を絞る（Sent は無条件、それ以外は宛先判定）
    sent = [m for m in allm if m.get("folder") == SENT_FOLDER]
    inbox = [m for m in allm
             if m.get("folder") != SENT_FOLDER
             and m.get("folder") not in EXCLUDE_FOLDERS
             and addressed_to_me(m)]
    after_scope = len(sent) + len(inbox)

    # 2. 既知ノイズを引く
    def keep(m):
        a = addr(m.get("author", ""))
        if a in EXCLUDE_AUTHORS:
            return False
        if any(dom in a for dom in EXCLUDE_AUTHOR_DOMAINS):
            return False
        return not EXCLUDE_SUBJECT_RE.search(m.get("subject") or "")

    sent = [m for m in sent if keep(m)]
    inbox = [m for m in inbox if keep(m)]

    if os.environ.get("TB_STATS") == "1":
        print(f"取得(全件)      : {len(allm)}")
        print(f"母集団(宛先絞込): {after_scope}")
        print(f"ノイズ除去後    : {len(sent) + len(inbox)}  (Sent {len(sent)} / Inbox {len(inbox)})")
        return

    # 3. conversationId でスレッド集約
    sent_conv = {m.get("conversationId") for m in sent} | replied_conv
    threads = defaultdict(list)
    for m in sent + inbox:
        threads[m.get("conversationId")].append(m)

    rows = []
    for cid, msgs in threads.items():
        msgs.sort(key=lambda x: x.get("date", ""))
        last = msgs[-1]
        # 自分以外の参加者を、やりとり相手として拾う
        others, seen_names = [], set()
        for m in msgs:
            if m.get("folder") == SENT_FOLDER:
                continue
            n = display_name(m.get("author", ""))
            if n and n not in seen_names:
                seen_names.add(n)
                others.append(n)
        rows.append({
            "replied": cid in sent_conv,
            "date": last.get("date", "")[:10],
            "subject": normalize_subject(last.get("subject")),
            "count": len(msgs),
            "sent_count": sum(1 for m in msgs if m.get("folder") == SENT_FOLDER),
            "others": others[:4],
            "msgs": msgs,
        })

    # 自分が返信済みを最優先、次に往復数、次に新しい順
    rows.sort(key=lambda r: (not r["replied"], -r["count"], r["date"]), reverse=False)

    out = []
    replied = [r for r in rows if r["replied"]]
    other = [r for r in rows if not r["replied"]]

    # --replied-only: 一度でも返信したスレッドだけを残す。他人同士のやりとりを
    # CC で受けているだけのスレッドは自分の作業ではないため落とす。
    # 「一度でも」の判定は SENT_LOOKBACK_DAYS 分遡った Sent を含む（当日の返信は不要）。
    if os.environ.get("TB_REPLIED_ONLY") == "1":
        other = []

    def header(r):
        who = "、".join(r["others"]) if r["others"] else "(送信のみ)"
        detail = f"{r['count']}通"
        if r["sent_count"]:
            detail += f"・自分の返信{r['sent_count']}通"
        return f"{r['subject']}（{who} / {detail} / 最終 {r['date']}）"

    no_body = os.environ.get("TB_NO_BODY") == "1"

    # --full-thread: 要約層に渡すため、対象日より前の経緯も含めてスレッド全体を出す。
    # get_thread は1回の呼び出しでスレッド全通を body 付きで返すので、
    # 当日分の messageId ごとに get_message するより呼び出し回数が少ない。
    if os.environ.get("TB_FULL_THREAD") == "1":
        for r in replied + other:
            cid = r["msgs"][0].get("conversationId")
            msgs = fetch_thread(cid) or r["msgs"]
            out.append("")
            out.append(f"#### {header(r)}")
            out.append(f"（スレッド全体 {len(msgs)}通。対象期間の活動: "
                       f"{r['count']}通・自分の返信{r['sent_count']}通）")
            for m in sorted(msgs, key=lambda x: x.get("date", "")):
                body = clean_body(m.get("body") or m.get("snippet") or "",
                                  BODY_CHARS_FULL) or "(本文なし)"
                mark = ("自分" if m.get("folder") == SENT_FOLDER
                        else display_name(m.get("author", "")))
                in_range = m.get("date", "")[:10] >= os.environ["TB_FROM"]
                flag = " ★対象期間" if in_range else ""
                out.append(f"- **{m.get('date','')[:16]} {mark}**{flag}")
                out.extend(f"  {ln}" for ln in body.splitlines())
        text = "\n".join(out).strip()
        print(text if text else "(メールなし)")
        return

    if replied:
        label = "（最優先）" if no_body else "（最優先・本文あり）"
        out.append(f"### 自分が返信したスレッド{label}")
        if no_body:
            out.extend(f"- {header(r)}" for r in replied)
        else:
            for r in replied:
                out.append("")
                out.append(f"#### {header(r)}")
                for m in r["msgs"]:
                    body = fetch_body(m["messageId"])
                    if not body:
                        body = clean_body(m.get("snippet") or "") or "(本文なし)"
                    mark = ("自分" if m.get("folder") == SENT_FOLDER
                            else display_name(m.get("author", "")))
                    out.append(f"- **{m.get('date','')[:16]} {mark}**")
                    out.extend(f"  {ln}" for ln in body.splitlines())
    if other:
        if replied:
            out.append("")
        out.append("### 宛先に入っていたスレッド（参考・件名のみ）")
        for r in other:
            out.append(f"- {header(r)}")
            if no_body:
                continue
            snippet = clean_body(r["msgs"][-1].get("snippet") or "").replace("\n", " ")[:120]
            if snippet:
                out.append(f"  └ {snippet}")

    if not out:
        print("(メールなし)")
        return

    text = "\n".join(out)
    if budget and len(text) > budget:
        # 予算超過時は参考セクションを丸ごと落とす（本文付きの最優先を残す）
        idx = text.find("### 宛先に入っていたスレッド")
        if idx > 0:
            text = text[:idx].rstrip()
        if len(text) > budget:
            text = text[:budget].rstrip()
        text += "\n（※ 文字数上限のため一部を省略）"
    print(text)


if __name__ == "__main__":
    main()
