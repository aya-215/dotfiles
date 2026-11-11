"""人の判断の記録（todo-decisions.jsonl）と、人による AI/同期の変更の戻しの検出。

1行 = {"ts", "ref", "kind", "value", "by": "human"} と、任意の "commit"（検出元の AI/同期コミット）。
kind は確認待ちの kind、または revert_move / reject_add / intent。
intent はユーザー指示（source user）の意図で、key の無い行の改名では "prev_ref" に旧 ref を持つ。
確認待ちの回答に基づく意図（source ai の by_answer）は "by_answer": {ref, kind} を持ち、edit_title なら "title" に新しい題を持つ。
"op" は意図を残した op（delete / edit_title 等。古い記録には無い）。
revert_move は戻された AI/同期の移動を "from"→"to" で持つ（value は人が戻した先 = from）。
"to" の無い古い記録は、戻し先以外への移動をすべて止める。
alias は apply が key の無い行に key を付けた・source ai が key の無い行の題を変えた印（{"ts", "ref": <key か新しい
title: ref>, "kind": "alias", "prev_ref": <旧 title: ref>, "by": "ai"}）。人の判断ではなく、行の系譜をつなぐだけ。
確認待ちの回答（kind が確認待ちの kind）の "stale": true は、問いを書いた後に同じ行の意図が記録されていたもの。
行の系譜: ref の記録に、alias と intent の prev_ref を後ろ向きに辿った旧 ref の、つないだ時点より前の記録を足したもの。
"""
import datetime
import json
import subprocess
import sys
from pathlib import Path
from typing import Iterable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import todo_md

DECISIONS_NAME = "todo-decisions.jsonl"
CLEANUP_PREFIX = "後片付け（"
_LINKS = ("alias", "intent")


def load(path: Path) -> "list[dict]":
    try:
        text = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return []
    return parse_text(text)


def parse_text(text: str) -> "list[dict]":
    out = []
    for line in todo_md.split_lines(text):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            out.append(rec)
    return out


def render_lines(records: "list[dict]") -> str:
    return "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records)


def append(path: Path, records: "list[dict]") -> None:
    if not records:
        return
    path = Path(path)
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    if old and not old.endswith("\n"):
        old += "\n"
    path.write_text(old + render_lines(records), encoding="utf-8")


def lineage(records: "list[dict]", ref: str, end: "int | None" = None) -> "list[tuple[int, dict]]":
    """ref の行の系譜の記録を (位置, 記録) で新しい順に返す。end を渡すとその位置より前だけを見る。"""
    # 同じ実行の記録は ts が同じなので、追記順（ファイル内の位置）を時系列とみなす
    refs, out = {ref}, []
    for i in range((len(records) if end is None else end) - 1, -1, -1):
        r = records[i]
        if r.get("ref") not in refs:
            continue
        out.append((i, r))
        if r.get("kind") in _LINKS and isinstance(r.get("prev_ref"), str):
            refs.add(r["prev_ref"])
    return out


def lineage_refs(records: "list[dict]", ref: str, end: "int | None" = None) -> "set[str]":
    return {ref} | {r["prev_ref"] for _, r in lineage(records, ref, end)
                    if r.get("kind") in _LINKS and isinstance(r.get("prev_ref"), str)}


def pinned_sections(records: "list[dict]", ref: str) -> "list[str]":
    """人が戻したため、ref をもう動かしてはいけない移動先（TASK_SECTIONS の順）。系譜の旧 ref の記録も含める。"""
    blocked = set()
    for _, r in lineage(records, ref):
        if r.get("kind") != "revert_move":
            continue
        if r.get("to") in todo_md.TASK_SECTIONS:
            blocked.add(r["to"])
        else:
            blocked |= set(todo_md.TASK_SECTIONS) - {r.get("value")}
    return [s for s in todo_md.TASK_SECTIONS if s in blocked]


def is_pinned(records: "list[dict]", ref: str, to: str) -> bool:
    return to in pinned_sections(records, ref)


def is_rejected(records: "list[dict]", ref: str) -> bool:
    return any(r.get("ref") == ref and r.get("kind") == "reject_add" for r in records)


