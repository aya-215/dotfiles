#!/usr/bin/env python3
"""全リポジトリの worktree を列挙し、削除してよいかの判定材料と分類を出す。

使い方:
    python3 worktree_scan.py [--json] [--no-fetch] [--no-size] [--root DIR ...]

対象は `ghq list -p` と ~/worktrees/* から逆引きした本体リポジトリ（本体が /mnt/d 等にあっても拾う）。
git fetch --prune で remote-tracking ref を更新するだけで、作業ツリー・ブランチは一切変更しない。

分類:
    prunable   ディレクトリが消えている（git worktree prune で掃除）
    locked     git worktree lock されている
    dirty      追跡ファイルに未コミット変更あり（作業中）。REGENERATED のファイルだけの変更は数えない
    merged     取り込み済み かつ 追跡ファイルの変更なし → まとめ削除候補
    unstarted  base の祖先だがブランチで一度もコミットしていない（作りたて）
    closed     PR が CLOSED（未マージ）
    open       未マージ
"""

import argparse
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HOME = os.path.expanduser("~")
GITHUB = re.compile(r"github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?/?$")
# ツールが勝手に書き換える追跡ファイル（next dev の AGENTS.md、npm install の lockfile）
REGENERATED = {"AGENTS.md", "package-lock.json"}


def run(cmd, cwd=None, timeout=120):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, ""
    return p.returncode, p.stdout


def git(repo, *args, timeout=120):
    return run(["git", "-C", repo, *args], timeout=timeout)


def drop_index_lock(worktree):
    # /mnt 配下は Windows 側エディタの git status がロックを掴みっぱなしにしやすい
    if not worktree.startswith("/mnt/"):
        return
    rc, out = git(worktree, "rev-parse", "--path-format=absolute", "--git-dir")
    if rc == 0:
        try:
            os.remove(os.path.join(out.strip(), "index.lock"))
        except FileNotFoundError:
            pass


def candidate_dirs(roots):
    dirs = []
    rc, out = run(["ghq", "list", "-p"])
    if rc == 0:
        dirs += out.split()
    for root in roots:
        if os.path.isdir(root):
            dirs += [os.path.join(root, d) for d in sorted(os.listdir(root))]
    return dirs


def common_dirs(dirs):
    def resolve(d):
        rc, out = git(d, "rev-parse", "--path-format=absolute", "--git-common-dir", timeout=30)
        return out.strip() if rc == 0 else None

    with ThreadPoolExecutor(8) as ex:
        found = set(filter(None, ex.map(resolve, dirs)))
    return sorted(found)


def parse_worktrees(common):
    rc, out = git(common, "worktree", "list", "--porcelain")
    if rc != 0:
        return []
    entries, cur = [], {}
    for line in out.splitlines() + [""]:
        if not line:
            if cur:
                entries.append(cur)
            cur = {}
            continue
        key, _, val = line.partition(" ")
        cur[key] = val or True
    return entries


def github_slug(repo):
    rc, out = git(repo, "remote", "get-url", "origin")
    m = GITHUB.search(out.strip()) if rc == 0 else None
    return m.group(1) if m else None


def base_ref(repo):
    for ref in ("origin/main", "origin/master"):
        if git(repo, "rev-parse", "--verify", "--quiet", ref)[0] == 0:
            return ref
    return None


def pr_states(slug):
    if not slug:
        return {}, None
    rc, out = run(["gh", "pr", "list", "--repo", slug, "--state", "all", "--limit", "500",
                   "--json", "number,state,headRefName,headRefOid"], timeout=60)
    if rc != 0:
        return {}, "取得失敗（gh auth switch で別アカウントを試す）"
    prs = {}
    for pr in json.loads(out or "[]"):
        prs.setdefault(pr["headRefName"], pr)
        # main→prod のようなリリース PR は head が base ブランチそのものなので、コミット一致に使わない
        if pr["headRefName"] not in ("main", "master"):
            prs.setdefault(pr["headRefOid"], pr)
    return prs, None


def has_own_commits(repo, branch):
    # reflog が作成時の1件だけ = このブランチでは一度もコミットしていない
    rc, out = git(repo, "reflog", "show", "--format=%gs", f"refs/heads/{branch}")
    if rc != 0:
        return True
    return any(not s.startswith("branch: Created from") for s in out.splitlines())


