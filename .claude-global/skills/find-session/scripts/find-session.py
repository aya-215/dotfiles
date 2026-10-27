#!/usr/bin/env python3
"""過去の Claude Code セッションを要約・トランスクリプトから探す。

使い方:
  find-session.py search  TERMS...            要約を検索する
  find-session.py search  --transcripts TERMS...  jsonl（会話本文とタイトル）を検索する
  find-session.py show    SESSION_ID            要約本文・cwd・resume コマンドを出す
  find-session.py excerpt SESSION_ID TERMS...   jsonl の会話本文から該当発言を抜き出す

TERMS: 引数ごとに AND、引数の中の `|` で OR。大文字小文字・全角半角は区別しない。
  例: "JSESSION|Cookie|401" "Apache|httpd|ProxyErrorOverride"

環境変数: SESSIONS_ROOT（要約）/ PROJECTS_ROOT（jsonl）
"""

import argparse
import json
import os
import re
import sys
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

SESSIONS_ROOT = Path(os.environ.get("SESSIONS_ROOT", Path.home() / ".nb/claude/sessions"))
PROJECTS_ROOT = Path(os.environ.get("PROJECTS_ROOT", Path.home() / ".claude/projects"))
# 会話本文として扱わないシステム由来のテキスト
NOISE_PREFIX = re.compile(r"^\s*<(local-command|system-reminder|task-notification|command-message)")
COMMAND_ARGS = re.compile(r"<command-(name|args)>(.*?)</command-\1>", re.S)


def norm(s):
    return unicodedata.normalize("NFKC", s).casefold()


def parse_terms(raw):
    groups = [[norm(t) for t in arg.split("|") if t.strip()] for arg in raw]
    return [g for g in groups if g]


def match(text, groups):
    """各 AND グループで当たった語と総ヒット数を返す。"""
    t = norm(text)
    matched, hits = [], 0
    for g in groups:
        found = [w for w in g if w in t]
        if found:
            matched.append(found)
            hits += sum(t.count(w) for w in found)
    return matched, hits


def jsonl_index():
    # 実行中のセッション自身は検索語を含むので必ず当たってしまう
    current = os.environ.get("CLAUDE_CODE_SESSION_ID")
    return {p.stem: p for p in PROJECTS_ROOT.glob("*/*.jsonl") if p.stem != current}


def frontmatter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}
    return dict(line.split(": ", 1) for line in m.group(1).splitlines() if ": " in line)


def section(text, name):
    m = re.search(rf"^## {name}\n+(.+?)$", text, re.M)
    return m.group(1).strip() if m else ""


def local_time(iso):
    try:
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return iso


def summary_date(s):
    if s["fm"].get("start"):
        return local_time(s["fm"]["start"])
    # 初期の要約は start を持たないため、日付フォルダとファイル名の HHMM で代用する
    m = re.search(r"-(\d{2})(\d{2})-[0-9a-f]{8}\.md$", s["path"].name)
    return s["path"].parent.name + (f" {m.group(1)}:{m.group(2)}" if m else "")


def load_summaries():
    """session_id ごとに最新の要約を返す（resume 後に閉じ直すと要約が複数できる）。"""
    by_id = {}
    # ".dotfiles-*.md" のようにドットで始まる要約があるため rglob で隠しファイルも拾う
    for p in SESSIONS_ROOT.rglob("*.md"):
        text = p.read_text(encoding="utf-8", errors="replace")
        fm = frontmatter(text)
        sid = fm.get("session_id")
        if not sid:
            continue
        if sid not in by_id or fm.get("end", "") > by_id[sid]["fm"].get("end", ""):
            by_id[sid] = {"path": p, "text": text, "fm": fm}
    return by_id


def transcript(path):
    """jsonl から title・cwd・会話本文（ユーザーとアシスタントの text、コマンド引数）を取り出す。"""
    title_custom = title_ai = cwd = start = ""
    lines = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            try:
                e = json.loads(raw)
            except ValueError:
                continue
            t = e.get("type")
            if t == "custom-title":
                title_custom = e.get("customTitle", "")
            elif t == "ai-title":
                title_ai = e.get("aiTitle", "")
            if t not in ("user", "assistant") or e.get("isMeta"):
                continue
            cwd = cwd or e.get("cwd", "")
            start = start or e.get("timestamp", "")
            content = e.get("message", {}).get("content")
            texts = [content] if isinstance(content, str) else [
                c.get("text", "") for c in content or [] if isinstance(c, dict) and c.get("type") == "text"]
            for s in texts:
                args = COMMAND_ARGS.findall(s)
                if args:
                    s = " ".join(v for _, v in args)
                elif NOISE_PREFIX.match(s):
                    continue
                if s.strip():
                    lines.append((t, " ".join(s.split())))
    return {"title": title_custom or title_ai, "cwd": cwd, "start": start, "lines": lines}


