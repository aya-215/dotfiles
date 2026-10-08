#!/usr/bin/env python3
"""eBASE AI 3リポジトリの PR レビュー用に、判断を含まない事実だけを一括収集する。

使い方:
    python3 pr_context.py [PR番号] [--repo owner/repo] [--no-fetch]

PR番号を省略すると現在ブランチの PR、--repo を省略すると cwd のリポジトリを対象にする。
作業ツリーは一切変更しない（git fetch で remote-tracking ref を更新するだけ）。
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime

HOME = os.path.expanduser("~")
REPOS = {
    "ebase-dev/ebase-portal-chat": {
        "clone": f"{HOME}/src/github.com/ebase-dev/ebase-portal-chat",
        "wt_prefix": "epc-",
        "preview_workflow": "pr-preview.yml",
    },
    "ebase-dev/ebase-middleware-mcp": {
        "clone": f"{HOME}/src/github.com/ebase-dev/ebase-middleware-mcp",
        "wt_prefix": "emm-",
        "preview_workflow": "eb-api-mcp-pr-preview.yml",
    },
    "ebase-dev/eb-api-extended": {
        "clone": "/mnt/d/tomcat/webapps/eb-api-extended",
        "wt_prefix": None,
        "preview_workflow": None,
    },
}
MY_LOGINS = set(os.environ.get("REVIEWER_LOGINS", "eBASE-Mori,aya-215").split(","))
XREF = re.compile(r"github\.com/(ebase-dev/[\w.-]+)/(pull|issues)/(\d+)")
ALIASES = {
    "ebase-portal-chat": "ebase-dev/ebase-portal-chat",
    "portal-chat": "ebase-dev/ebase-portal-chat",
    "ebase-middleware-mcp": "ebase-dev/ebase-middleware-mcp",
    "eb-api-mcp": "ebase-dev/ebase-middleware-mcp",
    "eb-api-extended": "ebase-dev/eb-api-extended",
}
SHORT_XREF = re.compile(r"(?<![\w/-])(?:ebase-dev/)?(" + "|".join(map(re.escape, ALIASES)) + r")#(\d+)")
PREFIXED_XREF = re.compile(r"\b(MCP|JSP|ext)\s*#(\d+)", re.I)
PREFIX_REPO = {"mcp": "ebase-dev/ebase-middleware-mcp", "jsp": "ebase-dev/eb-api-extended", "ext": "ebase-dev/eb-api-extended"}
BARE_XREF = re.compile(r"(?<![\w/#-])#(\d+)\b")
BOT_LOGINS = {"github-actions[bot]"}
SNIP = 240


def run(cmd, cwd=None, check=True):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}\n{p.stderr.strip()}")
    return p.stdout


def gh_json(args):
    return json.loads(run(["gh", *args]) or "null")


def gh_api_all(path):
    return gh_json(["api", "--paginate", "--slurp", path]) or []


def flat(pages):
    return [x for page in pages for x in (page if isinstance(page, list) else [page])]


def snip(text, n=SNIP):
    t = re.sub(r"\s+", " ", (text or "")).strip()
    return t if len(t) <= n else t[:n] + "…"


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def detect_repo():
    return run(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).strip()


def git(clone, *args, check=True):
    return run(["git", "-C", clone, *args], check=check)


def fetch(clone, refs):
    # /mnt/d 配下はエディタの git 統合が index.lock を掴むことがあるため事前に消す
    lock = os.path.join(clone, ".git", "index.lock")
    if clone.startswith("/mnt/") and os.path.exists(lock):
        os.remove(lock)
    git(clone, "fetch", "--quiet", "origin", *refs, check=False)


def find_worktree(clone, branch):
    out = git(clone, "worktree", "list", "--porcelain", check=False)
    cur = {}
    for line in out.splitlines() + [""]:
        if not line:
            if cur.get("branch") == f"refs/heads/{branch}":
                return cur
            cur = {}
        elif line.startswith("worktree "):
            cur["path"] = line[9:]
        elif line.startswith("HEAD "):
            cur["head"] = line[5:]
        elif line.startswith("branch "):
            cur["branch"] = line[7:]
    return None


def print_others(items, since, title):
    def when(c):
        return c.get("created_at") or c.get("submitted_at")
    others = [c for c in items if when(c) and c["user"]["login"] not in MY_LOGINS | BOT_LOGINS
              and (since is None or ts(when(c)) > since) and (c.get("body") or "").strip()]
    print(f"\n### {title}")
    if not others:
        print("- なし")
    for c in sorted(others, key=lambda c: ts(when(c))):
        loc = f" {c['path']}:{c.get('line') or c.get('original_line')}" if c.get("path") else ""
        print(f"\n#### @{c['user']['login']} {when(c)[:16]}{loc}\n~~~~markdown\n{c['body'].strip()}\n~~~~")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pr", nargs="?")
    ap.add_argument("--repo")
    ap.add_argument("--no-fetch", action="store_true")
    a = ap.parse_args()

    repo = a.repo or detect_repo()
    conf = REPOS.get(repo)
    fields = ("number,title,url,state,isDraft,author,headRefName,headRefOid,baseRefName,body,"
              "additions,deletions,changedFiles,files,commits,statusCheckRollup,closingIssuesReferences,mergeable")
    pr = gh_json(["pr", "view", *([a.pr] if a.pr else []), "--repo", repo, "--json", fields])
    n, head, head_sha = pr["number"], pr["headRefName"], pr["headRefOid"]

    reviews = flat(gh_api_all(f"repos/{repo}/pulls/{n}/reviews"))
    issue_comments = flat(gh_api_all(f"repos/{repo}/issues/{n}/comments"))
    inline = flat(gh_api_all(f"repos/{repo}/pulls/{n}/comments"))

    print(f"# PR context: {repo}#{n}")
    print(f"- title: {pr['title']}")
    print(f"- url: {pr['url']}")
    print(f"- author: {pr['author']['login']} / state: {pr['state']}{' (draft)' if pr['isDraft'] else ''} / mergeable: {pr['mergeable']}")
    print(f"- head: {head} @ {head_sha[:8]} → base: {pr['baseRefName']}")
    print(f"- size: +{pr['additions']} -{pr['deletions']} / {pr['changedFiles']} files / {len(pr['commits'])} commits")
    if repo not in REPOS:
        print(f"- 注意: {repo} は対象3リポジトリ外")

    print("\n## PR本文")
    print("~~~~markdown\n" + (pr["body"] or "(なし)").strip() + "\n~~~~")
    for ci in pr.get("closingIssuesReferences") or []:
        try:
            x = gh_json(["issue", "view", str(ci["number"]), "--repo", repo, "--json", "title,body"])
            print(f"\n## closing issue #{ci['number']} {x['title']}\n~~~~markdown\n{(x['body'] or '').strip()[:4000]}\n~~~~")
        except RuntimeError:
            pass

    print("\n## 変更ファイル")
    for f in pr["files"]:
        print(f"- {f['path']} (+{f['additions']} -{f['deletions']})")

    # 作業場所: PR の worktree の有無と、そのブランチが PR head からどれだけ離れているか
    print("\n## 作業場所")
    if conf and os.path.isdir(conf["clone"]):
        clone = conf["clone"]
        if not a.no_fetch:
            fetch(clone, [head, pr["baseRefName"]])
        conflict = run(["git", "-C", clone, "merge-tree", "--write-tree", "--name-only",
                        f"origin/{pr['baseRefName']}", f"origin/{head}"], check=False)
        names = []
        for line in conflict.splitlines()[1:]:
            if not line.strip():
                break
            names.append(line)
        print(f"- {pr['baseRefName']} との衝突（merge-tree）: {'要解消: ' + ', '.join(names) if names else ('なし' if conflict else '判定不可')}")
        wt = find_worktree(clone, head)
        main_branch = git(clone, "branch", "--show-current", check=False).strip()
        print(f"- 本体clone: {clone} (現在ブランチ: {main_branch or 'detached'})")
        if clone.startswith("/mnt/d/tomcat/"):
            print("  - 注意: Tomcat が直接読む作業ツリー。checkout すると配信中の JSP が変わる")
        if wt:
            dirty = git(wt["path"], "status", "--porcelain", check=False).splitlines()
            print(f"- PRのworktree: {wt['path']}")
            print(f"  - local HEAD {wt['head'][:8]} / PR head {head_sha[:8]}"
                  f"{' (一致)' if wt['head'] == head_sha else ' (不一致: origin/' + head + ' を git show/diff で読む。worktree は書き換えない)'}")
            if wt["head"] != head_sha:
                cnt = git(clone, "rev-list", "--left-right", "--count", f"{wt['head']}...{head_sha}", check=False).strip()
                if cnt:
                    behind_local, ahead_remote = cnt.split()
                    print(f"  - local のみ {behind_local} commits / PR head のみ {ahead_remote} commits")
            print(f"  - 未コミット変更: {len(dirty)} 件" + (f" ({', '.join(l[3:] for l in dirty[:5])})" if dirty else ""))
        elif conf["wt_prefix"]:
            print(f"- PRのworktree: なし（命名規則なら {os.path.dirname(clone)}/{conf['wt_prefix']}{head.replace('/', '-')}）")
            print(f"  - 本体cloneで origin/{head} を git show/diff で読む")
        else:
            print("- worktree は作らない運用。checkout せず origin/<branch> を git show/diff で読む")
        others = [l[9:] for l in git(clone, "worktree", "list", "--porcelain", check=False).splitlines()
                  if l.startswith("worktree ") and "/scratchpad/" in l]
        if others:
            print(f"- 残っている scratchpad worktree: {len(others)} 本（他セッションが使用中のものも含む。片付けはユーザーに確認）")
            for o in others:
                print(f"  - {o}")
    else:
        print("- ローカルcloneが見つからない")

    print("\n## CI")
    checks = pr.get("statusCheckRollup") or []
    if not checks:
        print("- チェックなし")
    for c in checks:
        print(f"- {c.get('name') or c.get('context')}: {c.get('conclusion') or c.get('state') or c.get('status')}")

    if conf and conf["preview_workflow"]:
        print("\n## PRプレビュー")
        runs = gh_json(["run", "list", "--repo", repo, "--workflow", conf["preview_workflow"], "--branch", head,
                        "--limit", "3", "--json", "headSha,status,conclusion,createdAt,url"]) or []
        if not runs:
            print("- 実行なし")
        for c in issue_comments:
            if c["user"]["login"] in BOT_LOGINS and "Preview" in (c.get("body") or ""):
                m = re.search(r"\*\*ブランド\*\*\s*\|\s*([^|\n]+)", c["body"])
                if m:
                    print(f"- プレビューのブランド: {m.group(1).strip()}（変更対象のブランドと違えば、プレビューでは検証にならない）")
        for r in runs:
            mark = "最新head" if r["headSha"] == head_sha else "古いhead"
            print(f"- {r['createdAt']} {r['headSha'][:8]} ({mark}) {r['status']}/{r['conclusion'] or '-'} {r['url']}")


    # 関連 PR/issue: 本文・コメントに出てくる他リポジトリ/同リポジトリの参照と closing issue
    print("\n## 関連 PR / issue")
    refs = set()
    for t in [pr["body"] or ""] + [c.get("body") or "" for c in issue_comments + reviews]:
        refs.update((r, num) for r, _, num in XREF.findall(t))
        refs.update((ALIASES[name], num) for name, num in SHORT_XREF.findall(t))
        refs.update((PREFIX_REPO[k.lower()], num) for k, num in PREFIXED_XREF.findall(t))
    refs.discard((repo, str(n)))
    # 裸の #N はどのリポジトリか文脈次第なので、確定参照とは分けて出す（本文だけから拾う）
    body_wo = SHORT_XREF.sub("", PREFIXED_XREF.sub("", pr["body"] or ""))
    cross_nums = {num for _, num in refs}
    bare = sorted({num for num in BARE_XREF.findall(body_wo) if num not in cross_nums and num != str(n)}, key=int)
    closing = {str(ci["number"]) for ci in pr.get("closingIssuesReferences") or []}
    refs.update((repo, num) for num in closing)
    bare = [num for num in bare if num not in closing]

    def describe(r, num):
        x = gh_json(["api", f"repos/{r}/issues/{num}"])
        if "pull_request" in x:
            merged = (x["pull_request"] or {}).get("merged_at")
            return f"PR [{x['state']}{' merged ' + merged if merged else ''}] {x['title']}"
        return f"issue [{x['state']}] {x['title']}"

    if not refs and not bare:
        print("- なし")
    for r, num in sorted(refs, key=lambda x: (x[0] != repo, x[0], int(x[1]))):
        try:
            print(f"- {r}#{num} {describe(r, num)}")
        except RuntimeError:
            print(f"- {r}#{num} 取得失敗")
    # 逆参照: 相手側 PR の本文だけがこの PR を指している場合（例: chat の PR が MCP の PR を前提にする）
    try:
        back = gh_json(["search", "prs", "--owner", repo.split("/")[0], f"{repo}/pull/{n}",
                        "--json", "repository,number,title,state", "--limit", "10"]) or []
    except RuntimeError:
        back = []
    for b in back:
        key = (b["repository"]["nameWithOwner"], str(b["number"]))
        if key not in refs and key != (repo, str(n)):
            print(f"- {key[0]}#{key[1]} PR [{b['state']}] {b['title']}（この PR を参照している側）")
    if bare:
        print(f"- 本文中の裸の #N（{repo} と仮定。他リポジトリの略記のことがあるので文脈で確認）:")
        for num in bare:
            try:
                print(f"  - #{num} {describe(repo, num)}")
            except RuntimeError:
                print(f"  - #{num} {repo} に無し（他リポジトリの番号の可能性）")

    # 時系列: コミット・レビュー・コメントを1本に並べ、指摘とその後のコミットの対応を追えるようにする
    events = []
    for c in pr["commits"]:
        events.append((c["committedDate"], "commit", f"{c['oid'][:8]} {c['messageHeadline']}"))
    for r in reviews:
        if r.get("submitted_at"):
            events.append((r["submitted_at"], f"review:{r['state']}", f"@{r['user']['login']} [{(r.get('commit_id') or '')[:8]}] {snip(r.get('body'))}"))
    for c in issue_comments:
        events.append((c["created_at"], "comment", f"@{c['user']['login']} {snip(c.get('body'))}"))
    for c in inline:
        events.append((c["created_at"], "inline", f"@{c['user']['login']} {c.get('path')}:{c.get('line') or c.get('original_line')} {snip(c.get('body'))}"))
    events.sort(key=lambda e: ts(e[0]))
    print("\n## 時系列（commit / review / comment）")
    for t, kind, text in events:
        print(f"- {t[:16]} {kind}: {text}")

    # 再レビュー用: 自分の最後のレビュー以降に何が積まれたか
    mine = [r for r in reviews if r["user"]["login"] in MY_LOGINS and r.get("submitted_at")]
    my_comments = [c for c in issue_comments + inline if c["user"]["login"] in MY_LOGINS]
    print("\n## 再レビュー情報")
    if not mine and not my_comments:
        print("- 自分のレビュー/コメントなし（初回レビュー）")
        print_others(issue_comments + inline + reviews, None, "他者のレビュー・コメント（全文。claude[bot] の指摘と作者の対応を含む）")
        return
    last = max([ts(r["submitted_at"]) for r in mine] + [ts(c["created_at"]) for c in my_comments])
    # 基準点は「最後に変更を求めたレビュー」。その後に軽い COMMENTED があっても修正コミットが隠れないようにする
    cr = [r for r in mine if r["state"] == "CHANGES_REQUESTED"]
    approved_after = cr and any(r["state"] == "APPROVED" and ts(r["submitted_at"]) > ts(cr[-1]["submitted_at"]) for r in mine)
    if cr and not approved_after:
        anchor_review = max(cr, key=lambda r: ts(r["submitted_at"]))
        anchor_kind = "最後の CHANGES_REQUESTED"
    elif mine:
        anchor_review = max(mine, key=lambda r: ts(r["submitted_at"]))
        anchor_kind = f"最後のレビュー({anchor_review['state']})"
    else:
        anchor_review = None
        anchor_kind = "最後のコメント"
    anchor = ts(anchor_review["submitted_at"]) if anchor_review else last
    base_sha = anchor_review.get("commit_id") if anchor_review else None
    if not base_sha:
        before = [c for c in pr["commits"] if ts(c["committedDate"]) <= anchor]
        base_sha = before[-1]["oid"] if before else None
    print(f"- 基準: {anchor_kind} {anchor.isoformat()[:16]} @ {(base_sha or '?')[:8]}")
    if last > anchor:
        print(f"- 自分の最終活動はそれより後: {last.isoformat()[:16]}（基準より後の自分の発言も下の全文に含む）")
    oids = [c["oid"] for c in pr["commits"]]
    # レビュー時の head が分かればコミット順で切る（committedDate はリベース等でレビュー時刻と前後する）
    if base_sha in oids:
        after = pr["commits"][oids.index(base_sha) + 1:]
    else:
        after = [c for c in pr["commits"] if ts(c["committedDate"]) > anchor]
    print(f"- 基準以降のコミット: {len(after)} 件")
    for c in after:
        merge = len(c.get("parents") or []) > 1 or c["messageHeadline"].startswith("Merge ")
        print(f"  - {c['oid'][:8]} {c['committedDate'][:16]} {'[main取り込み] ' if merge else ''}{c['messageHeadline']}")
    fixes = [c for c in after if not (len(c.get("parents") or []) > 1 or c["messageHeadline"].startswith("Merge "))]
    if conf and fixes and os.path.isdir(conf["clone"]):
        # main 取り込みを含む範囲 diff は main 側の変更で膨らむため、修正コミット単位で見る
        print("- 修正コミットの変更ファイル（main取り込みは除外）:")
        for c in fixes:
            stat = git(conf["clone"], "show", "--stat", "--format=", c["oid"], check=False).strip()
            print(f"  - {c['oid'][:8]}: git -C {conf['clone']} show {c['oid'][:8]}")
            for line in stat.splitlines():
                print(f"    {line}")
    elif after and not fixes:
        print("- 修正コミットなし（main取り込みのみ）")
    print("\n### 自分の過去の指摘（全文）")
    for r in sorted(mine, key=lambda r: ts(r["submitted_at"])):
        if (r.get("body") or "").strip():
            print(f"\n#### review {r['state']} {r['submitted_at'][:16]} @ {(r.get('commit_id') or '')[:8]}\n~~~~markdown\n{r['body'].strip()}\n~~~~")
    for c in sorted(my_comments, key=lambda c: ts(c["created_at"])):
        loc = f" {c['path']}:{c.get('line') or c.get('original_line')}" if c.get("path") else ""
        print(f"\n#### comment {c['created_at'][:16]}{loc}\n~~~~markdown\n{(c.get('body') or '').strip()}\n~~~~")
    print_others(issue_comments + inline + reviews, anchor, "基準以降の他者の発言（全文。作者の返信・相談・claude[bot] を含む）")

if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        print("gh が認証エラーなら `gh auth switch` でアカウントを切り替える", file=sys.stderr)
        sys.exit(1)
