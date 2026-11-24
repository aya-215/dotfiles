#!/usr/bin/env python3
"""tmux の各セッションで Claude が作業中か返事待ちかと、その作業場所の git の状態を JSON で出す。"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

JST = timezone(timedelta(hours=9))
PANE_FORMAT = "#{pane_id}\t#{pane_current_command}\t#{pane_current_path}"
_DONE = re.compile(r"done (\d{1,2}):(\d{2})")
_AHEAD = re.compile(r"\[ahead (\d+)")
# Claude Code の入力欄・ステータス行（tmux-agent-sidebar 等の装飾を含む）は状態の要約に要らない
_NOISE = re.compile(r"^─|^❯\s*$|auto mode|cache|󰉋|^5h |^[│┃\s]+$")


def pick_claude_pane(panes: str) -> "dict | None":
    for line in panes.splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and parts[1] == "claude":
            return {"pane": parts[0], "cwd": parts[2]}
    return None


def pane_state(capture: str, now: datetime) -> dict:
    lines = capture.rstrip("\n").splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    working = any("esc to interrupt" in line for line in lines[-8:])
    tail = [s for s in (line.strip() for line in lines) if s and not _NOISE.search(s)][-6:]
    done = [(h, m) for h, m in _DONE.findall(capture) if int(h) < 24 and int(m) < 60]
    since = minutes = None
    if done and not working:
        h, m = (int(x) for x in done[-1])
        at = now.replace(hour=h, minute=m, second=0, microsecond=0)
        if at > now:
            at -= timedelta(days=1)
        since, minutes = f"{h:02d}:{m:02d}", int((now - at).total_seconds() // 60)
    return {"state": "working" if working else "idle", "idle_since": since, "idle_minutes": minutes, "tail": tail}


def git_state(porcelain: "str | None") -> "dict | None":
    if porcelain is None:
        return None
    lines = porcelain.splitlines()
    head = lines[0][3:] if lines and lines[0].startswith("## ") else ""
    ahead = _AHEAD.search(head)
    # upstream が無いブランチは未 push かどうか分からないので 0 と区別する
    return {"branch": head.split("...")[0].split(" ")[0], "dirty": len([x for x in lines[1:] if x.strip()]),
            "ahead": None if "..." not in head else int(ahead.group(1)) if ahead else 0}


def list_sessions(run, self_pane: "str | None", now: datetime) -> "list[dict] | None":
    names = run(["tmux", "list-sessions", "-F", "#S"])
    if names is None:
        return None
    out = []
    for name in (n for n in names.splitlines() if n):
        row = {"name": name, "pane": None, "cwd": None, "self": False, "state": "no_claude",
               "idle_since": None, "idle_minutes": None, "tail": [], "git": None}
        pane = pick_claude_pane(run(["tmux", "list-panes", "-s", "-t", name, "-F", PANE_FORMAT]) or "")
        if pane:
            row.update(pane)
            if pane["pane"] == self_pane:
                row.update({"self": True, "state": "self"})
            else:
                row.update(pane_state(run(["tmux", "capture-pane", "-p", "-t", pane["pane"], "-S", "-40"]) or "", now))
                row["git"] = git_state(run(["git", "--no-optional-locks", "-C", pane["cwd"], "status", "--porcelain=v1", "--branch"]))
        out.append(row)
    return out


def run_cmd(argv: "list[str]") -> "str | None":
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=15, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return None


def main() -> int:
    print(json.dumps(list_sessions(run_cmd, os.environ.get("TMUX_PANE"), datetime.now(JST)), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
