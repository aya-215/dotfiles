#!/usr/bin/env python3
"""/todo が変更案を作るための材料を、todo.md・git 履歴・判断記録から決定的に組み立てて JSON で出す。

使い方: context.py [--todo PATH] [--decisions PATH] [--today YYYY-MM-DD]
終了コード: 0 出力した / 1 todo.md を読めない・解釈できない

出力:
  items           やる・待ち・完了の各行（ref, section, title, key, url, next, done, done_date,
                  origin, added_date, age_days, pinned_to, intents, answers）。pinned_to は人が戻したため
                  その行を移してはいけないセクション。pinned_to・intents・answers は行の系譜（key を付ける前・
                  改名する前の ref の記録）も含める
  confirm_blocks  確認待ちの各ブロック（number, ref, kind, question, facts, options, answer）。
                  ref/kind は apply.py が書いた問い末尾のタグから読み、question はタグを外したもの。
                  ref, kind, question, facts, options をそのまま confirm に写せば同じ行に戻る
  confirm_errors  確認待ちを全置換できない理由（空でなければ /todo は confirm を出さない）
  answered_now    回答欄が埋まったブロックの (ref, kind, answer, superseded)。apply.py も同じものを記録する
  answered_refs   判断記録にある確認待ちへの回答（ref, kind, value, ts, superseded）
  superseded      conflict の回答のうち、問いを書いた後・回答の後に同じ行の意図が記録されたもの（true）。
                  その回答には従わず、意図と一次データが食い違えばもう一度聞く。conflict 以外は常に false
  rejected_refs   人が消した AI の追加（reject_add）の ref
  archived_keys   todo-archive/*.md に移った完了行の key
  intents         （各 item）ユーザー指示の意図。新しい順で最大5件の {ts, value}。/todo-edit で消した後に人が
                  書き戻した行では、消した指示とそれより前の意図を出さない
  answers         （各 item）その行への確認待ちの回答。新しい順の {kind, value, ts, superseded}
  intent_refs     意図の記録がある全 ref（prev_ref 含む。todo.md から消えた行も）
  deleted_refs    ユーザー指示（delete・edit_title の旧 ref）で台帳から消えた ref。/todo は足し直さない
                  （apply.py も source ai の add/attach を skip する）。今の台帳にある ref（人が書き戻した行）は除く
  other_intents   items に無く、items の行の系譜にも deleted_refs にも無い ref の意図（まだ台帳に無い key への note 等）。
                  {ref, intents}。intents は items と同じ形
pinned_to と rejected_refs には、まだ記録していない戻しも git 履歴から足す（ここでは書かない）。
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

KINDS = apply.KINDS
MAX_INTENTS = 5


def _intent_refs(records: "list[dict]") -> "list[str]":
    """行が todo.md から消えていても残す（/todo が消した行を足し直さないため）。prev_ref も含む。"""
    refs = set()
    for r in records:
        if r.get("kind") == "intent":
            refs |= {x for x in (r.get("ref"), r.get("prev_ref")) if isinstance(x, str) and x}
    return sorted(refs)


def _intents(records: "list[dict]", ref: str, present: bool = False) -> "list[dict]":
    """present（台帳にある行）では、最新の delete より前の意図を出さない。消した後に人が書き戻した行の指示ではない。"""
    out = []
    for r in decisions.intents(records, ref):
        if present and r.get("op") == "delete":
            break
        out.append({"ts": r.get("ts"), "value": r.get("value")})
    return out[:MAX_INTENTS]


def _answers(records: "list[dict]", ref: str) -> "list[dict]":
    return [{"kind": r.get("kind"), "value": r.get("value"), "ts": r.get("ts"),
             "superseded": decisions.superseded(records, i)} for i, r in decisions.answers(records, ref, KINDS)]


_OPTION = re.compile(r"(\S+) (.*?)(（おすすめ）)?\Z")


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
        kind, ref = apply.parse_tag(b["question"])
        out.append({"number": n, "ref": ref, "kind": kind, "question": apply.strip_tag(b["question"]),
                    "facts": b["事実"], "options": _parse_options(b["選択"]), "answer": b["回答"].strip()})
    return out


def added_date(repo: Path, name: str, needle: str) -> "str | None":
    if not needle:
        return None
    r = subprocess.run(["git", "-C", str(repo), "log", "-S" + needle, "--reverse", "--format=%as", "--", name],
                       capture_output=True, text=True, encoding="utf-8")
    lines = r.stdout.split() if r.returncode == 0 else []
    return lines[0] if lines else None


def archived_keys(repo: Path) -> "list[str]":
    keys = set()
    for p in sorted((Path(repo) / "todo-archive").glob("*.md")):
        try:
            lines = todo_md.split_lines(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for n, line in enumerate(lines, 1):
            try:
                it = todo_md._parse_item(line, n)
            except todo_md.ParseError:
                continue
            if it.key:
                keys.add(it.key)
    return sorted(keys)


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
    records = records + decisions.detect_reverts(repo, name, records)
    t = datetime.date.fromisoformat(today)

    items = []
    for section in todo_md.TASK_SECTIONS:
        for it in doc.sections[section]:
            added = added_date(repo, name, it.key or it.title)
            items.append({
                "ref": it.ref, "section": section, "title": it.title, "key": it.key, "url": it.url,
                "next": it.next, "done": it.done, "done_date": it.done_date,
                "origin": origin_of(repo, name, it.title),
                "added_date": added,
                "age_days": (t - datetime.date.fromisoformat(added)).days if added else None,
                "pinned_to": decisions.pinned_sections(records, it.ref),
                "intents": _intents(records, it.ref, present=True),
                "answers": _answers(records, it.ref),
            })

    present = {i["ref"] for i in items}
    deleted = decisions.deleted_refs(records, present)
    covered = set().union(*(decisions.lineage_refs(records, ref) for ref in present))
    errors: "list[str]" = []
    try:
        blocks = confirm_blocks(doc.confirm)
    except apply.ChangeError as e:
        blocks = []
        errors.append(str(e))
    else:
        errors += apply.confirm_edit_errors(doc.confirm, _last_written_confirm(repo, name))
    answered_now = []
    asked_at = (apply.confirm_asked_at(repo, name, Path(decisions_path).absolute())
                if any(b["answer"] and b["kind"] == "conflict" for b in blocks) else None)
    for b in blocks:
        if b["ref"] is None:
            errors.append(f"確認待ちのブロックに [kind ref] のタグが無い（記録先が分からない）: {b['number']}. {b['question']}")
        elif b["answer"]:
            answered_now.append({"ref": b["ref"], "kind": b["kind"], "answer": b["answer"],
                                 "superseded": apply.stale_answer(records, b["ref"], b["kind"], asked_at)})

    return {
        "today": today,
        "todo": str(todo),
        "items": items,
        "confirm_blocks": blocks,
        "confirm_errors": errors,
        "answered_now": answered_now,
        "answered_refs": [{"ref": r.get("ref"), "kind": r.get("kind"), "value": r.get("value"), "ts": r.get("ts"),
                           "superseded": decisions.superseded(records, i)}
                          for i, r in enumerate(records) if r.get("kind") in KINDS],
        "rejected_refs": sorted({r["ref"] for r in records if r.get("kind") == "reject_add" and r.get("ref")}),
        "archived_keys": archived_keys(repo),
        "intent_refs": _intent_refs(records),
        "deleted_refs": deleted,
        "other_intents": [{"ref": ref, "intents": _intents(records, ref)} for ref in _intent_refs(records)
                          if ref not in deleted and ref not in covered],
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
