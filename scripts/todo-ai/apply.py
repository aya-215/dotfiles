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
import time
from collections import Counter
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import decisions
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
CONFIRM_FIELDS = ("事実", "選択", "回答")
_CONFIRM_Q = re.compile(r"(\d+)\. (.+)\Z")
_CONFIRM_FIELD = re.compile(r"\s+(事実|選択|回答)[:：] ?(.*)\Z")
GIT_RETRIES = 10


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


def parse_confirm(lines: "list[str]") -> "list[dict]":
    """確認待ちを「問い・事実・選択・回答」の4行ブロックの列として厳密に読む。崩れていれば ChangeError。

    各ブロックは {"question", "事実", "選択", "回答", "lines"}。ブロックの間の空行だけ許す。
    """
    blocks = []
    i = 0
    while i < len(lines):
        if not lines[i].strip():
            i += 1
            continue
        m = _CONFIRM_Q.match(lines[i])
        if not m:
            raise ChangeError(f"確認待ちに解釈できない行がある（全置換すると消える）: {lines[i]!r}")
        block = {"question": m.group(2), "lines": lines[i:i + 4]}
        for j, name in enumerate(CONFIRM_FIELDS, 1):
            f = _CONFIRM_FIELD.match(lines[i + j]) if i + j < len(lines) else None
            if not f or f.group(1) != name:
                raise ChangeError(f"確認待ちのブロックが崩れている（{name} の行が無い）: {lines[i]!r}")
            block[name] = f.group(2)
        blocks.append(block)
        i += 4
    return blocks


def _check_answers(blocks: "list[dict]", answered: list) -> None:
    pool = Counter()
    for a in answered:
        if not isinstance(a, dict) or not isinstance(a.get("answer"), str):
            raise ChangeError(f"answered の要素に answer の文字列が無い: {a!r}")
        if not all(isinstance(a.get(k), str) and a[k] for k in ("ref", "kind")):
            raise ChangeError(f"answered の要素の ref/kind が空でない文字列でない: {a!r}")
        pool[a["answer"].strip()] += 1
    for b in blocks:
        ans = b["回答"].strip()
        if not ans:
            continue
        if pool[ans] <= 0:
            raise ChangeError(f"確認待ちの回答が answered に無い（全置換すると消える）: {ans!r}")
        pool[ans] -= 1


def confirm_edit_errors(current: "list[str]", written: "list[str]") -> "list[str]":
    """確認待ちの問い・事実・選択が、apply が最後に書いた内容から変わっていれば違反を返す。

    written は最後の todo(ai)/todo(sync) コミット時点の確認待ち。人が足した文は全置換で消えるため止める。
    """
    try:
        cur = parse_confirm(current)
    except ChangeError as e:
        return [str(e)]
    try:
        prev = parse_confirm(written)
    except ChangeError:
        prev = []
    pool = Counter((b["question"], b["事実"], b["選択"]) for b in prev)
    errs = []
    for b in cur:
        k = (b["question"], b["事実"], b["選択"])
        if pool[k] <= 0:
            errs.append(f"確認待ちの問い・事実・選択が apply の書いた内容と違う（人の追記が消える）: {b['lines'][0]!r}")
        else:
            pool[k] -= 1
    return errs


def _render_confirm(entries: list) -> "list[str]":
    out = []
    for n, e in enumerate(entries, 1):
        if not isinstance(e, dict):
            raise ChangeError(f"confirm の要素が object でない: {e!r}")
        q = _str(e, "question")
        facts = _str(e, "facts", required=False) or ""
        opts = []
        options = e.get("options") or []
        if not isinstance(options, list) or not all(isinstance(o, dict) for o in options):
            raise ChangeError(f"confirm の options が object の配列でない: {options!r}")
        for o in options:
            label = _str(o, "label")
            text = _str(o, "text")
            opts.append(f"{label} {text}" + ("（おすすめ）" if o.get("recommended") else ""))
        out += [f"{n}. {q}", f"   事実: {facts}", f"   選択: {' / '.join(opts)}", "   回答:"]
    return out


