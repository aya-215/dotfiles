#!/usr/bin/env python3
"""todo.md の唯一の書き込み口。変更案 JSON を検証して適用し、git にコミットする。

使い方: apply.py --changes <json> [--todo PATH] [--decisions PATH] [--today YYYY-MM-DD]
終了コード: 0 適用（変更なし含む） / 3 nvim で編集中のためスキップ / 2 検証違反で未適用 / 1 その他
"""
import argparse
import copy
import datetime
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import todo_md
from origin import origin_of
from todo_md import TASK_SECTIONS, Doc, Item

SOURCES = ("ai", "sync")
OPEN_SECTIONS = ("やる", "待ち")
ARCHIVE_DAYS = 30
OP_LABELS = {
    "add": "追加", "move": "移動", "set_next": "next更新", "attach": "紐付け",
    "order": "並べ替え", "confirm": "確認待ち", "archive": "アーカイブ",
}
_CONFIRM_Q = re.compile(r"\d+\. ")
_CONFIRM_FIELD = re.compile(r"(事実|選択|回答)[:：]\s*(.*)\Z")


class ChangeError(ValueError):
    """変更案そのものが不正、または適用すると人の記述を失う。"""


def _str(op: dict, name: str, required: bool = True) -> "str | None":
    v = op.get(name)
    if v is None and not required:
        return None
    if not isinstance(v, str) or (required and not v):
        raise ChangeError(f"{op.get('op')}: {name} が文字列でない: {v!r}")
    if "\n" in v or "\r" in v:
        raise ChangeError(f"{op.get('op')}: {name} に改行は入れられない: {v!r}")
    return v


def _key(op: dict) -> str:
    key = _str(op, "key")
    if not todo_md.is_key(key):
        raise ChangeError(f"{op['op']}: key の形式が違う: {key!r}")
    _str(op, "url")
    return key


def _find(doc: Doc, ref: str) -> "list[tuple[str, int]]":
    return [(s, i) for s in TASK_SECTIONS for i, it in enumerate(doc.sections[s]) if it.ref == ref]


def _note(op: dict, head: str, url: "str | None") -> str:
    s = head
    if op.get("reason"):
        s += f": {op['reason']}"
    if url:
        s += f" {url}"
    return s


def _check_old_confirm(lines: "list[str]", answered: list) -> None:
    n_answers = 0
    for line in lines:
        st = line.strip()
        if not st or _CONFIRM_Q.match(st):
            continue
        m = _CONFIRM_FIELD.match(st)
        if not m:
            raise ChangeError(f"確認待ちに解釈できない行がある（全置換すると消える）: {line!r}")
        if m.group(1) == "回答" and m.group(2).strip():
            n_answers += 1
    if len(answered) < n_answers:
        raise ChangeError(
            f"確認待ちの回答 {n_answers} 件に対し answered が {len(answered)} 件（回答が消える）"
        )


def _render_confirm(entries: list) -> "list[str]":
    out = []
    for n, e in enumerate(entries, 1):
        if not isinstance(e, dict):
            raise ChangeError(f"confirm の要素が object でない: {e!r}")
        q = _str(e, "question")
        facts = _str(e, "facts", required=False) or ""
        opts = []
        for o in e.get("options") or []:
            label = _str(o, "label")
            text = _str(o, "text")
            opts.append(f"{label} {text}" + ("（おすすめ）" if o.get("recommended") else ""))
        out += [f"{n}. {q}", f"   事実: {facts}", f"   選択: {' / '.join(opts)}", "   回答:"]
    return out


