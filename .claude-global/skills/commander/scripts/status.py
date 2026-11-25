#!/usr/bin/env python3
"""「現在の状況をまとめて」の材料（tmux・GitHub・引き継ぎメモの変化・到達性・git）を1回で JSON に出す。"""
import argparse
import json
import os
import re
import socket
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import carry  # noqa: E402
import check_waits  # noqa: E402
import collect  # noqa: E402
import sessions as tmux_sessions  # noqa: E402
from refs import refs_in_text  # noqa: E402
from check_waits import pr_ball, sync_github  # noqa: E402

JST = timezone(timedelta(hours=9))
PORTS = (22, 80, 445, 3389)
PROBE_TIMEOUT = 2
_LAST = re.compile(r"^最終確認:\s*(.+?)\s*$", re.M)
_WAIT = re.compile(r"^## 待っているもの\s*\n(.*?)(?=^## |\Z)", re.S | re.M)
_IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
_HEADING = re.compile(r"^## (.+?)\s*$", re.M)
# /handoff の雛形の節。これより後ろに書き足された見出しだけが進み具合を表す
_BOILERPLATE = {"待っているもの", "今の状態", "決めたことと理由", "次にやること", "関連", "元のセッション"}
GH_WORKERS = 6
_RC_ROOM = re.compile(r"team\.ebase-jp\.com/(direct|group|channel)/([^?#\s)\]]+)")


def _front(text: str, key: str) -> str:
    m = re.search(rf"^{key}:\s*\"?(.*?)\"?\s*$", text, re.M)
    return m.group(1) if m else ""


def read_last_check(text: "str | None", today: date, warnings: "list[str]") -> datetime:
    midnight = datetime.combine(today, time(0), JST)
    m = _LAST.search(text or "")
    if not m:
        return midnight
    try:
        dt = datetime.fromisoformat(m.group(1))
    except ValueError:
        warnings.append(f"最終確認の行を読めないので 0 時から見る: {m.group(1)}")
        return midnight
    return dt if dt.tzinfo else dt.replace(tzinfo=JST)


def changed_handoffs(memo_dir: Path, since: datetime, warnings: "list[str]") -> "list[dict]":
    out = []
    for p in sorted(memo_dir.glob("handoff-*.md")):
        try:
            if p.stat().st_mtime <= since.timestamp():
                continue
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as e:
            warnings.append(f"引き継ぎメモを読めない: {p.name}: {e}")
            continue
        headings = [h for h in _HEADING.findall(text) if h not in _BOILERPLATE]
        out.append({"path": str(p), "status": _front(text, "status"), "summary": _front(text, "summary"),
                    "last_heading": headings[-1] if headings else ""})
    return out


def wait_ips(memo_text: str) -> "list[str]":
    m = _WAIT.search(memo_text)
    return list(dict.fromkeys(_IPV4.findall(m.group(1)))) if m else []


def probe(ip: str, connect) -> "list[int]":
    return [port for port in PORTS if connect(ip, port, PROBE_TIMEOUT)]


def closed_sessions(commander_text: "str | None", live: "list[str] | None") -> "list[str]":
    if commander_text is None or live is None:
        return []
    _, info = carry.prune(carry.extract(commander_text), live, None)
    return info["removed_tmux"]


def rc_rooms(texts: "list[str | None]") -> "list[dict]":
    seen: "dict[tuple[str, str], dict]" = {}
    for text in texts:
        for kind, room in _RC_ROOM.findall(text or ""):
            seen.setdefault((kind, unquote(room)), {"kind": kind, "room": unquote(room)})
    return list(seen.values())


_RC_MSG = re.compile(r"^  (\d\d):(\d\d) ([^\s:]+)(.*)$")
_RC_PARENT = re.compile(r"\[↳(\d\d):(\d\d) ([^\]]+)\]")
_RC_DROPPED = "（※ 容量制限"


def _jst_hm(h: str, m: str) -> str:
    return f"{(int(h) + 9) % 24:02d}:{m}"