def apply_changes(
    doc: Doc, changes: dict, origins: Callable[[str], str], today: str, pinned=frozenset()
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
            if source == "sync" and ref in pinned:
                body.append(f"skip: pinned {ref}")
                continue
            loc = locate(ref)
            if loc is None or loc[0] == to:
                continue
            if loc[0] == "完了":
                raise ChangeError(f"{source} は完了から戻せない: {ref}")
            it = doc.sections[loc[0]].pop(loc[1])
            if to == "完了":
                it.done, it.done_date = True, today
                doc.sections[to].insert(0, it)
            else:
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
        old_blocks = parse_confirm(doc.confirm)
        _check_answers(old_blocks, answered)
        new_confirm = _render_confirm(entries)
        if new_confirm != doc.confirm:
            doc.confirm = new_confirm
            body.append(f"confirm: {len(entries)} 件")
            # decisions に記録されるまでは、コミット本文が人の回答の唯一の控えになる
            for b in old_blocks:
                if b["回答"].strip():
                    body.append(f"answer: {b['lines'][0]}")
                    body.extend(b["lines"][1:])
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
        done_b, done_a = _items(before, ["完了"]), _items(after, ["完了"])
        pairs_a = Counter((it.title, it.key) for it in done_a if it.key)
        for (t, k), n in Counter((it.title, it.key) for it in done_b if it.key).items():
            if pairs_a[(t, k)] < n:
                errs.append(f"{source} は完了から戻せない: {k} {t!r}")
        # key の無い完了行は attach で key が付きうるので、タイトルだけで数える
        titles_done_a = Counter(it.title for it in done_a)
        for t, n in Counter(it.title for it in done_b if not it.key).items():
            if titles_done_a[t] < n:
                errs.append(f"{source} は完了から戻せない: {t!r}")
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
    except (ValueError, OverflowError, OSError):
        pass
    try:
        lock.unlink()
    except FileNotFoundError:
        pass
    return False


class _Changed(Exception):
    """読んだ後に todo.md が書き換えられた。"""


def _git(repo: Path, *args: str, retry: bool = False) -> str:
    """retry=True なら index.lock の競合（nvim の git 連携など）を、ロックを消して最大10回まで再試行する。"""
    for n in range(GIT_RETRIES):
        r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8")
        if r.returncode == 0:
            return r.stdout
        if not retry or "index.lock" not in r.stderr or n == GIT_RETRIES - 1:
            raise RuntimeError(f"git {' '.join(args)} failed: {r.stderr.strip()}")
        git_dir = Path(_git(repo, "rev-parse", "--absolute-git-dir").strip())
        (git_dir / "index.lock").unlink(missing_ok=True)
        time.sleep(1)
    raise AssertionError("unreachable")


def _commit_human_edits(repo: Path, name: str) -> None:
    # nvim は保存ごとに書きコミットは閉じるときだけなので、未コミット分を AI のコミットに混ぜると出どころが ai になる
    if not _git(repo, "status", "--porcelain", "--", name).strip():
        return
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    _git(repo, "add", "--", name, retry=True)
    _git(repo, "commit", "-q", "-m", f"todo: {stamp}", "--", name, retry=True)


def _last_written_confirm(repo: Path, name: str) -> "list[str]":
    h = _git(repo, "log", "-1", "--format=%H", "-E", r"--grep=^todo\((ai|sync)\): ", "--", name).strip()
    if not h:
        return []
    try:
        return todo_md.parse(_git(repo, "show", f"{h}:{name}")).confirm
    except (RuntimeError, ValueError):
        return []


def _write_atomic(path: Path, text: str, expect: "str | None" = None) -> None:
    """expect を渡すと、置き換える直前に中身が expect のままか確かめ、違えば書かずに _Changed。"""
    tmp = path.with_name(f".{path.name}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    if path.exists():
        shutil.copymode(path, tmp)
    if expect is not None and path.read_text(encoding="utf-8") != expect:
        tmp.unlink()
        raise _Changed(str(path))
    os.replace(tmp, path)


def _restore(originals: "dict[Path, str | None]") -> None:
    for p, old in originals.items():
        if old is None:
            p.unlink(missing_ok=True)
        else:
            _write_atomic(p, old)


def summarize(body: "list[str]") -> str:
    counts = Counter(l.split(" ", 1)[0].rstrip(":") for l in body)
    parts = [f"{label}{counts[k]}" for k, label in OP_LABELS.items() if counts[k]]
    return " ".join(parts)


def run(changes_path: Path, todo: Path, today: str, decisions_path: "Path | None" = None) -> int:
    try:
        changes = json.loads(changes_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"apply: 変更案を読めない: {e}", file=sys.stderr)
        return 2
    source = changes.get("source") if isinstance(changes, dict) else None
    repo, name = todo.parent, todo.name
    dpath = (decisions_path or repo / decisions.DECISIONS_NAME).expanduser().absolute()
    if not todo.is_file():
        print(f"apply: todo.md が無い: {todo}", file=sys.stderr)
        return 1
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
            old_records = decisions.load(dpath)
            new_records = decisions.detect_reverts(repo, name, old_records)
            pinned = {r["ref"] for r in old_records + new_records if r.get("kind") == "revert_move"}
            after, body = apply_changes(before, changes, lambda t: origin_of(repo, name, t), today, pinned)
        except ValueError as e:
            print(f"apply: 未適用: {e}", file=sys.stderr)
            return 2
        errs = validate(before, after, lambda t: origin_of(repo, name, t), source) + roundtrip_errors(after)
        if "confirm" in changes:
            errs += confirm_edit_errors(before.confirm, _last_written_confirm(repo, name))
        if errs:
            print("apply: 検証違反のため未適用:\n" + "\n".join(errs), file=sys.stderr)
            return 2
        ts = decisions.now_iso()
        for a in changes.get("answered", []) if "confirm" in changes else []:
            new_records.append({"ts": ts, "ref": a.get("ref"), "kind": a.get("kind"),
                                "value": a["answer"], "by": "human"})
        body += [f"record {r['kind']} {r['ref']}" for r in new_records]
        kept, archived = split_archive(after, today)
        new_text = todo_md.render(kept)
        todo_changed = new_text != todo_md.render(before) or bool(archived)
        if not todo_changed and not new_records:
            return 0
        if nvim_editing(repo) or todo.read_text(encoding="utf-8") != text:
            print("apply: todo.md を編集中のためスキップ", file=sys.stderr)
            return 3

        archive_dir = repo / "todo-archive"
        originals: "dict[Path, str | None]" = {}
        for month, items in sorted(archived.items()):
            p = archive_dir / f"{month}.md"
            originals[p] = p.read_text(encoding="utf-8") if p.exists() else None
            archive_dir.mkdir(exist_ok=True)
            _write_atomic(p, (originals[p] or "") + "".join(todo_md._render_item(it) + "\n" for it in items))
            body += [f"archive {it.ref} → todo-archive/{month}.md" for it in items]
        if new_records:
            originals[dpath] = dpath.read_text(encoding="utf-8") if dpath.exists() else None
            _write_atomic(dpath, (originals[dpath] or "") + decisions.render_lines(new_records))
        if todo_changed:
            try:
                _write_atomic(todo, new_text, expect=text)
            except _Changed:
                _restore(originals)
                print("apply: 読んだ後に todo.md が変わったためスキップ", file=sys.stderr)
                return 3

        paths = ([name] if todo_changed else []) + [p for p in ("todo-archive", "todo-decisions.jsonl") if (repo / p).exists()]
        if dpath.exists() and dpath.parent == repo and dpath.name != "todo-decisions.jsonl":
            paths.append(dpath.name)
        subject = summarize(body) or "判断の記録"
        try:
            _git(repo, "add", "--", *paths, retry=True)
            _git(repo, "commit", "-q", "-m", f"todo({source}): {subject}", "-m", "\n".join(body),
                 "--", *paths, retry=True)
        except RuntimeError:
            # 未コミットのまま残すと次の人のコミットに AI の変更が混ざるので戻す。人が触った後なら触らない
            try:
                if todo_changed:
                    _write_atomic(todo, text, expect=new_text)
                _restore(originals)
            except _Changed:
                pass
            raise
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
    p.add_argument("--decisions", type=Path, help="判断記録（既定は todo.md と同じディレクトリの todo-decisions.jsonl）")
    p.add_argument("--today", default=datetime.date.today().isoformat())
    a = p.parse_args(argv)
    todo = a.todo or Path(os.environ.get("TODO_MD_PATH") or Path.home() / "memo" / "todo.md")
    try:
        datetime.date.fromisoformat(a.today)
        return run(a.changes, todo.expanduser().absolute(), a.today, a.decisions)
    except Exception as e:
        print(f"apply: {type(e).__name__}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
