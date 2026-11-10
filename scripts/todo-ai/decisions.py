"""人の判断の記録（todo-decisions.jsonl）と、人による AI/同期の変更の戻しの検出。

1行 = {"ts", "ref", "kind", "value", "by": "human"} と、任意の "commit"（検出元の AI/同期コミット）。
kind は確認待ちの kind、または revert_move / reject_add。
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
    for line in text.splitlines():
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


def is_pinned(records: "list[dict]", ref: str) -> bool:
    return any(r.get("ref") == ref and r.get("kind") == "revert_move" for r in records)


def already_answered(records: "list[dict]", ref: str, kind: str) -> "dict | None":
    hits = [r for r in records if r.get("ref") == ref and r.get("kind") == kind]
    return hits[-1] if hits else None


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


def detect_reverts(repo: Path, path: str, records: "list[dict] | None" = None) -> "list[dict]":
    """記録済みの最後のコミットより後の todo(ai)/todo(sync) コミットを古い順に見て、人の戻しの記録を返す。

    各 C を C^・C・HEAD で比べる。C より後の AI/同期コミットが同じ ref を動かしていれば、その ref は
    C では判定しない（後の正当な移動を戻しと誤検出しない）。records を省くと repo/todo-decisions.jsonl を読む。
    """
    repo = Path(repo)
    if records is None:
        records = load(repo / DECISIONS_NAME)
    out = _git(repo, "log", f"-{MAX_SCAN}", "--format=%H", "-E", r"--grep=^todo\((ai|sync)\): ", "--", path)
    commits = list(reversed((out or "").split()))
    recorded = {r.get("commit") for r in records if r.get("commit")}
    last = max((i for i, c in enumerate(commits) if c in recorded), default=-1)
    head = _sections(_git(repo, "show", f"HEAD:{path}"))
    if head is None:
        return []
    cache: "dict[str, tuple]" = {}

    def pair(c):
        if c not in cache:
            cache[c] = (_sections(_git(repo, "show", f"{c}^:{path}")), _sections(_git(repo, "show", f"{c}:{path}")))
        return cache[c]

    def moved_by(c):
        p, a = pair(c)
        if p is None or a is None:
            return set()
        return {r for r in set(p) | set(a) if p.get(r) != a.get(r)}

    ts = now_iso()
    new = []
    for i, c in enumerate(commits):
        if i <= last or c in recorded:
            continue
        parent, after = pair(c)
        if parent is None or after is None:
            continue
        later = set()
        for l in commits[i + 1:]:
            later |= moved_by(l)
        for ref in sorted(set(parent) | set(after)):
            if ref in later:
                continue
            p, s, h = parent.get(ref), after.get(ref), head.get(ref)
            if p is not None and s is not None and p != s and h == p:
                kind, value = "revert_move", p
            elif p is None and s is not None and h is None and not ref.startswith("title:"):
                kind, value = "reject_add", s
            else:
                continue
            new.append({"ts": ts, "ref": ref, "kind": kind, "value": value, "by": "human", "commit": c})
    return new
