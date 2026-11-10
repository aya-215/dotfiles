"""todo.md の行が AI 由来か人由来かを git 履歴から判定する。"""
import subprocess
from pathlib import Path


def _git(repo: Path, *args: str) -> str:
    r = subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8"
    )
    return r.stdout if r.returncode == 0 else ""


def origin_of(repo: Path, path: str, title: str) -> str:
    """title を最初に入れたコミットが `todo(ai):` なら "ai"。曖昧なときは保護側の "human"。"""
    if not title:
        return "human"
    # 部分一致の別行も数えて、同名・包含タイトルは human 側に倒す
    head = _git(repo, "show", f"HEAD:{path}")
    if sum(1 for line in head.splitlines() if title in line) > 1:
        return "human"
    out = _git(repo, "log", "-S" + title, "--reverse", "--format=%s", "--", path)
    first = out.splitlines()[0] if out.splitlines() else ""
    return "ai" if first.startswith("todo(ai):") else "human"
