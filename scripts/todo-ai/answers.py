#!/usr/bin/env python3
"""確認待ちの回答のうち、選択肢の文字1つだけのものを、/todo が保存した変更案（todo-pending.json）で反映する。AI は使わない。

nvim のポップアップを閉じたときに裏で起動される。対象は、回答が選択肢の文字1つ（前後の空白・全角・小文字可）で、
その文字がブロックの選択肢にあり、todo-pending.json にそのブロック（問い・選択肢の行が書いたときと同じもの）の
その文字の ops があるブロックだけ。文の回答・pending の無いブロック・選択肢に無い文字は回答欄ごと残し、次の /todo に回す。
反映しない conflict の問いが残るとき（回答が古くなったかの基準が動く）は、何もせず全部を次の /todo に回す。
対象の ops に by_answer を付けた source ai の変更案を作り、apply.py に渡す。

使い方: answers.py [--todo PATH] [--decisions PATH] [--log-dir DIR] [--today YYYY-MM-DD]
終了コード: 0 反映した・対象が無い / 1 todo.md を読めない等のエラー / それ以外は apply.py の終了コード
ログ: <log-dir>/<日付>/answers-<HHMMSS>.{json,out,err}（対象があったか、エラーのときだけ）
"""
import argparse
import datetime
import json
import os
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply
import decisions
import todo_md

APPLY = str(Path(__file__).resolve().parent / "apply.py")
LOG_DIR = Path.home() / ".local" / "log" / "todo-ai"


def _entry(b: dict, pending: "list[dict]") -> dict:
    kind, ref = apply.parse_tag(b["question"])
    on = apply.pending_for(b, pending)
    return {"ref": ref, "kind": kind, "question": apply.strip_tag(b["question"]), "facts": b["事実"],
            "options": apply.parse_options(b["選択"]), **({"on_answer": on} if on is not None else {})}


def plan(todo: Path, dpath: Path) -> "tuple[dict | None, str]":
    """反映する変更案と、無ければその理由。"""
    repo, name = todo.parent, todo.name
    doc = todo_md.parse(todo.read_text(encoding="utf-8"))
    try:
        blocks = apply.parse_confirm(doc.confirm)
    except apply.ChangeError as e:
        return None, str(e)
    tags = [tuple(reversed(apply.parse_tag(b["question"]))) for b in blocks]
    if any(ref is None for ref, _ in tags):
        return None, "タグの無いブロックがある"
    if any(n > 1 for n in Counter(tags).values()):
        return None, "同じタグのブロックが複数ある"
    if not any(b["回答"].strip() for b in blocks):
        return None, "回答が無い"
    pending = apply.load_pending(repo)
    if not pending:
        return None, "todo-pending.json が無い"
    errs = apply.confirm_edit_errors(doc.confirm, apply._last_written_confirm(repo, name))
    if errs:
        return None, errs[0]
    records = decisions.load(dpath)
    asked_at = None
    targets = []
    for b, (ref, kind) in zip(blocks, tags):
        ans = b["回答"].strip()
        label = apply.answer_label(ans, apply.parse_options(b["選択"])) if ans else None
        on = apply.pending_for(b, pending) if label else None
        if on is None or label not in on:
            continue
        if kind == "conflict":
            if asked_at is None:
                asked_at = apply.confirm_asked_at(repo, name, dpath)
            if apply.stale_answer(records, ref, kind, asked_at):
                continue
        targets.append((b, on[label]))
    if not targets:
        return None, "選択肢の文字1つで変更案のある回答が無い"
    chosen = [b for b, _ in targets]
    # 書き直した確認待ちが conflict の回答の古さの基準になるので、問いの後に記録された意図を見落とさないよう持ち越さない
    if any(kind == "conflict" and all(b is not c for c in chosen) for b, (_, kind) in zip(blocks, tags)):
        return None, "持ち越す conflict の問いがある"
    ops = [dict(op, by_answer={"ref": ref, "kind": kind})
           for b, todo_ops in targets for op in todo_ops
           for kind, ref in [apply.parse_tag(b["question"])]]
    changes = {
        "source": "ai",
        "ops": ops,
        "confirm": [_entry(b, pending) for b in blocks if not b["回答"].strip()],
        "keep_answered": [{"ref": ref, "kind": kind} for b, (ref, kind) in zip(blocks, tags)
                          if b["回答"].strip() and all(b is not c for c in chosen)],
        "answered": [{"ref": ref, "kind": kind, "answer": b["回答"].strip()}
                     for b, (ref, kind) in zip(blocks, tags) if b["回答"].strip()],
    }
    return changes, f"{len(targets)} 件"


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="選択肢の文字1つの回答を、保存済みの変更案で反映する")
    p.add_argument("--todo", type=Path)
    p.add_argument("--decisions", type=Path)
    p.add_argument("--log-dir", type=Path, default=LOG_DIR)
    p.add_argument("--today", default=datetime.date.today().isoformat())
    a = p.parse_args(argv)
    todo = (a.todo or Path(os.environ.get("TODO_MD_PATH") or Path.home() / "memo" / "todo.md")).expanduser().absolute()
    dpath = (a.decisions or todo.parent / decisions.DECISIONS_NAME).expanduser().absolute()
    now = datetime.datetime.now()
    logs = a.log_dir.expanduser() / now.strftime("%Y-%m-%d")
    stem = f"answers-{now.strftime('%H%M%S')}"
    try:
        changes, _ = plan(todo, dpath)
    except (OSError, ValueError, RuntimeError) as e:
        logs.mkdir(parents=True, exist_ok=True)
        (logs / f"{stem}.err").write_text(f"answers: {type(e).__name__}: {e}\n", encoding="utf-8")
        return 1
    if changes is None:
        return 0
    logs.mkdir(parents=True, exist_ok=True)
    cf = logs / f"{stem}.json"
    cf.write_text(json.dumps(changes, ensure_ascii=False, indent=1), encoding="utf-8")
    with open(logs / f"{stem}.out", "w", encoding="utf-8") as out, open(logs / f"{stem}.err", "w", encoding="utf-8") as err:
        r = subprocess.run([sys.executable, "-I", APPLY, "--changes", str(cf), "--todo", str(todo),
                            "--decisions", str(dpath), "--today", a.today], stdout=out, stderr=err)
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
