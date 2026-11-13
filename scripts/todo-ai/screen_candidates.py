#!/usr/bin/env python3
"""/my-tasks --json の候補に、自分のメモ（日報・セッション要約）だけが根拠かの印を付ける。

使い方: screen_candidates.py <my-tasks.json>
  候補ごとに "self_note_only": true|false を足した JSON を標準出力に、
  印の付いた候補の題を1行1件で標準エラーに出す。入力がスキーマ違反なら終了コード 1。
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import my_tasks_schema

SELF_NOTES = frozenset(("daily", "sessions"))


def self_note_only(c: dict) -> bool:
    """key が無く、根拠が日報・セッション要約だけの候補か。"""
    return c.get("key") is None and set(c["sources"]) <= SELF_NOTES


def screen(data: dict) -> dict:
    for c in data["candidates"]:
        c["self_note_only"] = self_note_only(c)
    return data


def main(argv) -> int:
    if len(argv) != 2:
        print("usage: screen_candidates.py <my-tasks.json>", file=sys.stderr)
        return 2
    try:
        data = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"screen_candidates: 読めない: {e}", file=sys.stderr)
        return 1
    errs = my_tasks_schema.validate_candidates(data)
    if errs:
        for e in errs:
            print(e, file=sys.stderr)
        return 1
    out = screen(data)
    for c in out["candidates"]:
        if c["self_note_only"]:
            print(f"self_note_only: {c['title']}", file=sys.stderr)
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