def deleted_refs(records: "list[dict]", present: "Iterable[str]" = ()) -> "list[str]":
    """ユーザー指示で台帳から消えた ref（delete した行の系譜の ref と、edit_title で変わる前の ref）。

    後で同じ ref を台帳に戻す指示（add 等）があれば外す。note は台帳を変えないので数えない。
    present（今の台帳にある ref）は外す。人が書き戻した行は、ふつうの行として扱う。
    """
    out: "set[str]" = set()
    for i, r in enumerate(records):
        if r.get("kind") != "intent" or not isinstance(r.get("ref"), str):
            continue
        op = r.get("op")
        if op == "delete":
            out |= lineage_refs(records, r["ref"], i + 1)
        elif op != "note":
            out.discard(r["ref"])
            prev = r.get("prev_ref")
            if op == "edit_title" and isinstance(prev, str) and prev != r["ref"]:
                out.add(prev)
    return sorted(out - set(present))


def superseded(records: "list[dict]", pos: int) -> bool:
    """pos の conflict の回答が、後から記録された同じ行（key 付け・改名の後も含む）の意図で古くなったか。"""
    r = records[pos]
    if r.get("kind") != "conflict":
        return False
    if r.get("stale"):
        return True
    refs = {r.get("ref")}
    for x in records[pos + 1:]:
        if x.get("kind") in _LINKS and x.get("prev_ref") in refs:
            refs.add(x.get("ref"))
        if x.get("kind") == "intent" and x.get("ref") in refs:
            return True
    return False


def answers(records: "list[dict]", ref: str, kinds: "Iterable[str]") -> "list[tuple[int, dict]]":
    """ref の行の系譜にある、人の確認待ちへの回答を (位置, 記録) で新しい順に返す。"""
    kinds = set(kinds)
    return [(i, r) for i, r in lineage(records, ref) if r.get("kind") in kinds and r.get("by", "human") == "human"]


def already_answered(records: "list[dict]", ref: str, kind: str) -> "dict | None":
    """ref の行への kind の有効な回答（新しいもの）。conflict は、後から意図が記録されたら無効。"""
    return next((r for i, r in answers(records, ref, [kind]) if not superseded(records, i)), None)


def newest_intent_pos(records: "list[dict]", ref: str) -> int:
    return next((i for i, r in lineage(records, ref) if r.get("kind") == "intent"), -1)


def intents(records: "list[dict]", ref: str) -> "list[dict]":
    """ref の意図の記録を新しい順に返す。系譜（key 付け・改名より前の旧 ref）の記録も含める。"""
    return [r for _, r in lineage(records, ref) if r.get("kind") == "intent"]


def answer_titles(records: "list[dict]") -> "set[str]":
    """確認待ちの回答（by_answer）に基づく edit_title で付けた題。人の言葉なので、todo(ai) のコミットでも人の題として扱う。"""
    return {r["title"] for r in records if r.get("kind") == "intent" and r.get("op") == "edit_title"
            and r.get("by_answer") and isinstance(r.get("title"), str)}


def now_iso() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def _git(repo: Path, *args: str) -> "str | None":
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8")
    return r.stdout if r.returncode == 0 else None


def _sections(text: "str | None") -> "dict[str, str] | None":
    """ref -> セクション名。パースできない・同じ ref が複数ある行は除く。None は読めない。"""
    if text is None:
        return None
    try:
        doc = todo_md.parse(text)
    except ValueError:
        return None
    found: "dict[str, list[str]]" = {}
    for s in todo_md.TASK_SECTIONS:
        for it in doc.sections[s]:
            found.setdefault(it.ref, []).append(s)
    return {r: v[0] for r, v in found.items() if len(v) == 1}


MAX_SCAN = 50
_OPEN = ("やる", "待ち")


def _sections_at(repo: Path, revs: "list[str]") -> "list[dict[str, str] | None]":
    """各 rev（`<commit>:<path>` の形）の _sections。git は1回だけ起動する。"""
    r = subprocess.run(["git", "-C", str(repo), "cat-file", "--batch"], input="".join(v + "\n" for v in revs).encode(),
                       capture_output=True)
    if r.returncode != 0:
        return [None] * len(revs)
    data, pos, out = r.stdout, 0, []
    for _ in revs:
        end = data.index(b"\n", pos)
        header = data[pos:end].split()
        pos = end + 1
        if len(header) != 3 or header[1] != b"blob":
            out.append(None)
            continue
        size = int(header[2])
        blob, pos = data[pos:pos + size], pos + size + 1
        try:
            out.append(_sections(blob.decode("utf-8")))
        except UnicodeDecodeError:
            out.append(None)
    return out


