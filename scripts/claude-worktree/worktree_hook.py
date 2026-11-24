#!/usr/bin/env python3
"""Claude Code の WorktreeCreate / WorktreeRemove フック。worktree の置き場所・ブランチ名・コピーをうちの決まりに合わせる。

設計: docs/superpowers/specs/2026-11-24-claude-worktree-hooks-design.md
"""
from pathlib import Path

KNOWN_TYPES = ("feat", "fix", "docs", "chore", "refactor", "test", "hotfix", "ci", "perf", "build", "style")
PERSONAL_MARKERS = ("github-aya215:", "github.com/aya-215/")


def slug(name: str) -> str:
    return name.replace("/", "-")


def placement(root: Path, name: str, home: Path) -> Path:
    # /mnt/d の本体（Tomcat が直接読む）の中に作ると公開範囲に入るので外へ置く
    if str(root).startswith("/mnt/"):
        return home / "worktrees" / f"{root.name}-{slug(name)}"
    return root / ".claude" / "worktrees" / slug(name)


def is_personal(remote_url: "str | None") -> bool:
    return bool(remote_url) and any(m in remote_url for m in PERSONAL_MARKERS)


def new_branch_name(name: str, personal: bool) -> str:
    if name.split("/", 1)[0] in KNOWN_TYPES and "/" in name:
        return name
    return name if personal else f"feat/{name}"
