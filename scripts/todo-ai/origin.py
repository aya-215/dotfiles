"""todo.md の行が AI 由来か人由来かを git 履歴から判定する。"""
import subprocess
import sys
from pathlib import Path

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