def detect_reverts(repo: Path, path: str, records: "list[dict] | None" = None) -> "list[dict]":
    """直近 MAX_SCAN 件の todo(ai)/todo(sync)/todo(user) コミットを古い順に見て、まだ記録していない人の戻しを返す。

    各 ai/sync コミット C を C^・C・HEAD で比べる。C より後の ai/sync/user コミットが同じ ref を動かしていれば、
    その ref は C では判定しない（後の正当な移動や /todo-edit の変更を戻しと誤検出しない）。記録済みかは (commit, ref) で見る。
    title: の ref の追加の消去は、後片付け（題が日付で変わる）だけ reject_add にする。後片付けは、消える直前に
    やる・待ちにあり、消えた時点の台帳のやる・待ちに後片付けの行が残っていないときだけ（完了からの片付けと、題の手直しは除く）。
    records を省くと repo/todo-decisions.jsonl を読む。
    """
    repo = Path(repo)
    if records is None:
        records = load(repo / DECISIONS_NAME)
    out = _git(repo, "log", f"-{MAX_SCAN}", "--format=%H %s", "-E", r"--grep=^todo\((ai|sync|user)\): ", "--", path)
    log = [l.split(" ", 1) for l in reversed((out or "").splitlines()) if l]
    commits = [h for h, _ in log]
    # todo(user) は /todo-edit の承認済みの変更で意図が別に残る。後の変更として数えるだけで、戻しの検出元にしない
    by_user = [subj.startswith("todo(user): ") for _, subj in log]
    if not commits:
        return []
    recorded = {(r.get("commit"), r.get("ref")) for r in records if r.get("commit")}
    head, *got = _sections_at(repo, [f"HEAD:{path}"] + [v for c in commits for v in (f"{c}^:{path}", f"{c}:{path}")])
    if head is None:
        return []
    pairs = [(got[2 * i], got[2 * i + 1]) for i in range(len(commits))]

    later: "list[set[str]]" = [set() for _ in commits]
    acc: "set[str]" = set()
    for i in range(len(commits) - 1, -1, -1):
        later[i] = set(acc)
        p, a = pairs[i]
        if p is not None and a is not None:
            acc |= {r for r in set(p) | set(a) if p.get(r) != a.get(r)}

    after_c: "dict[str, list[dict[str, str] | None]]" = {}

    def cleanup_dropped(c: str, ref: str, added_to: str) -> bool:
        if c not in after_c:
            hs = (_git(repo, "log", "--format=%H", f"{c}..HEAD", "--", path) or "").split()
            after_c[c] = _sections_at(repo, [f"{h}:{path}" for h in hs]) if hs else [head]
        snaps = after_c[c]
        # 新しい順。ref が最後に載った版の1つ新しい版が、消えた時点の台帳（毎回 HEAD で見ると、後で完了にした改名行で判定が変わる）
        k = next((j for j, x in enumerate(snaps) if x is not None and ref in x), len(snaps))
        last = snaps[k][ref] if k < len(snaps) else added_to
        gone = snaps[k - 1] if k > 0 else None
        return gone is not None and last in _OPEN and not any(
            r.startswith("title:" + CLEANUP_PREFIX) and v in _OPEN for r, v in gone.items())

    ts = now_iso()
    new = []
    for i, c in enumerate(commits):
        parent, after = pairs[i]
        if by_user[i] or parent is None or after is None:
            continue
        for ref in sorted(set(parent) | set(after)):
            if ref in later[i] or (c, ref) in recorded:
                continue
            p, s, h = parent.get(ref), after.get(ref), head.get(ref)
            if p is not None and s is not None and p != s and h == p:
                rec = {"kind": "revert_move", "value": p, "from": p, "to": s}
            elif p is None and s is not None and h is None and (
                    not ref.startswith("title:") or (ref.startswith("title:" + CLEANUP_PREFIX)
                                                     and cleanup_dropped(c, ref, s))):
                rec = {"kind": "reject_add", "value": s}
            else:
                continue
            new.append({"ts": ts, "ref": ref, **rec, "by": "human", "commit": c})
    return new
