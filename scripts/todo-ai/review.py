#!/usr/bin/env python3
"""週次見直し用に、人の訂正を AI の判断（reason・evidence）と並べた Markdown 表を出す。

使い方: review.py --since YYYY-MM-DD [--decisions PATH] [--logs DIR]
過去の /todo ログを読む唯一の場所（AI の過去判断の評価が目的で、タスクの根拠には使わない）。
"""
import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import decisions

DEFAULT_LOGS = Path.home() / ".local" / "log" / "todo-ai"
HEADER = "| 日付 | ref | 人がしたこと | AI がしたこと | AI の根拠 | my-tasks の根拠 | ball |\n|---|---|---|---|---|---|---|\n"


def _cell(v) -> str:
    s = "-" if v in (None, "") else str(v)
    return s.replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ")


def _read(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _op_text(op: dict) -> str:
    name = op.get("op", "?")
    if name == "add":
        return f"add → {op.get('section', '-')}"
    if name == "move":
        return f"move → {op.get('to', '-')}"
    if name == "attach":
        return f"attach {op.get('key', '-')}"
    return name


def _find_ai(logs: Path, dates: "list[str]", day: str, ref: str):
    """record の日以前で最も新しい日の、ref を触った op か確認待ち。"""
    for d in dates:
        if d > day:
            continue
        data = _read(logs / d / "changes.json")
        if not isinstance(data, dict):
            continue
        for op in reversed(data.get("ops") or []):
            if isinstance(op, dict) and ref in (op.get("ref"), op.get("key")):
                return _op_text(op), op.get("reason")
        for c in reversed(data.get("confirm") or []):
            if isinstance(c, dict) and c.get("ref") == ref:
                return f"確認待ち({c.get('kind', '-')}): {c.get('question', '-')}", c.get("facts")
    return None, None


def _find_candidate(logs: Path, dates: "list[str]", day: str, ref: str):
    for d in dates:
        if d > day:
            continue
        data = _read(logs / d / "my-tasks.json")
        if not isinstance(data, dict):
            continue
        for c in data.get("candidates") or []:
            if isinstance(c, dict) and c.get("key") == ref:
                return c.get("evidence"), c.get("ball")
    return None, None


def render(decisions_path: Path, logs: Path, since: str) -> str:
    recs = [r for r in decisions.load(decisions_path)
            if r.get("by", "human") == "human" and str(r.get("ts", ""))[:10] >= since]
    if not recs:
        return f"{since} 以降の人の訂正なし\n"
    logs = Path(logs)
    try:
        dates = sorted((p.name for p in logs.iterdir() if p.is_dir()), reverse=True)
    except OSError:
        dates = []
    rows = []
    for r in recs:
        ref, day = str(r.get("ref", "")), str(r.get("ts", ""))[:10]
        ai, reason = _find_ai(logs, dates, day, ref)
        ev, ball = _find_candidate(logs, dates, day, ref)
        human = f"{r.get('kind', '-')}: {r.get('value', '-')}"
        rows.append("| " + " | ".join(_cell(x) for x in (day, ref, human, ai, reason, ev, ball)) + " |\n")
    return HEADER + "".join(rows)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True)
    ap.add_argument("--decisions", type=Path)
    ap.add_argument("--logs", type=Path, default=DEFAULT_LOGS)
    a = ap.parse_args(argv)
    todo = Path(os.environ.get("TODO_MD_PATH") or Path.home() / "memo" / "todo.md").expanduser()
    dec = a.decisions or todo.parent / decisions.DECISIONS_NAME
    sys.stdout.write(render(dec, a.logs, a.since))
    return 0


if __name__ == "__main__":
    sys.exit(main())
