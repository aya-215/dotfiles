"""人の判断の記録（todo-decisions.jsonl）と、人による AI/同期の変更の戻しの検出。

1行 = {"ts", "ref", "kind", "value", "by": "human"} と、任意の "commit"（検出元の AI/同期コミット）。
kind は確認待ちの kind、または revert_move / reject_add / intent。
intent はユーザー指示（source user）の意図で、key の無い行の改名では "prev_ref" に旧 ref を持つ。
revert_move は戻された AI/同期の移動を "from"→"to" で持つ（value は人が戻した先 = from）。
"to" の無い古い記録は、戻し先以外への移動をすべて止める。
"""
import datetime
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import todo_md

DECISIONS_NAME = "todo-decisions.jsonl"


def load(path: Path) -> "list[dict]":
    try:
        text = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return []
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


def pinned_sections(records: "list[dict]", ref: str) -> "list[str]":
    """人が戻したため、ref をもう動かしてはいけない移動先（TASK_SECTIONS の順）。"""
    blocked = set()
    for r in records:
        if r.get("ref") != ref or r.get("kind") != "revert_move":
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


def already_answered(records: "list[dict]", ref: str, kind: str) -> "dict | None":
    hits = [r for r in records if r.get("ref") == ref and r.get("kind") == kind]
    return hits[-1] if hits else None


def intents(records: "list[dict]", ref: str) -> "list[dict]":
    """ref の意図の記録を新しい順に返す。prev_ref を辿り、改名より前の旧 ref の記録も含める。"""
    # 同じ実行の記録は ts が同じなので、追記順（ファイル内の位置）を時系列とみなす
    refs, out = {ref}, []
    for r in reversed(records):
        if r.get("kind") != "intent" or r.get("ref") not in refs:
            continue
        out.append(r)
        if isinstance(r.get("prev_ref"), str):
            refs.add(r["prev_ref"])
    return out


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
    """直近 MAX_SCAN 件の todo(ai)/todo(sync) コミットを古い順に見て、まだ記録していない人の戻しを返す。

    各 C を C^・C・HEAD で比べる。C より後の AI/同期コミットが同じ ref を動かしていれば、その ref は
    C では判定しない（後の正当な移動を戻しと誤検出しない）。記録済みかは (commit, ref) で見る。
    records を省くと repo/todo-decisions.jsonl を読む。
    """
    repo = Path(repo)
    if records is None:
        records = load(repo / DECISIONS_NAME)
    out = _git(repo, "log", f"-{MAX_SCAN}", "--format=%H", "-E", r"--grep=^todo\((ai|sync)\): ", "--", path)
    commits = list(reversed((out or "").split()))
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

    ts = now_iso()
    new = []
    for i, c in enumerate(commits):
        parent, after = pairs[i]
        if parent is None or after is None:
            continue
        for ref in sorted(set(parent) | set(after)):
            if ref in later[i] or (c, ref) in recorded:
                continue
            p, s, h = parent.get(ref), after.get(ref), head.get(ref)
            if p is not None and s is not None and p != s and h == p:
                rec = {"kind": "revert_move", "value": p, "from": p, "to": s}
            elif p is None and s is not None and h is None and not ref.startswith("title:"):
                rec = {"kind": "reject_add", "value": s}
            else:
                continue
            new.append({"ts": ts, "ref": ref, **rec, "by": "human", "commit": c})
    return new
