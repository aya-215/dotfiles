"""todo.md の行が AI 由来か人由来かを git 履歴から判定する。"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import todo_md

AI_SUBJECTS = ("todo(ai):", "todo(sync):")


def _git(repo: Path, *args: str) -> str:
    r = subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8"
    )
    if r.returncode != 0:
        print(f"origin: git {args[0]} failed: {r.stderr.strip()}", file=sys.stderr)
        return ""
    return r.stdout


def origin_of(repo: Path, path: str, title: str) -> str:
    """title の出現数を変えたコミットがすべて `todo(ai):` / `todo(sync):` なら "ai"。曖昧なときは保護側の "human"。"""
    if not title:
        return "human"
    # 作業ツリーを優先し、部分一致の別行も数えて、同名・包含タイトルは human 側に倒す
    try:
        current = (Path(repo) / path).read_text(encoding="utf-8")
    except (OSError, ValueError):
        try:
            current = _git(repo, "show", f"HEAD:{path}")
        except ValueError:
            return "human"
    if sum(1 for line in current.split("\n") if title in line) > 1:
        return "human"
    try:
        out = _git(repo, "log", "-S" + title, "--reverse", "--format=%s", "--", path)
    except ValueError:
        return "human"
    subjects = out.splitlines()
    # 確認待ちの問い・タグに題が出ても出現数は変わるので、件数ではなく人のコミットが混ざるか（消して打ち直し等）で見る
    if not subjects or not all(s.startswith(AI_SUBJECTS) for s in subjects):
        return "human"
    return "ai"


SCAN_CHUNK = 50


def _has_title(blob: "bytes | None", title: str) -> "bool | None":
    """blob の台帳のタスク行に title ちょうどの題があるか。blob が無ければ False、読めなければ None。"""
    if blob is None:
        return False
    try:
        doc = todo_md.parse(blob.decode("utf-8"))
    except ValueError:
        return None
    return any(it.title == title for sec in todo_md.TASK_SECTIONS for it in doc.sections[sec])


def _blobs(repo: Path, revs: "list[str]") -> "list[bytes | None]":
    r = subprocess.run(["git", "-C", str(repo), "cat-file", "--batch"], input="".join(v + "\n" for v in revs).encode(),
                       capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.decode(errors="replace").strip())
    data, pos, out = r.stdout, 0, []
    for _ in revs:
        end = data.index(b"\n", pos)
        header = data[pos:end].split()
        pos = end + 1
        if len(header) != 3 or header[1] != b"blob":
            out.append(None)
            continue
        size = int(header[2])
        out.append(data[pos:pos + size])
        pos += size + 1
    return out


def title_written_by(repo: Path, path: str, title: str) -> str:
    """タスク行の題をちょうど title にした最後のコミットが ai/sync なら "ai"。人なら・分からなければ "human"。

    origin_of は題の出現数で見るので、人が AI の題を縮めて元の題の一部にした変更を拾えない。行の題の完全一致で見る。
    """
    if not title:
        return "human"
    out = _git(repo, "log", "--format=%H %s", "--", path)
    log = [l.split(" ", 1) for l in out.splitlines() if l]
    try:
        for i in range(0, len(log), SCAN_CHUNK):
            chunk = log[i:i + SCAN_CHUNK]
            blobs = _blobs(repo, [r for h, _ in chunk for r in (f"{h}:{path}", f"{h}^:{path}")])
            for j, (_, subject) in enumerate(chunk):
                now, before = _has_title(blobs[2 * j], title), _has_title(blobs[2 * j + 1], title)
                if now is None or before is None:
                    return "human"
                if now and not before:
                    return "ai" if subject.startswith(AI_SUBJECTS) else "human"
    except (RuntimeError, ValueError):
        return "human"
    return "human"