def apply_changes(
    doc: Doc, changes: dict, origins: Callable[[str], str], today: str
) -> "tuple[Doc, list[str]]":
    """変更案を適用した新しい Doc とコミット本文の行を返す（doc は変更しない）。

    存在しない・複数に当たる ref への op はその op だけ飛ばし `skip: ...` を本文に残す。
    変更案の形が不正なら ChangeError。人のタイトル保護などの結果の検証は validate が行う。
    origins は現状の op では使わない（タイトルを書き換える op が無いため）。
    """
    if not isinstance(changes, dict):
        raise ChangeError("変更案が object でない")
    source = changes.get("source")
    if source not in SOURCES:
        raise ChangeError(f"source が不正: {source!r}")
    ops = changes.get("ops", [])
    if not isinstance(ops, list):
        raise ChangeError("ops が配列でない")
    doc = copy.deepcopy(doc)
    body: "list[str]" = []

    def locate(ref: str) -> "tuple[str, int] | None":
        hits = _find(doc, ref)
        if len(hits) == 1:
            return hits[0]
        body.append(f"skip: {'unknown' if not hits else 'ambiguous'} ref {ref}")
        return None

    for op in ops:
        if not isinstance(op, dict):
            raise ChangeError(f"op が object でない: {op!r}")
        kind = op.get("op")
        if kind == "add":
            section = op.get("section")
            if section not in OPEN_SECTIONS:
                raise ChangeError(f"add: section が不正: {section!r}")
            title = _str(op, "title")
            key = _key(op) if op.get("key") is not None else None
            nxt = _str(op, "next", required=False)
            it = Item(title, key, op.get("url") if key else None, nxt or None)
            if _find(doc, it.ref):
                body.append(f"skip: duplicate {it.ref}")
                continue
            doc.sections[section].append(it)
            body.append(_note(op, f"add {it.ref} → {section}", it.url))
        elif kind == "move":
            ref, to = _str(op, "ref"), op.get("to")
            if to not in TASK_SECTIONS:
                raise ChangeError(f"move: to が不正: {to!r}")
            loc = locate(ref)
            if loc is None or loc[0] == to:
                continue
            it = doc.sections[loc[0]].pop(loc[1])
            if to == "完了":
                it.done, it.done_date = True, today
                doc.sections[to].insert(0, it)
            else:
                if loc[0] == "完了":
                    it.done, it.done_date = False, None
                doc.sections[to].append(it)
            body.append(_note(op, f"move {ref} → {to}", op.get("url") or it.url))
        elif kind == "set_next":
            ref = _str(op, "ref")
            nxt = _str(op, "next", required=False)
            loc = locate(ref)
            if loc is None:
                continue
            it = doc.sections[loc[0]][loc[1]]
            it.next = nxt or None
            body.append(_note(op, f"set_next {ref}", op.get("url") or it.url))
        elif kind == "attach":
            ref = _str(op, "ref")
            key = _key(op)
            nxt = _str(op, "next", required=False)
            loc = locate(ref)
            if loc is None:
                continue
            it = doc.sections[loc[0]][loc[1]]
            if it.key:
                body.append(f"skip: already linked {ref}")
                continue
            if _find(doc, key):
                body.append(f"skip: duplicate {key}")
                continue
            if nxt and it.next:
                body.append(f"skip: next already set {ref}")
                continue
            it.key, it.url = key, op["url"]
            if nxt:
                it.next = nxt
            body.append(_note(op, f"attach {ref} ← {key}", it.url))
        elif kind == "order":
            section, refs = op.get("section"), op.get("refs")
            if section not in TASK_SECTIONS or not isinstance(refs, list):
                raise ChangeError(f"order: section/refs が不正: {op!r}")
            items = doc.sections[section]
            first: "list[Item]" = []
            for ref in refs:
                hits = [i for i, it in enumerate(items) if it.ref == ref]
                if len(hits) != 1:
                    body.append(f"skip: {'unknown' if not hits else 'ambiguous'} ref {ref}")
                elif items[hits[0]] not in first:
                    first.append(items[hits[0]])
            rest = [it for it in items if all(it is not f for f in first)]
            new = first + rest
            if any(a is not b for a, b in zip(new, items)):
                doc.sections[section] = new
                body.append(_note(op, f"order {section}", None))
        else:
            raise ChangeError(f"未知の op: {kind!r}")

    if "confirm" in changes:
        entries = changes["confirm"]
        answered = changes.get("answered", [])
        if not isinstance(entries, list) or not isinstance(answered, list):
            raise ChangeError("confirm/answered が配列でない")
        _check_old_confirm(doc.confirm, answered)
        new_confirm = _render_confirm(entries)
        if new_confirm != doc.confirm:
            doc.confirm = new_confirm
            body.append(f"confirm: {len(entries)} 件")
    return doc, body


