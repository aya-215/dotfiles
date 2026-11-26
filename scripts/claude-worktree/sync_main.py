#!/usr/bin/env python3
"""worktree の仕上げで、本体のチェックアウトを origin/main まで早送りで進め、結果を1行で出す。

本体が main でない・ローカル main に未 push のコミットがある・git が早送りを断ったときは何も変えず理由を出す。
終了コード: 0 進めた／最新、3 理由があって進めない、1 fetch の失敗。
設計: docs/superpowers/specs/2026-11-26-claude-worktree-finish-design.md
"""
import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from worktree_hook import FETCH_TIMEOUT, _GIT_ENV  # noqa: E402


def _git(root: Path, *args: str, timeout: "float | None" = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, env=_GIT_ENV,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", f"{timeout} 秒で終わりませんでした")


def _first_line(text: str) -> str:
    return next((line.strip() for line in text.splitlines() if line.strip()), "")


def sync(root: Path) -> "tuple[int, str]":
    branch = _git(root, "branch", "--show-current").stdout.strip()
    if branch != "main":
        return 3, f"本体は {branch or '(detached)'} を使用中なので進めない"
    r = _git(root, "fetch", "-q", "origin", timeout=FETCH_TIMEOUT)
    if r.returncode != 0:
        return 1, f"fetch に失敗: {_first_line(r.stderr)}"
    unpushed = _git(root, "rev-list", "--count", "origin/main..main").stdout.strip()
    if unpushed != "0":
        return 3, f"本体の main に未 push のコミットが {unpushed} 件あるので進めない"
    before = _git(root, "rev-parse", "HEAD").stdout.strip()
    # pull.rebase=true だと git pull は手元に変更があるだけで断るので、merge --ff-only で重なりだけを git に判定させる
    r = _git(root, "merge", "--ff-only", "-q", "origin/main")
    if r.returncode != 0:
        return 3, f"git が早送りを断った: {_first_line(r.stderr)}"
    after = _git(root, "rev-parse", "HEAD").stdout.strip()
    if after == before:
        return 0, "最新"
    n = _git(root, "rev-list", "--count", f"{before}..{after}").stdout.strip()
    return 0, f"進めた: {before[:7]} → {after[:7]}（{n} コミット）"


def main(argv: "list[str] | None" = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", type=Path, default=Path.home() / ".dotfiles")
    code, line = sync(p.parse_args(argv).repo)
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
