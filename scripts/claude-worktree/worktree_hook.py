#!/usr/bin/env python3
"""Claude Code の WorktreeCreate / WorktreeRemove フック。worktree の置き場所・ブランチ名・コピーをうちの決まりに合わせる。

設計: docs/superpowers/specs/2026-11-24-claude-worktree-hooks-design.md
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable, TextIO

KNOWN_TYPES = ("feat", "fix", "docs", "chore", "refactor", "test", "hotfix", "ci", "perf", "build", "style")
PERSONAL_MARKERS = ("github-aya215:", "github.com/aya-215/")
ENV_FILES = (".env.local", ".env.keys")
FETCH_TIMEOUT = 60
# フックが認証プロンプトで止まると claude -w ごと 600 秒待たされるので、聞かずに失敗させる
_GIT_ENV = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
_GIT_ENV.setdefault("GIT_SSH_COMMAND", "ssh -o BatchMode=yes")
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


def _run(cwd: Path, *args: str, timeout: "float | None" = None) -> subprocess.CompletedProcess:
    try:
        r = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, env=_GIT_ENV,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", f"git {' '.join(args)} が {timeout} 秒で終わりませんでした\n")
    # フックの stdout はパスだけにする決まりなので、git の出力は stderr へ流す
    sys.stderr.write(r.stdout + r.stderr)
    return r


def _ok(cwd: Path, *args: str) -> bool:
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, env=_GIT_ENV).returncode == 0


def _out(cwd: Path, *args: str) -> "str | None":
    r = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, env=_GIT_ENV)
    return r.stdout.strip() if r.returncode == 0 else None


def _must(cwd: Path, *args: str, timeout: "float | None" = None) -> None:
    r = _run(cwd, *args, timeout=timeout)
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


def _gh_accounts(run: Callable = subprocess.run) -> "list[str]":
    try:
        r = run(["gh", "auth", "status", "--hostname", "github.com"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    return re.findall(r"account (\S+)", r.stdout + r.stderr)


def gh_pr_head(root: Path, number: int, run: Callable = subprocess.run,
               accounts: "list[str] | None" = None) -> "str | None":
    """PR の head ブランチ名。今のアカウントで取れなければ、ログイン済みの別アカウントでも試す。"""
    cmd = ["gh", "pr", "view", str(number), "--json", "headRefName", "-q", ".headRefName"]

    def view(env: "dict | None") -> "str | None":
        try:
            r = run(cmd, cwd=root, capture_output=True, text=True, timeout=30, env=env)
        except (OSError, subprocess.SubprocessError):
            return None
        return r.stdout.strip() or None if r.returncode == 0 else None

    head = view(None)
    if head:
        return head
    for acct in _gh_accounts(run) if accounts is None else accounts:
        try:
            t = run(["gh", "auth", "token", "--user", acct], capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError):
            continue
        if t.returncode == 0 and t.stdout.strip():
            head = view({**os.environ, "GH_TOKEN": t.stdout.strip()})
            if head:
                return head
    return None


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
    if has_origin and _run(root, "fetch", "-q", "origin", timeout=FETCH_TIMEOUT).returncode != 0:
        print("warn: git fetch origin に失敗したので、手元の参照で続けます", file=sys.stderr)

    branch = name
    m = re.fullmatch(r"pr-(\d+)", name)
    if m:
        head = gh_head(root, int(m.group(1)))
        if head and (_has_local(root, head) or _has_remote(root, head)):
            branch = head
        else:
            # fork からの PR やマージ後に消えた head は origin に無いので、PR の head そのものを取る
            refspec = f"refs/pull/{m.group(1)}/head:refs/heads/{name}"
            print(f"warn: PR #{m.group(1)} のブランチを取れなかったので {name} で開きます。"
                  f"ここで push しても PR は更新されません（gh auth status を確かめてください）", file=sys.stderr)
            if not _has_local(root, name):
                _must(root, "fetch", "-q", "origin", refspec, timeout=FETCH_TIMEOUT)
            elif _run(root, "fetch", "-q", "origin", refspec, timeout=FETCH_TIMEOUT).returncode != 0:
                # + を付けないので fast-forward できないときは断られる。手元のコミットを守ってそのまま開く
                print(f"warn: 手元の {name} を PR の head に進められなかったので、手元のまま開きます", file=sys.stderr)
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
    # ここで失敗すると worktree は出来ているのに claude -w が失敗扱いになるので、警告だけにする
    try:
        for rel in copy_env(root, path):
            print(f"コピー: {rel}", file=sys.stderr)
    except OSError as e:
        print(f"warn: .env のコピーに失敗しました: {e}", file=sys.stderr)
    try:
        for rel in link_node_modules(root, path):
            print(f"ハードリンク: {rel}", file=sys.stderr)
    except OSError as e:
        print(f"warn: node_modules の複製に失敗しました: {e}", file=sys.stderr)
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


def _same_device(a: Path, b: Path) -> bool:
    return os.stat(a).st_dev == os.stat(b).st_dev


def link_node_modules(root: Path, wt: Path, cp: "Callable[[Path, Path], bool]" = _cp_al,
                      same_device: "Callable[[Path, Path], bool]" = _same_device) -> "list[str]":
    if not (root / "package-lock.json").exists():
        return []
    if not same_device(root, wt):
        # /mnt/d の本体と ~/worktrees のように別のファイルシステムだとハードリンクは必ず失敗する
        print("warn: 本体と worktree が別のファイルシステムなので node_modules は複製しません", file=sys.stderr)
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


def remove(worktree_path: Path) -> int:
    if not worktree_path.exists():
        return 0
    branch = _out(worktree_path, "branch", "--show-current")
    common = _out(worktree_path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common:
        root = Path(common).parent
        # Claude Code は変更があれば消してよいか聞いてから呼ぶので、ここでは --force でよい
        _run(root, "worktree", "remove", "--force", str(worktree_path))
        if branch and not worktree_path.exists() and _run(root, "branch", "-d", branch).returncode != 0:
            print(f"ブランチ {branch} は手元にしか無いコミットがあるので残しました", file=sys.stderr)
    if worktree_path.exists():
        print(f"{worktree_path} を消せませんでした", file=sys.stderr)
        return 1
    return 0


def main(argv: "list[str] | None" = None, stdin: TextIO = sys.stdin) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create", help="worktree を作る（引数が無ければ stdin のフック JSON を読む）")
    c.add_argument("--name")
    c.add_argument("--cwd", type=Path)
    sub.add_parser("remove", help="worktree を消す（stdin のフック JSON を読む）")
    a = p.parse_args(argv)
    try:
        if a.cmd == "create":
            if a.name:
                name, cwd = a.name, a.cwd or Path.cwd()
            else:
                data = json.load(stdin)
                name, cwd = data["name"], Path(data["cwd"])
            print(create(name, cwd))
            return 0
        return remove(Path(json.load(stdin)["worktree_path"]))
    except HookError as e:
        print(f"worktree の処理に失敗しました: {e}", file=sys.stderr)
    except (ValueError, KeyError) as e:
        print(f"フックの入力を読めません: {e}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
