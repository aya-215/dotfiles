#!/usr/bin/env python3
"""旧形式の todo.md（`## やる` 無し）を新形式へ一度だけ変換する。

使い方: migrate.py <path>  （その場で書き換える。成功時は何も出力しない）
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import todo_md


def migrate(text: str) -> str:
    lines = text.splitlines()
    if any(l.startswith("## ") and l[3:].strip() == "確認待ち" for l in lines):
        return todo_md.render(todo_md.parse(text))
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
    return todo_md.render(todo_md.parse(out))


def main(argv):
    if len(argv) != 2:
        print("usage: migrate.py <path>", file=sys.stderr)
        return 2
    p = Path(argv[1])
    try:
        new = migrate(p.read_text(encoding="utf-8"))
    except todo_md.ParseError as e:
        print(f"migrate: {e}", file=sys.stderr)
        return 1
    p.write_text(new, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