def _ident(it: Item) -> str:
    return it.title or it.key or ""


def _items(doc: Doc, sections=TASK_SECTIONS) -> "list[Item]":
    return [it for s in sections for it in doc.sections[s] if _ident(it)]


def validate(before: Doc, after: Doc, origins: Callable[[str], str], source: str) -> "list[str]":
    """適用前後を比べ、人の行・判断を壊す変更なら違反メッセージを返す（空なら OK）。"""
    errs = []
    nb, na = len(_items(before)), len(_items(after))
    if na < nb:
        errs.append(f"タスク行が減る: {nb} → {na}")
    keys_b = Counter(it.key for it in _items(before) if it.key)
    keys_a = Counter(it.key for it in _items(after) if it.key)
    for k in keys_b - keys_a:
        errs.append(f"リンク付きの行が消える: {k}")
    titles_a = Counter(it.title for it in _items(after))
    for t, n in Counter(it.title for it in _items(before) if it.title).items():
        if titles_a[t] < n and origins(t) == "human":
            errs.append(f"人が書いたタイトルが変わる: {t!r}")
    if source in SOURCES:
        done_a = Counter(_ident(it) for it in _items(after, ["完了"]))
        for ident, n in Counter(_ident(it) for it in _items(before, ["完了"])).items():
            if done_a[ident] < n:
                errs.append(f"{source} は完了から戻せない: {ident!r}")
    return errs


def roundtrip_errors(doc: Doc) -> "list[str]":
    """render した結果を parse し直して同じ Doc に戻らなければ、書くと意味が変わる。"""
    try:
        back = todo_md.parse(todo_md.render(doc))
    except ValueError as e:
        return [f"書き出せない: {e}"]
    errs = []
    if back.preamble != doc.preamble or back.confirm != doc.confirm:
        errs.append("確認待ち・前置きが書き出し後に変わる")
    fields = lambda it: (it.title, it.key, it.url, it.next, it.done, it.done_date)
    for s in TASK_SECTIONS:
        if [fields(i) for i in back.sections[s]] != [fields(i) for i in doc.sections[s]]:
            errs.append(f"{s} の行が書き出し後に別の意味になる（タイトルに — next: や ]( 等）")
    return errs


def split_archive(doc: Doc, today: str) -> "tuple[Doc, dict[str, list[Item]]]":
    """完了日から 30 日を超えた完了行を、完了月ごとに取り出す。日付が無い・読めない行は残す。"""
    t = datetime.date.fromisoformat(today)
    doc = copy.deepcopy(doc)
    archived: "dict[str, list[Item]]" = {}
    kept = []
    for it in doc.sections["完了"]:
        try:
            d = datetime.date.fromisoformat(it.done_date) if it.done_date else None
        except ValueError:
            d = None
        if it.done and d and (t - d).days > ARCHIVE_DAYS:
            archived.setdefault(d.strftime("%Y-%m"), []).append(it)
        else:
            kept.append(it)
    doc.sections["完了"] = kept
    return doc, archived


def nvim_editing(todo_dir: Path) -> bool:
    """`.todo.lock` の PID が生きていれば True。死んだ PID・読めない中身は古いロックとして消す。"""
    lock = todo_dir / ".todo.lock"
    try:
        content = lock.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return False
    try:
        pid = int(content)
        if pid > 0:
            os.kill(pid, 0)
            return True
    except PermissionError:
        return True
    except (ValueError, ProcessLookupError):
        pass
    try:
        lock.unlink()
    except FileNotFoundError:
        pass
    return False