def inspect(repo, base, prs, wt, want_size):
    path = wt["worktree"]
    branch = wt.get("branch", "").removeprefix("refs/heads/") or None
    info = {"path": path, "branch": branch, "head": wt.get("HEAD", "")[:9]}

    if "prunable" in wt:
        return {**info, "category": "prunable"}
    if "locked" in wt:
        return {**info, "category": "locked"}

    drop_index_lock(path)
    rc, out = git(path, "status", "--porcelain")
    lines = out.splitlines() if rc == 0 else []
    tracked = [l[3:] for l in lines if not l.startswith("??")]
    info["regenerated"] = [f for f in tracked if os.path.basename(f) in REGENERATED]
    info["tracked_changes"] = len(tracked) - len(info["regenerated"])
    info["untracked"] = sum(1 for l in lines if l.startswith("??"))
    info["last_commit"] = git(path, "log", "-1", "--format=%cs")[1].strip()
    if want_size:
        info["size"] = run(["du", "-sh", path], timeout=600)[1].split("\t")[0]

    pr = prs.get(branch) or prs.get(wt.get("HEAD"))
    info["pr"] = f"#{pr['number']} {pr['state']}" if pr else None
    info["remote_branch"] = bool(branch) and git(repo, "rev-parse", "--verify", "--quiet",
                                                  f"refs/remotes/origin/{branch}")[0] == 0
    ancestor = bool(base) and git(repo, "merge-base", "--is-ancestor", wt["HEAD"], base)[0] == 0
    committed = has_own_commits(repo, branch) if branch else True
    pr_open = bool(pr) and pr["state"] == "OPEN"
    merged = (pr and pr["state"] == "MERGED") or (ancestor and committed and not pr_open)

    if info["tracked_changes"]:
        cat = "dirty"
    elif merged:
        cat = "merged"
    elif ancestor and not pr_open:
        cat = "unstarted"
    elif pr and pr["state"] == "CLOSED":
        cat = "closed"
    else:
        cat = "open"
    return {**info, "ancestor_of_base": ancestor, "category": cat}


def scan_repo(common, fetch, want_size):
    entries = [e for e in parse_worktrees(common) if "bare" not in e]
    if len(entries) < 2:
        return None
    main = entries[0]["worktree"]
    if fetch:
        git(main, "fetch", "--prune", "--quiet", "origin", timeout=180)
    base = base_ref(main)
    slug = github_slug(main)
    prs, pr_error = pr_states(slug)
    with ThreadPoolExecutor(4) as ex:
        wts = list(ex.map(lambda e: inspect(main, base, prs, e, want_size), entries[1:]))
    return {"repo": main, "github": slug, "base": base, "pr_error": pr_error, "worktrees": wts}


LABEL = {
    "prunable": "ディレクトリ消失",
    "locked": "ロック中",
    "dirty": "作業中",
    "merged": "取り込み済み",
    "unstarted": "未着手",
    "closed": "PR CLOSED",
    "open": "未マージ",
}


def render(repos):
    out = []
    for r in repos:
        out.append(f"## {r['repo']}  (base: {r['base']}, github: {r['github'] or '-'})")
        if r["pr_error"]:
            out.append(f"   PR: {r['pr_error']}")
        for w in r["worktrees"]:
            parts = [LABEL[w["category"]]]
            if w.get("pr"):
                parts.append(f"PR{w['pr']}")
            if "remote_branch" in w and w["branch"]:
                parts.append("リモートあり" if w["remote_branch"] else "リモートなし")
            if w.get("tracked_changes"):
                parts.append(f"変更{w['tracked_changes']}")
            if w.get("untracked"):
                parts.append(f"未追跡{w['untracked']}")
            if w.get("regenerated"):
                parts.append(f"再生成ファイル変更: {', '.join(w['regenerated'])}")
            for k in ("last_commit", "size"):
                if w.get(k):
                    parts.append(w[k])
            out.append(f" - {w['branch'] or '(detached ' + w['head'] + ')'}  {w['path']}")
            out.append(f"     {' / '.join(parts)}")
        out.append("")
    n = sum(1 for r in repos for w in r["worktrees"] if w["category"] == "merged")
    out.append(f"まとめ削除候補（取り込み済み・追跡ファイル変更なし）: {n} 件")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-fetch", action="store_true")
    ap.add_argument("--no-size", action="store_true")
    ap.add_argument("--root", action="append", default=[f"{HOME}/worktrees"],
                    help="worktree を置いているディレクトリ（ghq 以外）")
    a = ap.parse_args()

    commons = common_dirs(candidate_dirs(a.root))
    with ThreadPoolExecutor(4) as ex:
        repos = [r for r in ex.map(lambda c: scan_repo(c, not a.no_fetch, not a.no_size), commons) if r]

    if a.json:
        json.dump(repos, sys.stdout, ensure_ascii=False, indent=2)
        print()
    else:
        print(render(repos))


if __name__ == "__main__":
    main()
