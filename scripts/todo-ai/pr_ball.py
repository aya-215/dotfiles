#!/usr/bin/env python3
"""自分の PR のボール（mine/theirs/done/unknown）を決める。判定は決定的で AI を使わない。"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync_github

DEFAULT_ME = {"eBASE-Mori", "森彪人", "mori.a"}
STATES = ("open", "closed", "merged")


def get_me(env=os.environ) -> "set[str]":
    raw = env.get("TODO_ME")
    if raw:
        names = {s.strip() for s in raw.split(",") if s.strip()}
        if names:
            return names
    return set(DEFAULT_ME)


def _ts(s):
    try:
        t = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None
    return t if t.tzinfo else None  # naive と aware の比較で TypeError になるため拒否


def validate(pr) -> "str | None":
    """不正なら理由、正しければ None。"""
    if not isinstance(pr, dict):
        return "pr が object ではありません"
    if pr.get("state") not in STATES:
        return "state が open/closed/merged ではありません"
    if not isinstance(pr.get("author"), str) or not pr["author"]:
        return "author がありません"
    rv = pr.get("reviewers")
    if not isinstance(rv, list) or not all(isinstance(x, str) for x in rv):
        return "reviewers が文字列の配列ではありません"
    evs = pr.get("events")
    if not isinstance(evs, list):
        return "events が配列ではありません"
    for e in evs:
        if not isinstance(e, dict) or not isinstance(e.get("user"), str) or _ts(e.get("ts")) is None:
            return "events の要素が不正です"
        if e.get("kind") not in ("comment", "review"):
            return "events の kind が不正です"
    return None


def decide(pr: dict, me: "set[str]") -> dict:
    if pr["state"] in ("closed", "merged"):
        return {"ball": "done", "reason": "クローズ済み" if pr["state"] == "closed" else "マージ済み"}
    if pr["author"] not in me:
        return {"ball": "unknown", "reason": "自分の PR ではありません"}
    if not pr["reviewers"]:
        return {"ball": "mine", "reason": "レビュアー未設定"}
    if all(e["user"] in me for e in pr["events"]):
        return {"ball": "theirs", "reason": "反応待ち"}
    newest = max(_ts(e["ts"]) for e in pr["events"])
    tied = [e for e in pr["events"] if _ts(e["ts"]) == newest]
    # 同時刻に相手が混じるなら保守側（自分ボール）
    other = next((e for e in tied if e["user"] not in me), None)
    if other is None:
        return {"ball": "theirs", "reason": "自分が最後に発言"}
    return {"ball": "mine", "reason": f"{other['user']} が最後に発言"}


class FetchError(Exception):
    pass


def gh_json(path: str, token: str, paginate: bool = False):
    cmd = ["gh", "api"] + (["--paginate", "--slurp"] if paginate else []) + [path]
    env = {**os.environ, "GH_TOKEN": token}
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FetchError(f"{path}: {e}")
    if r.returncode != 0:
        raise FetchError(f"{path}: gh api 失敗: {r.stderr.strip()[:200]}")
    try:
        data = json.loads(r.stdout)
    except ValueError as e:
        raise FetchError(f"{path}: {e}")
    if paginate:
        if not isinstance(data, list):
            raise FetchError(f"{path}: 配列ではありません")
        data = [x for page in data for x in (page if isinstance(page, list) else [page])]
    return data


def _login(obj):
    u = obj.get("user") if isinstance(obj, dict) else None
    return u.get("login") if isinstance(u, dict) and isinstance(u.get("login"), str) else None


def _is_bot(u) -> bool:
    return isinstance(u, dict) and (u.get("type") == "Bot" or str(u.get("login", "")).endswith("[bot]"))


def fetch_pr(repo: str, number: int, token: str) -> dict:
    base = f"repos/{sync_github.ORG}/{repo}"
    p = gh_json(f"{base}/pulls/{number}", token)
    reviews = gh_json(f"{base}/pulls/{number}/reviews", token, True)
    issue_comments = gh_json(f"{base}/issues/{number}/comments", token, True)
    review_comments = gh_json(f"{base}/pulls/{number}/comments", token, True)
    if not isinstance(p, dict):
        raise FetchError("pulls 応答が object ではありません")
    author = _login(p)
    st = p.get("state")
    if st == "closed":
        state = "merged" if p.get("merged") else "closed"
    elif st == "open":
        state = "open"
    else:
        raise FetchError(f"状態を解釈できません: {st!r}")
    reviewers = [x.get("login") for x in p.get("requested_reviewers") or [] if isinstance(x, dict) and not _is_bot(x)]
    reviewers += [f"team:{t['slug']}" for t in p.get("requested_teams") or [] if isinstance(t, dict) and t.get("slug")]
    events = []
    for rv in reviews:
        if not isinstance(rv, dict) or not rv.get("submitted_at"):
            continue
        u = _login(rv) or "ghost"
        events.append({"user": u, "ts": rv["submitted_at"], "kind": "review", "state": rv.get("state")})
        if u != "ghost" and not _is_bot(rv.get("user")):
            reviewers.append(u)
    for c in list(issue_comments) + list(review_comments):
        if isinstance(c, dict) and c.get("created_at"):
            events.append({"user": _login(c) or "ghost", "ts": c["created_at"], "kind": "comment", "state": None})
    reviewers = list(dict.fromkeys(r for r in reviewers if isinstance(r, str) and r != author))
    return {"state": state, "author": author or "", "reviewers": reviewers, "events": events}


def unknown(ref, reason: str) -> dict:
    print(f"warn: {reason}", file=sys.stderr)
    return {"ref": ref, "ball": "unknown", "reason": reason}


def run_github(ref: str, me: "set[str]") -> dict:
    abbr, sep, num = ref.partition("#")
    repo = sync_github.REPOS.get(abbr)
    if not sep or repo is None or not num.isdigit():
        return unknown(ref, f"解釈できない参照: {ref}")
    sync_github.ensure_gh_path()
    token = get_token()
    if not token:
        return unknown(ref, f"gh auth token --user {sync_github.ACCOUNT} に失敗")
    try:
        pr = fetch_pr(repo, int(num), token)
        err = validate(pr)
        if err:
            return unknown(ref, f"取得結果が不正: {err}")
        return {"ref": ref, **decide(pr, me)}
    except FetchError as e:
        return unknown(ref, f"取得失敗: {e}")
    except Exception as e:  # 想定外の応答でも JSON を出して落ちない
        return unknown(ref, f"想定外のエラー: {type(e).__name__}: {e}")


def run_json(text: str, me: "set[str]") -> dict:
    try:
        pr = json.loads(text)
    except ValueError as e:
        return unknown(None, f"JSON を読めません: {e}")
    err = validate(pr)
    if err:
        return unknown(None, f"入力が不正: {err}")
    return {"ref": None, **decide(pr, me)}


get_token = sync_github.get_token


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--from-json", action="store_true")
    g.add_argument("github", nargs="?", choices=["github"])
    p.add_argument("ref", nargs="?")
    a = p.parse_args(argv)
    me = get_me()
    if a.from_json:
        res = run_json(sys.stdin.read(), me)
    elif a.ref:
        res = run_github(a.ref, me)
    else:
        p.error("github には <repo略称>#<n> が必要です")
    print(json.dumps(res, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