def _git(repo: Path, *args: str) -> str:
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout


def _commit_human_edits(repo: Path, name: str) -> None:
    # nvim は保存ごとに書きコミットは閉じるときだけなので、未コミット分を AI のコミットに混ぜると出どころが ai になる
    if not _git(repo, "status", "--porcelain", "--", name).strip():
        return
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    _git(repo, "add", "--", name)
    _git(repo, "commit", "-q", "-m", f"todo: {stamp}", "--", name)


def _write_atomic(path: Path, text: str) -> None:
    tmp = path.with_name(f".{path.name}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    if path.exists():
        shutil.copymode(path, tmp)
    os.replace(tmp, path)


def summarize(body: "list[str]") -> str:
    counts = Counter(l.split(" ", 1)[0].rstrip(":") for l in body)
    parts = [f"{label}{counts[k]}" for k, label in OP_LABELS.items() if counts[k]]
    return " ".join(parts) or "整形"


def run(changes_path: Path, todo: Path, today: str) -> int:
    try:
        changes = json.loads(changes_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"apply: 変更案を読めない: {e}", file=sys.stderr)
        return 2
    source = changes.get("source") if isinstance(changes, dict) else None
    repo, name = todo.parent, todo.name
    _git(repo, "rev-parse", "--is-inside-work-tree")

    with open(repo / ".todo.write.lock", "w") as wl:
        fcntl.flock(wl, fcntl.LOCK_EX)
        if nvim_editing(repo):
            print("apply: todo.md を編集中のためスキップ", file=sys.stderr)
            return 3
        _commit_human_edits(repo, name)
        text = todo.read_text(encoding="utf-8")
        try:
            before = todo_md.parse(text)
            after, body = apply_changes(before, changes, lambda t: origin_of(repo, name, t), today)
        except ValueError as e:
            print(f"apply: 未適用: {e}", file=sys.stderr)
            return 2
        errs = validate(before, after, lambda t: origin_of(repo, name, t), source) + roundtrip_errors(after)
        if errs:
            print("apply: 検証違反のため未適用:\n" + "\n".join(errs), file=sys.stderr)
            return 2
        kept, archived = split_archive(after, today)
        new_text = todo_md.render(kept)
        if new_text == text and not archived:
            return 0
        if nvim_editing(repo):
            print("apply: todo.md を編集中のためスキップ", file=sys.stderr)
            return 3

        archive_dir = repo / "todo-archive"
        for month, items in sorted(archived.items()):
            archive_dir.mkdir(exist_ok=True)
            with open(archive_dir / f"{month}.md", "a", encoding="utf-8") as f:
                f.write("".join(todo_md._render_item(it) + "\n" for it in items))
            body += [f"archive {it.ref} → todo-archive/{month}.md" for it in items]
        _write_atomic(todo, new_text)

        paths = [name] + [p for p in ("todo-archive", "todo-decisions.jsonl") if (repo / p).exists()]
        _git(repo, "add", "--", *paths)
        _git(repo, "commit", "-q", "-m", f"todo({source}): {summarize(body)}", "-m", "\n".join(body), "--", *paths)
    return 0


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"apply: {message}", file=sys.stderr)
        sys.exit(1)


def main(argv=None) -> int:
    p = _Parser(description="変更案 JSON を todo.md に適用する")
    p.add_argument("--changes", required=True, type=Path)
    p.add_argument("--todo", type=Path)
    p.add_argument("--decisions", type=Path, help="判断記録（未使用。Task 5 で使う）")
    p.add_argument("--today", default=datetime.date.today().isoformat())
    a = p.parse_args(argv)
    todo = a.todo or Path(os.environ.get("TODO_MD_PATH") or Path.home() / "memo" / "todo.md")
    try:
        datetime.date.fromisoformat(a.today)
        return run(a.changes, todo.expanduser().absolute(), a.today)
    except Exception as e:
        print(f"apply: {type(e).__name__}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
