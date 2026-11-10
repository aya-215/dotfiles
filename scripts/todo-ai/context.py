#!/usr/bin/env python3
"""/todo が変更案を作るための材料を、todo.md・git 履歴・判断記録から決定的に組み立てて JSON で出す。

使い方: context.py [--todo PATH] [--decisions PATH] [--today YYYY-MM-DD]
終了コード: 0 出力した / 1 todo.md を読めない・解釈できない

出力:
  items           やる・待ち・完了の各行（ref, section, title, key, url, next, done, done_date,
                  origin, added_date, age_days, pinned）
  confirm_blocks  確認待ちの各ブロック（number, ref, kind, question, facts, options, answer）。
                  ref/kind は question 末尾のタグ `[<kind> <ref>]` から読む。無ければ null
  confirm_errors  確認待ちを全置換できない理由（空でなければ /todo は confirm を出さない）
  answered_now    回答欄が埋まったブロックを、apply.py の answered にそのまま渡せる形にしたもの
  answered_refs   判断記録にある確認待ちへの回答（ref, kind, value, ts）
  rejected_refs   人が消した AI の追加（reject_add）の ref
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply
import decisions
import todo_md
from origin import origin_of

KINDS = ("policy", "before_share", "manual", "conflict", "is_task", "still_needed")
_TAG = re.compile(r" \[(" + "|".join(KINDS) + r") (.+)\]\Z")
_OPTION = re.compile(r"(\S+) (.*?)(（おすすめ）)?\Z")


def with_tag(question: str, kind: str, ref: str) -> str:
    return f"{question} [{kind} {ref}]"


def parse_tag(question: str) -> "tuple[str | None, str | None]":
    m = _TAG.search(question)
    return (m.group(1), m.group(2)) if m else (None, None)


def _parse_options(s: str) -> "list[dict]":
    out = []
    for part in s.split(" / ") if s else []:
        m = _OPTION.match(part)
        # 空白の無い断片は選択肢の文中の " / " で割れたものなので、前の選択肢に戻す
        if out and (not m or not m.group(2)):
            prev = out[-1]
            prev["text"] += " / " + part
            if prev["text"].endswith("（おすすめ）"):
                prev["text"], prev["recommended"] = prev["text"][: -len("（おすすめ）")], True
        elif m:
            out.append({"label": m.group(1), "text": m.group(2), "recommended": bool(m.group(3))})
        else:
            out.append({"label": part, "text": part, "recommended": False})
    return out


def confirm_blocks(lines: "list[str]") -> "list[dict]":
    """確認待ちの行を apply.py と同じ厳密さで読む。崩れていれば apply.ChangeError。"""
    out = []
    for n, b in enumerate(apply.parse_confirm(lines), 1):
        kind, ref = parse_tag(b["question"])
        out.append({"number": n, "ref": ref, "kind": kind, "question": b["question"],
                    "facts": b["事実"], "options": _parse_options(b["選択"]), "answer": b["回答"].strip()})
    return out


def added_date(repo: Path, name: str, needle: str) -> "str | None":
    if not needle:
        return None
    r = subprocess.run(["git", "-C", str(repo), "log", "-S" + needle, "--reverse", "--format=%as", "--", name],
                       capture_output=True, text=True, encoding="utf-8")
    lines = r.stdout.split() if r.returncode == 0 else []
    return lines[0] if lines else None


def _last_written_confirm(repo: Path, name: str) -> "list[str]":
    try:
        return apply._last_written_confirm(repo, name)
    except RuntimeError:
        return []


def build(todo: Path, decisions_path: Path, today: str) -> dict:
    todo = Path(todo)
    repo, name = todo.parent, todo.name
    doc = todo_md.parse(todo.read_text(encoding="utf-8"))
    records = decisions.load(decisions_path)
    t = datetime.date.fromisoformat(today)

    items = []
    for section in todo_md.TASK_SECTIONS:
        for it in doc.sections[section]:
            added = added_date(repo, name, it.title or it.key or "")
            items.append({
                "ref": it.ref, "section": section, "title": it.title, "key": it.key, "url": it.url,
                "next": it.next, "done": it.done, "done_date": it.done_date,
                "origin": origin_of(repo, name, it.title),
                "added_date": added,
                "age_days": (t - datetime.date.fromisoformat(added)).days if added else None,
                "pinned": decisions.is_pinned(records, it.ref),
            })

    errors: "list[str]" = []
    try:
        blocks = confirm_blocks(doc.confirm)
    except apply.ChangeError as e:
        blocks = []
        errors.append(str(e))
    else:
        errors += apply.confirm_edit_errors(doc.confirm, _last_written_confirm(repo, name))
    answered_now = []
    for b in blocks:
        if not b["answer"]:
            continue
        if b["ref"] is None:
            errors.append(f"回答のあるブロックに ref/kind のタグが無い（記録できない）: {b['number']}. {b['question']}")
            continue
        answered_now.append({"ref": b["ref"], "kind": b["kind"], "answer": b["answer"]})

    return {
        "today": today,
        "todo": str(todo),
        "items": items,
        "confirm_blocks": blocks,
        "confirm_errors": errors,
        "answered_now": answered_now,
        "answered_refs": [{"ref": r.get("ref"), "kind": r.get("kind"), "value": r.get("value"), "ts": r.get("ts")}
                          for r in records if r.get("kind") in KINDS],
        "rejected_refs": sorted({r["ref"] for r in records if r.get("kind") == "reject_add" and r.get("ref")}),
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="/todo の変更案づくりの材料を JSON で出す")
    p.add_argument("--todo", type=Path)
    p.add_argument("--decisions", type=Path)
    p.add_argument("--today", default=datetime.date.today().isoformat())
    a = p.parse_args(argv)
    todo = (a.todo or Path(os.environ.get("TODO_MD_PATH") or Path.home() / "memo" / "todo.md")).expanduser().absolute()
    dpath = (a.decisions or todo.parent / decisions.DECISIONS_NAME).expanduser().absolute()
    try:
        out = build(todo, dpath, a.today)
    except (OSError, ValueError) as e:
        print(f"context: {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
