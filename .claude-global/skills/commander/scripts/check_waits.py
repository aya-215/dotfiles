#!/usr/bin/env python3
"""GitHub の PR・issue で、待ちに入った後に相手の動きがあったか（返ってきたか）を判定する。"""
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".dotfiles/scripts/todo-ai"))
import pr_ball  # noqa: E402
import sync_github  # noqa: E402


def _ts(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def returned(state: str, events: "list[dict]", me: "set[str]", since: datetime) -> dict:
    if state in ("merged", "closed"):
        return {"returned": True, "reason": "マージ済み" if state == "merged" else "クローズ済み", "events": []}
    theirs = sorted((e for e in events if e["user"] not in me and _ts(e["ts"]) > since), key=lambda e: e["ts"])
    if theirs:
        last = theirs[-1]
        return {"returned": True, "reason": f"{last['user']} が {last['ts']} に発言", "events": theirs}
    return {"returned": False, "reason": "待ちに入った後の相手の動きなし", "events": []}


def _events(items, kind: str, ts_key: str) -> "list[dict]":
    out = []
    for x in items:
        if isinstance(x, dict) and x.get(ts_key) and not pr_ball._is_bot(x.get("user")):
            out.append({"user": pr_ball._login(x) or "ghost", "ts": x[ts_key], "kind": kind})
    return out


def fetch(repo: str, number: int, token: str) -> "tuple[str, list[dict]]":
    base = f"repos/{sync_github.ORG}/{repo}"
    try:
        p = pr_ball.gh_json(f"{base}/pulls/{number}", token)
    except pr_ball.FetchError as e:
        if "404" not in str(e):
            raise
        issue = pr_ball.gh_json(f"{base}/issues/{number}", token)
        comments = pr_ball.gh_json(f"{base}/issues/{number}/comments", token, True)
        return issue.get("state", "open"), _events(comments, "comment", "created_at")
    state = "merged" if p.get("merged") else p.get("state", "open")
    events = _events(pr_ball.gh_json(f"{base}/pulls/{number}/reviews", token, True), "review", "submitted_at")
    events += _events(pr_ball.gh_json(f"{base}/issues/{number}/comments", token, True), "comment", "created_at")
    events += _events(pr_ball.gh_json(f"{base}/pulls/{number}/comments", token, True), "comment", "created_at")
    return state, events


def check(items: "list[dict]", me: "set[str]", fetch_fn, token: "str | None") -> "list[dict]":
    out = []
    for it in items:
        ref = it["ref"]
        abbr, sep, num = ref.partition("#")
        if ref.startswith("gb:"):
            out.append({"ref": ref, "kind": "gitbucket", "returned": None, "reason": "GitBucket は MCP で確かめる", "events": []})
            continue
        if not (sep and abbr in sync_github.REPOS and num.isdigit()):
            out.append({"ref": ref, "kind": "other", "returned": None, "reason": "自動では確かめられない", "events": []})
            continue
        if not token:
            out.append({"ref": ref, "kind": "github", "returned": None, "reason": "gh のトークンを取れない", "events": []})
            continue
        try:
            state, events = fetch_fn(sync_github.REPOS[abbr], int(num), token)
            out.append({"ref": ref, "kind": "github", **returned(state, events, me, datetime.fromisoformat(it["since"]))})
        except Exception as e:  # 1件の失敗で残りの判定を止めない
            out.append({"ref": ref, "kind": "github", "returned": None, "reason": f"取得失敗: {e}", "events": []})
    return out


def main(argv=None) -> int:
    try:
        items = json.loads(sys.stdin.read())
    except ValueError as e:
        print(f"warn: 入力の JSON を読めません: {e}", file=sys.stderr)
        print("[]")
        return 0
    sync_github.ensure_gh_path()
    res = check(items, pr_ball.get_me(), fetch, sync_github.get_token())
    for r in res:
        if r["returned"] is None and r["kind"] == "github":
            print(f"warn: {r['ref']}: {r['reason']}", file=sys.stderr)
    print(json.dumps(res, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
