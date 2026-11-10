#!/usr/bin/env python3
"""
Claude Code セッション JSONL から、要約に必要な情報だけを抽出する。

会話の text ブロックと、ツール使用のメタ情報（ツール名・編集ファイルパス・
Bash コマンド）を残し、巨大な tool_result 本体は捨てる。これにより
Haiku の 200K コンテキストに確実に収まり、ノイズも除去される。

使用方法:
    python3 extract.py <transcript.jsonl> [--since ISO8601] [--until ISO8601]
--since は含む、--until は含まない。範囲指定時は timestamp の無い行を捨てる。
標準出力に整形済みテキストを出す。JSONL が読めない場合は exit 1。
"""
import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


def parse_iso(value: str) -> datetime:
    """タイムゾーン付き ISO 8601 を aware datetime にする（Z は +00:00 に読み替える）。"""
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        raise ValueError(f"タイムゾーンがありません: {value}")
    return dt


def main() -> int:
    ap = argparse.ArgumentParser(description="Claude Code セッション JSONL から要約用テキストを抽出する")
    ap.add_argument("transcript")
    ap.add_argument("--since", default=None)
    ap.add_argument("--until", default=None)
    args = ap.parse_args()

    try:
        since = parse_iso(args.since) if args.since else None
        until = parse_iso(args.until) if args.until else None
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    ranged = since is not None or until is not None

    path = Path(args.transcript)
    if not path.is_file():
        print(f"ERROR: ファイルが見つかりません: {path}", file=sys.stderr)
        return 1

    cwd = ""
    session_id = ""
    session_start = ""
    first_ts = ""
    last_ts = ""
    lines_out: list[str] = []
    entrypoint = ""

    with path.open(encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            try:
                d = json.loads(raw)
            except json.JSONDecodeError:
                continue

            # entrypoint（対話/非対話の弁別子）を最初に見つけた値で確定する
            if not entrypoint:
                _ep = d.get("entrypoint")
                if isinstance(_ep, str) and _ep:
                    entrypoint = _ep

            if d.get("type") not in ("user", "assistant"):
                continue

            # メタ情報を拾う（最初に出てきた値を採用）
            if not cwd:
                _cwd = d.get("cwd")
                if isinstance(_cwd, str) and _cwd:
                    cwd = _cwd
            if not session_id and d.get("sessionId"):
                session_id = d["sessionId"]
            ts = d.get("timestamp", "")
            if ts and not session_start:
                session_start = ts

            if ranged:
                # timestamp が無い・読めない行は範囲に属するか判定できないので捨てる
                try:
                    t = parse_iso(ts)
                except (ValueError, TypeError, AttributeError):
                    continue
                if (since is not None and t < since) or (until is not None and t >= until):
                    continue

            if ts:
                if not first_ts:
                    first_ts = ts
                last_ts = ts

            role = "User" if d["type"] == "user" else "Claude"
            content = (d.get("message") or {}).get("content", "")

            if isinstance(content, str):
                text = content.strip()
                if text:
                    lines_out.append(f"**{role}:** {text}")
                continue

            if not isinstance(content, list):
                continue

            for item in content:
                if not isinstance(item, dict):
                    continue
                itype = item.get("type")
                if itype == "text":
                    text = str(item.get("text", "")).strip()
                    if text:
                        lines_out.append(f"**{role}:** {text}")
                elif itype == "tool_use":
                    name = item.get("name", "?")
                    inp = item.get("input", {})
                    if not isinstance(inp, dict):
                        inp = {}
                    # ツールごとに要約に有用なメタだけ抜く
                    if name in ("Edit", "Write", "Read", "NotebookEdit"):
                        meta = str(inp.get("file_path", ""))
                    elif name == "Bash":
                        meta = str(inp.get("command", ""))[:120]
                    elif name in ("Grep", "Glob"):
                        meta = str(inp.get("pattern", ""))
                    else:
                        meta = ""
                    lines_out.append(f"  [tool:{name}] {meta}".rstrip())
                # tool_result は本体を捨てる（要約に不要・巨大）

    # sdk-cli(claude -p) / sdk-py(Python SDK) は非対話の自動生成実行。
    # 要約対象外（summarize.sh の自己参照ループ防止）。明示的にこの2値の時だけ弾き、
    # cli および entrypoint 欠落は通す（安全側=include）。
    if entrypoint in ("sdk-cli", "sdk-py"):
        # ヘッダのみ出力し本文は空にする → summarize.sh の「本文空なら要約しない」ガードに乗る
        lines_out = []

    project = Path(cwd).name if cwd else "unknown"
    header = [
        f"project: {project}",
        f"session_id: {session_id}",
        f"cwd: {cwd}",
        f"session_start: {session_start}",
        f"start: {first_ts}",
        f"end: {last_ts}",
        "---",
    ]
    print("\n".join(header))
    print("\n".join(lines_out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