def rc_digest(text: str, last_check: datetime, today: date, me: str) -> str:
    """rocketchat.sh の出力（時刻は UTC）を JST に直し、last_check 以降に発言があるルームだけ残す。

    発言者や返信先（↳）が自分（me）なら「自分(me)」と書き換える。容量制限で省いたルームの行は末尾に残す。
    """
    # 時刻しか出ないので、前日以前からの確認では時刻で絞れない
    same_day = last_check.astimezone(JST).date() == today
    since = last_check.astimezone(JST).strftime("%H:%M")
    out: "list[str]" = []
    notes: "list[str]" = []
    head: "str | None" = None
    kept: "list[str]" = []

    def mark(user: str) -> str:
        return f"自分({me})" if user == me else user

    def flush():
        if head is not None and kept:
            out.extend([head] + kept)

    for line in text.splitlines():
        if line.startswith("===== "):
            flush()
            head, kept = line, []
            continue
        if line.startswith(_RC_DROPPED):
            notes.append(line)
            continue
        m = _RC_MSG.match(line)
        if not m:
            if head is None and line.strip():
                out.append(line)
            continue
        hm = _jst_hm(m.group(1), m.group(2))
        if same_day and hm < since:
            continue
        rest = _RC_PARENT.sub(lambda p: f"[↳{_jst_hm(p.group(1), p.group(2))} {mark(p.group(3))}]", m.group(4))
        kept.append(f"  {hm} {mark(m.group(3))}{rest}")
    flush()
    if len(out) == 1 and out[0].startswith("（表示名"):
        out = []
    return "\n".join(out + notes)