def resume_cmd(sid, cwd, jsonl):
    if not jsonl:
        return "（jsonl 削除済みのため resume 不可。中身の取り出しのみ）"
    note = "" if cwd and Path(cwd).is_dir() else "  ※cwd が存在しない（worktree 削除済み等）"
    return f"cd {cwd} && claude -r {sid}{note}"


def print_rows(rows, groups, limit):
    full = [r for r in rows if len(r["matched"]) == len(groups)]
    partial = [r for r in rows if 0 < len(r["matched"]) < len(groups)]
    key = lambda r: (r["hits"], r["date"])
    full.sort(key=key, reverse=True)
    partial.sort(key=lambda r: (len(r["matched"]), r["hits"], r["date"]), reverse=True)
    print(f"# 全条件一致 {len(full)} 件 / 一部一致 {len(partial)} 件")
    shown = full[:limit] or partial[:limit]
    if not full and partial:
        print("# 全条件一致なし。一部一致を表示")
    for r in shown:
        terms = ",".join(w for g in r["matched"] for w in g)
        print(f"- {r['date']} | {r['project']} | {r['sid']} | resume:{'可' if r['jsonl'] else '不可'} | hits:{r['hits']} [{terms}]")
        if r["title"]:
            print(f"    title: {r['title']}")
        if r["intent"]:
            print(f"    意図: {r['intent'][:160]}")


def cmd_search(a):
    groups = parse_terms(a.terms)
    if not groups:
        sys.exit("検索語がない")
    jsonls = jsonl_index()
    summaries = load_summaries()
    rows = []
    if a.transcripts:
        for sid, path in jsonls.items():
            tr = transcript(path)
            body = tr["title"] + "\n" + "\n".join(s for _, s in tr["lines"])
            matched, hits = match(body, groups)
            if matched:
                s = summaries.get(sid)
                rows.append({"sid": sid, "date": local_time(tr["start"]), "project": Path(tr["cwd"]).name,
                             "jsonl": path, "title": tr["title"], "matched": matched, "hits": hits,
                             "intent": section(s["text"], "意図") if s else "（要約なし）"})
    else:
        for sid, s in summaries.items():
            matched, hits = match(s["text"], groups)
            if matched:
                rows.append({"sid": sid, "date": summary_date(s),
                             "project": s["fm"].get("project", ""), "jsonl": jsonls.get(sid),
                             "title": "", "matched": matched, "hits": hits, "intent": section(s["text"], "意図")})
    print_rows(rows, groups, a.limit)


def find_sid(prefix, candidates):
    hits = [s for s in candidates if s.startswith(prefix)]
    if len(hits) != 1:
        sys.exit(f"session_id '{prefix}' に一致するものが {len(hits)} 件")
    return hits[0]


def cmd_show(a):
    summaries = load_summaries()
    jsonls = jsonl_index()
    sid = find_sid(a.session_id, set(summaries) | set(jsonls))
    jsonl = jsonls.get(sid)
    tr = transcript(jsonl) if jsonl else {}
    s = summaries.get(sid)
    cwd = (s["fm"].get("cwd") if s else "") or tr.get("cwd", "")
    print(f"session_id: {sid}")
    print(f"title: {tr.get('title', '')}")
    print(f"cwd: {cwd}")
    print(f"jsonl: {jsonl or 'なし'}" + (f"（会話 {len(tr['lines'])} 発言）" if jsonl else ""))
    print(f"resume: {resume_cmd(sid, cwd, jsonl)}")
    print(f"summary: {s['path'] if s else 'なし'}")
    if s:
        print("\n" + s["text"])


def cmd_excerpt(a):
    jsonls = jsonl_index()
    sid = find_sid(a.session_id, jsonls)
    groups = parse_terms(a.terms)
    lines = transcript(jsonls[sid])["lines"]
    shown = 0
    for i, (role, s) in enumerate(lines):
        if groups and not any(w in norm(s) for g in groups for w in g):
            continue
        print(f"[{i}] {role}: {s[:a.width]}")
        shown += 1
        if shown >= a.limit:
            print(f"# 上限 {a.limit} 件で打ち切り")
            break
    print(f"# {shown} 件 / 全 {len(lines)} 発言")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search")
    s.add_argument("terms", nargs="+")
    s.add_argument("--transcripts", action="store_true")
    s.add_argument("--limit", type=int, default=10)
    s.set_defaults(func=cmd_search)
    s = sub.add_parser("show")
    s.add_argument("session_id")
    s.set_defaults(func=cmd_show)
    s = sub.add_parser("excerpt")
    s.add_argument("session_id")
    s.add_argument("terms", nargs="*")
    s.add_argument("--limit", type=int, default=30)
    s.add_argument("--width", type=int, default=400)
    s.set_defaults(func=cmd_excerpt)
    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
