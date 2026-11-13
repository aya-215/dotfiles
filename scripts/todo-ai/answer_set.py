#!/usr/bin/env python3
"""確認待ちの回答欄に回答を書き、人のコミット（`todo: `）にしてから answers.py で反映する。

対話で「1 は A」と言われたとき、Claude が nvim のポップアップと同じ結果を作るための口。
回答欄は番号でなくタグの (ref, kind) で探すので、確認待ちが書き換わった後でも別の問いに書かない。
1つでも書けない回答があれば何も書かない。選択肢の文字1つの回答は answers.py が反映し、文の回答は次の /todo に回る。

使い方: answer_set.py --answers '[{"ref": "...", "kind": "...", "answer": "A"}, ...]'
                      [--todo PATH] [--decisions PATH] [--log-dir DIR] [--today YYYY-MM-DD]
標準出力の最後の行: 「反映: <todo(ai) の件名>」か「反映なし（次の /todo に回る）」か「反映失敗: ...」。
終了コード: 0 書いた / 4 書いたが answers.py が失敗した / 2 回答の指定・確認待ちの問題、または無人実行で何も書いていない /
            3 todo.md を nvim で編集中で何も書いていない / 1 その他のエラー
"""
import argparse
import datetime
import fcntl
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import answers
import apply
import todo_md

ANSWERS = str(Path(__file__).resolve().parent / "answers.py")


class SpecError(Exception):
    pass


def parse_spec(raw: str) -> "list[dict]":
    try:
        spec = json.loads(raw)
    except ValueError as e:
        raise SpecError(f"--answers が JSON でない: {e}")
    if not isinstance(spec, list) or not spec:
        raise SpecError("--answers は1件以上の配列で渡す")
    for s in spec:
        if not (isinstance(s, dict) and all(isinstance(s.get(k), str) for k in ("ref", "kind", "answer"))):
            raise SpecError(f"ref・kind・answer の文字列が要る: {s!r}")
        if not s["answer"].strip() or "\n" in s["answer"] or "\r" in s["answer"]:
            raise SpecError(f"回答が空か改行を含む: {s['ref']}")
    return spec


def fill(text: str, spec: "list[dict]") -> str:
    """回答欄を埋めた todo.md の本文。書けない回答があれば SpecError。"""
    doc = todo_md.parse(text)
    try:
        blocks = apply.parse_confirm(doc.confirm)
    except apply.ChangeError as e:
        raise SpecError(str(e))
    lines = text.split("\n")
    for s in spec:
        hits = [b for b in blocks if apply.parse_tag(b["question"]) == (s["kind"], s["ref"])]
        if len(hits) != 1:
            raise SpecError(f"確認待ちに [{s['kind']} {s['ref']}] の問いが{'無い' if not hits else '複数ある'}")
        b = hits[0]
        now = b["回答"].strip()
        if now and now != s["answer"].strip():
            raise SpecError(f"回答済みで違う回答が入っている: [{s['kind']} {s['ref']}] 回答:{now}")
        # 問いの行はタグを含むので確認待ちの中で一意。回答はブロックの最後の行
        start = [i for i, l in enumerate(lines) if l == b["lines"][0]]
        if len(start) != 1:
            raise SpecError(f"問いの行を1つに決められない: [{s['kind']} {s['ref']}]")
        i = start[0] + len(b["lines"]) - 1
        m = apply._CONFIRM_FIELD.match(lines[i])
        if not (m and m.group(1) == "回答"):
            raise SpecError(f"回答の行が見つからない: [{s['kind']} {s['ref']}]")
        lines[i] = lines[i][:m.start(2)].rstrip(" ") + s["answer"].strip()
    return "\n".join(lines)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="確認待ちの回答欄を書いて反映する")
    p.add_argument("--answers", required=True)
    p.add_argument("--todo", type=Path)
    p.add_argument("--decisions", type=Path)
    p.add_argument("--log-dir", type=Path, default=answers.LOG_DIR)
    p.add_argument("--today", default=datetime.date.today().isoformat())
    a = p.parse_args(argv)
    todo = (a.todo or Path(os.environ.get("TODO_MD_PATH") or Path.home() / "memo" / "todo.md")).expanduser().absolute()
    repo, name = todo.parent, todo.name
    # 回答は人の印（todo: のコミット）になり、by_answer で人の行も動かせるので、apply.py の source user と同じく無人では受け付けない
    if os.environ.get("TODO_AI_DENY_USER", "") not in ("", "0"):
        print("answer_set: 未適用: TODO_AI_DENY_USER が立っているので回答を書かない", file=sys.stderr)
        return 2
    try:
        spec = parse_spec(a.answers)
    except SpecError as e:
        print(f"answer_set: 未適用: {e}", file=sys.stderr)
        return 2
    if not todo.is_file():
        print(f"answer_set: todo.md が無い: {todo}", file=sys.stderr)
        return 1
    with open(repo / ".todo.write.lock", "w") as wl:
        fcntl.flock(wl, fcntl.LOCK_EX)
        if apply.nvim_editing(repo):
            print("answer_set: todo.md を編集中のため未適用", file=sys.stderr)
            return 3
        apply._commit_human_edits(repo, name)
        text = todo.read_text(encoding="utf-8")
        try:
            new_text = fill(text, spec)
        except SpecError as e:
            print(f"answer_set: 未適用: {e}", file=sys.stderr)
            return 2
        if new_text != text:
            try:
                apply._write_atomic(todo, new_text, expect=text)
            except apply._Changed:
                print("answer_set: 読んだ後に todo.md が変わったため未適用", file=sys.stderr)
                return 3
            stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
            apply._git(repo, "add", "--", name, retry=True)
            apply._git(repo, "commit", "-q", "-m", f"todo: {stamp}", "--", name, retry=True)
    # apply.py が同じ書き込みロックを取るので、手放してから反映する
    cmd = [sys.executable, "-I", ANSWERS, "--todo", str(todo), "--log-dir", str(a.log_dir), "--today", a.today]
    if a.decisions:
        cmd += ["--decisions", str(a.decisions)]
    head = apply._git(repo, "rev-parse", "HEAD").strip()
    r = subprocess.run(cmd)
    print(f"answer_set: {len(spec)} 件書いた")
    if r.returncode != 0:
        print(f"反映失敗: answers.py exit={r.returncode}（ログ: {a.log_dir}/<日付>/answers-*.err）")
        return 4
    if apply._git(repo, "rev-parse", "HEAD").strip() == head:
        print("反映なし（次の /todo に回る）")
    else:
        print("反映: " + apply._git(repo, "log", "-1", "--format=%s").strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