def _ts(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def _github_ref(ref: str) -> "tuple[str, int] | None":
    abbr, sep, num = ref.partition("#")
    if sep and abbr in sync_github.REPOS and num.isdigit():
        return sync_github.REPOS[abbr], int(num)
    return None


def github_facts(ref: str, fetch_pr, fetch_extra, me: "set[str]", last_check: datetime,
                 since: "datetime | None") -> dict:
    out = {"ref": ref, "state": None, "reviews": {}, "last_commit": None, "checks": None,
           "activity": [], "returned": None, "error": None}
    repo, num = _github_ref(ref)
    try:
        pr = fetch_pr(repo, num)
        extra = {"last_commit": None, "checks": None, "closed_at": pr.get("closed_at")}
        if not pr.get("is_issue"):
            extra = fetch_extra(repo, num)
    except Exception as e:  # 1件の失敗で残りを止めない
        out["error"] = str(e)
        return out
    events = sorted((e for e in pr.get("events", []) if not e["user"].endswith("[bot]")), key=lambda e: e["ts"])
    for e in events:
        # Approve 後のインライン返信も COMMENTED のレビューになるので、それで Approve を消さない
        if e.get("kind") == "review" and e.get("state") and e["user"] not in me and (
                e["state"] != "COMMENTED" or e["user"] not in out["reviews"]):
            out["reviews"][e["user"]] = e["state"]
    out.update({"state": pr["state"], "last_commit": extra["last_commit"], "checks": extra["checks"],
                "activity": [e for e in events if e["user"] not in me and _ts(e["ts"]) > last_check]})
    if since is not None:
        out["returned"] = check_waits.returned(pr["state"], events, me, since, extra.get("closed_at"))["returned"]
    return out


def build(collected: dict, commander_text: "str | None", sessions: "list[dict] | None", memo_dir: Path,
          facts, memo_text, connect, now: datetime) -> dict:
    warnings = list(collected.get("warnings", []))
    last_check = read_last_check(commander_text, date.fromisoformat(collected["today"]), warnings)
    since_of: "dict[str, str | None]" = {}
    order: "list[str]" = []
    memo_refs = [x for h in collected["handoffs"] for x in h["refs"]]
    for ref in [r["ref"] for r in collected["todo"]] + memo_refs + sorted(refs_in_text(commander_text or "")):
        if ref not in order:
            order.append(ref)
    for h in collected["handoffs"]:
        for ref in h["wait_refs"]:
            since_of.setdefault(ref, h.get("since"))
    gh_refs = [ref for ref in order if _github_ref(ref)]
    with ThreadPoolExecutor(GH_WORKERS) as ex:
        github = list(ex.map(lambda ref: facts(ref, since_of.get(ref), last_check), gh_refs))
    for g in github:
        if g.get("error"):
            warnings.append(f"{g['ref']}: 取得失敗: {g['error']}")
    reach = []
    memo_texts = {h["path"]: memo_text(h["path"]) for h in collected["handoffs"]}
    rooms = rc_rooms([r.get("url") for r in collected["todo"]] + list(memo_texts.values()) + [commander_text])
    for h in collected["handoffs"]:
        for ip in wait_ips(memo_texts[h["path"]]):
            reach.append({"ip": ip, "open": probe(ip, connect), "memo": h["path"]})
    live = None if sessions is None else [s["name"] for s in sessions]
    return {"now": now.isoformat(), "last_check": last_check.isoformat(), "sessions": sessions,
            "closed_sessions": closed_sessions(commander_text, live),
            "handoffs_changed": changed_handoffs(memo_dir, last_check, warnings), "github": github,
            "gitbucket_refs": [r for r in order if r.startswith("gb:")], "reachability": reach,
            "rocketchat_rooms": rooms, "warnings": warnings}


_PASS = {"success", "skipped", "neutral"}


def _fetch_pr(repo: str, number: int, token: str) -> dict:
    try:
        return pr_ball.fetch_pr(repo, number, token)
    except pr_ball.FetchError as e:
        if "(HTTP 404)" not in str(e):
            raise
    state, events, closed_at = check_waits.fetch(repo, number, token)
    return {"state": state, "events": events, "closed_at": closed_at, "is_issue": True}


def _fetch_extra(repo: str, number: int, token: str) -> dict:
    base = f"repos/{sync_github.ORG}/{repo}"
    p = pr_ball.gh_json(f"{base}/pulls/{number}", token)
    sha = p["head"]["sha"]
    commit = pr_ball.gh_json(f"{base}/commits/{sha}", token)
    runs = pr_ball.gh_json(f"{base}/commits/{sha}/check-runs", token).get("check_runs", [])
    checks = {"pass": 0, "fail": 0, "pending": 0}
    for r in runs:
        c = r.get("conclusion")
        checks["pending" if c is None else "pass" if c in _PASS else "fail"] += 1
    return {"last_commit": commit["commit"]["committer"]["date"], "checks": checks,
            "closed_at": p.get("merged_at") or p.get("closed_at")}


def _connect(ip: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def _read(path: "str | None") -> "str | None":
    try:
        return Path(path).read_text(encoding="utf-8") if path else None
    except (OSError, UnicodeDecodeError):
        return None


LIB = Path.home() / ".dotfiles/scripts/lib"
RC_ME = "mori.a"


def _run_lib(script: str, args: "list[str]") -> "tuple[str, str | None]":
    try:
        r = subprocess.run(["bash", str(LIB / script), *args], capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.SubprocessError) as e:
        return "", f"{script}: {e}"
    if r.returncode != 0:
        return "", f"{script}: 終了コード {r.returncode}: {r.stderr.strip()[:200]}"
    return r.stdout, None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--todo", type=Path, default=Path.home() / "memo/todo.md")
    ap.add_argument("--commander-dir", type=Path, default=Path.home() / "memo/commander")
    ap.add_argument("--memo-dir", type=Path,
                    default=Path.home() / ".claude/skills/agent-memory/memories/work-in-progress")
    a = ap.parse_args(argv)
    now = datetime.now(JST)
    pre: "list[str]" = []
    hits = collect._find_handoffs(pre)
    collected = collect.collect(a.todo, hits, a.commander_dir, now.date(), collect._tmux_sessions())
    collected["warnings"] = pre + collected["warnings"]
    files = collected["files"]
    commander_text = _read(files["today"]) if files["today_exists"] else _read(files["previous"])
    since_day = read_last_check(commander_text, now.date(), []).date().isoformat()
    span = ["--from", since_day, "--to", now.date().isoformat()]
    pool = ThreadPoolExecutor(2)
    mail_job = pool.submit(_run_lib, "thunderbird.sh", span + ["--no-body", "--budget", "4000"])
    rc_job = pool.submit(_run_lib, "rocketchat.sh", span + ["--include-dm", "--with-ids", "--budget", "12000"])
    sync_github.ensure_gh_path()
    token, me = sync_github.get_token(), pr_ball.get_me()

    def facts(ref: str, since: "str | None", last_check: datetime) -> dict:
        if not token:
            return {"ref": ref, "state": None, "error": "gh のトークンを取れない"}
        return github_facts(ref, lambda r, n: _fetch_pr(r, n, token), lambda r, n: _fetch_extra(r, n, token),
                            me, last_check, datetime.fromisoformat(since) if since else None)

    out = build(collected, commander_text, tmux_sessions.list_sessions(tmux_sessions.run_cmd, os.environ.get("TMUX_PANE"), now),
                a.memo_dir, facts, lambda p: _read(p) or "", _connect, now)
    mail, mail_err = mail_job.result()
    rc, rc_err = rc_job.result()
    pool.shutdown()
    out["warnings"] += [e for e in (mail_err, rc_err) if e]
    out["mail"] = mail.strip()
    out["rocketchat"] = rc_digest(rc, datetime.fromisoformat(out["last_check"]), now.date(), RC_ME)
    for w in out["warnings"]:
        print(f"warn: {w}", file=sys.stderr)
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
