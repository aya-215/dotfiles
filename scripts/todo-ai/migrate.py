#!/usr/bin/env python3
"""旧形式の todo.md（`## やる` 無し）を新形式へ一度だけ変換する。

使い方: migrate.py <path> [--date YYYY-MM-DD]  （その場で書き換える。成功時は何も出力しない）
日付の無い完了行には ` (done: <--date、既定は今日>)` を付ける。30日後にアーカイブされる。
終了コード: 0 変換した / 1 旧形式として解釈できない / 2 引数が違う
"""
import datetime
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import todo_md


def _stamp(doc: todo_md.Doc, today: str) -> str:
    for s in todo_md.TASK_SECTIONS:
        for it in doc.sections[s]:
            if it.done and not it.done_date:
                it.done_date = today
    return todo_md.render(doc)


def migrate(text: str, today: "str | None" = None) -> str:
    today = today or datetime.date.today().isoformat()
    lines = todo_md.split_lines(text)
    if any(l.startswith("## ") and l[3:].strip() == "確認待ち" for l in lines):
        return _stamp(todo_md.parse(text), today)
    doc = todo_md.Doc()
    current = "やる"
    buckets = {"やる": [], "待ち": [], "完了": []}
    seen_task = False
    for n, line in enumerate(lines, 1):
        if line.startswith("## "):
            name = line[3:].strip()
            if name not in ("待ち", "完了") or current == "完了" or (
                name == "待ち" and current != "やる"
            ):
                raise todo_md.ParseError(f"line {n}: 旧形式として解釈できない見出し: {line!r}")
            current = name
        elif line.strip() == "":
            continue
        elif line.startswith("- ["):
            seen_task = True
            buckets[current].append(line)
        elif current == "やる" and not seen_task:
            doc.preamble.append(line)
        else:
            raise todo_md.ParseError(f"line {n}: タスク行ではない: {line!r}")
    out = "\n".join(
        doc.preamble + ([""] if doc.preamble else []) + ["## 確認待ち", "", "## やる"]
        + buckets["やる"] + ["", "## 待ち"] + buckets["待ち"] + ["", "## 完了"] + buckets["完了"]
    ) + "\n"
    return _stamp(todo_md.parse(out), today)


def main(argv):
    args = argv[1:]
    today = None
    if len(args) == 3 and args[1] == "--date":
        today = args[2]
        args = args[:1]
    if len(args) != 1:
        print("usage: migrate.py <path> [--date YYYY-MM-DD]", file=sys.stderr)
        return 2
    try:
        if today is not None:
            datetime.date.fromisoformat(today)
    except ValueError:
        print(f"migrate: --date が日付でない: {today!r}", file=sys.stderr)
        return 2
    p = Path(args[0])
    try:
        new = migrate(p.read_text(encoding="utf-8"), today)
    except todo_md.ParseError as e:
        print(f"migrate: {e}", file=sys.stderr)
        return 1
    p.write_text(new, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
