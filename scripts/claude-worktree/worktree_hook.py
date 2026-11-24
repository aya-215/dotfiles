#!/usr/bin/env python3
"""Claude Code の WorktreeCreate / WorktreeRemove フック。worktree の置き場所・ブランチ名・コピーをうちの決まりに合わせる。

設計: docs/superpowers/specs/2026-11-24-claude-worktree-hooks-design.md
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable

KNOWN_TYPES = ("feat", "fix", "docs", "chore", "refactor", "test", "hotfix", "ci", "perf", "build", "style")
PERSONAL_MARKERS = ("github-aya215:", "github.com/aya-215/")
ENV_FILES = (".env.local", ".env.keys")
NODE_MODULES_DEPTH = 3


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


class HookError(Exception):
    """利用者に見せる理由付きの失敗。"""


def _run(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    r = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    # フックの stdout はパスだけにする決まりなので、git の出力は stderr へ流す
    sys.stderr.write(r.stdout + r.stderr)
    return r


def _ok(cwd: Path, *args: str) -> bool:
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True).returncode == 0


def _out(cwd: Path, *args: str) -> "str | None":
    r = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def _must(cwd: Path, *args: str) -> None:
    r = _run(cwd, *args)
    if r.returncode != 0:
        raise HookError(f"git {' '.join(args)} が失敗しました: {r.stderr.strip()}")


def repo_root(cwd: Path) -> Path:
    common = _out(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        raise HookError(f"{cwd} は git リポジトリではありません")
    return Path(common).parent


def _worktrees(root: Path) -> "list[dict]":
    out, cur = [], {}
    for line in (_out(root, "worktree", "list", "--porcelain") or "").splitlines():
        if not line:
            if cur:
                out.append(cur)
            cur = {}
        elif " " in line:
            k, v = line.split(" ", 1)
            cur[k] = v
    if cur:
        out.append(cur)
    return out


def checked_out_at(root: Path, branch: str) -> "str | None":
    for w in _worktrees(root):
        if w.get("branch") == f"refs/heads/{branch}":
            return w["worktree"]
    return None


def _registered(root: Path, path: Path) -> bool:
    return any(Path(w["worktree"]) == path for w in _worktrees(root))


def gh_pr_head(root: Path, number: int) -> "str | None":
    try:
        r = subprocess.run(["gh", "pr", "view", str(number), "--json", "headRefName", "-q", ".headRefName"],
                           cwd=root, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() or None if r.returncode == 0 else None


def _base(root: Path) -> str:
    for ref in ("origin/main", "origin/master"):
        if _ok(root, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"):
            return ref
    return "HEAD"


def _has_local(root: Path, branch: str) -> bool:
    return _ok(root, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}")


def _has_remote(root: Path, branch: str) -> bool:
    return _ok(root, "rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{branch}")


def create(name: str, cwd: Path, home: Path = Path.home(),
           gh_head: "Callable[[Path, int], str | None]" = gh_pr_head) -> Path:
    root = repo_root(cwd)
    path = placement(root, name, home)
    if path.exists():
        if _registered(root, path):
            return path
        raise HookError(f"{path} が既にありますが worktree として登録されていません。中身を確かめて消してから作り直してください")
    has_origin = _out(root, "config", "--get", "remote.origin.url") is not None
    if has_origin and _run(root, "fetch", "-q", "origin").returncode != 0:
        print("warn: git fetch origin に失敗したので、手元の参照で続けます", file=sys.stderr)

    branch = name
    m = re.fullmatch(r"pr-(\d+)", name)
    if m:
        head = gh_head(root, int(m.group(1)))
        if head:
            branch = head
        else:
            _must(root, "fetch", "-q", "origin", f"+refs/pull/{m.group(1)}/head:refs/heads/{name}")
    elif not (_has_local(root, name) or _has_remote(root, name)):
        branch = new_branch_name(name, is_personal(_out(root, "config", "--get", "remote.origin.url")))

    if _has_local(root, branch) or _has_remote(root, branch):
        where = checked_out_at(root, branch)
        if where:
            raise HookError(f"ブランチ {branch} は {where} で使用中です。そこで claude を起動してください")
    path.parent.mkdir(parents=True, exist_ok=True)
    if _has_local(root, branch):
        _must(root, "worktree", "add", str(path), branch)
    elif _has_remote(root, branch):
        _must(root, "worktree", "add", "--track", "-b", branch, str(path), f"origin/{branch}")
    else:
        _must(root, "worktree", "add", "--no-track", "-b", branch, str(path), _base(root))
    for rel in copy_env(root, path):
        print(f"コピー: {rel}", file=sys.stderr)
    for rel in link_node_modules(root, path):
        print(f"ハードリンク: {rel}", file=sys.stderr)
    return path


def _walk(root: Path):
    """root 以下を歩く。node_modules・.git・.claude/worktrees の中には入らない。(相対ディレクトリ, 子ディレクトリ名, ファイル名) を返す。"""
    for dirpath, dirs, files in os.walk(root):
        rel = Path(dirpath).relative_to(root)
        yield rel, list(dirs), files
        dirs[:] = [d for d in dirs if d not in ("node_modules", ".git") and (rel / d) != Path(".claude/worktrees")]


def copy_env(root: Path, wt: Path) -> "list[str]":
    copied = []
    for rel, _, files in _walk(root):
        for f in files:
            if f in ENV_FILES:
                dst = wt / rel / f
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(root / rel / f, dst)
                copied.append(str(rel / f))
    return copied


def _cp_al(src: Path, dst: Path) -> bool:
    return subprocess.run(["cp", "-al", str(src), str(dst)], capture_output=True).returncode == 0


def link_node_modules(root: Path, wt: Path, cp: "Callable[[Path, Path], bool]" = _cp_al) -> "list[str]":
    if not (root / "package-lock.json").exists():
        return []
    linked = []
    for rel, dirs, _ in _walk(root):
        if "node_modules" not in dirs or len((rel / "node_modules").parts) > NODE_MODULES_DEPTH:
            continue
        dst = wt / rel / "node_modules"
        if not (wt / rel).is_dir() or dst.exists():
            continue
        if cp(root / rel / "node_modules", dst):
            linked.append(str(rel / "node_modules"))
        else:
            # 別のファイルシステム等で失敗したら、半端な複製を消して npm install に任せる
            shutil.rmtree(dst, ignore_errors=True)
            print(f"warn: {rel / 'node_modules'} をハードリンクできなかったので飛ばします", file=sys.stderr)
    return linked
