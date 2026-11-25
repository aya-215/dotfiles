#!/usr/bin/env python3
"""tmux セッションを立てて claude を起動し、入力欄が出てから最初のプロンプトを送る。

プロンプトを claude の引数に渡さないのは、シェルの履歴に残さないため。
結果は JSON で出す。`status`: sent（送った）／trust（フォルダの信頼確認で止まっている。送っていない）／
timeout（入力欄が出なかった。送っていない）／exists（同名のセッションがある。何もしていない）。
"""
import argparse
import json
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sessions import pick_claude_pane, run_cmd  # noqa: E402

PANE_FORMAT = "#{pane_id}\t#{pane_current_command}\t#{pane_current_path}"
_BAD_NAME = re.compile(r"[.:\s]")
_TRUST = re.compile(r"trust this folder|Accessing workspace")


def validate(name: str, prompt: str) -> "str | None":
    if not name or _BAD_NAME.search(name):
        return "セッション名に . : 空白は使えない"
    if "\n" in prompt or "\r" in prompt:
        # send-keys で改行を送るとその場で送信されてしまう
        return "プロンプトに改行は入れられない"
    return None


def claude_command(worktree: "str | None") -> str:
    return "claude" if worktree is None else f"claude -w {shlex.quote(worktree)}"


def screen_state(capture: str) -> str:
    """ready（入力欄が出た）／trust（信頼確認）／starting を返す。"""
    lines = capture.splitlines()
    if any(_TRUST.search(line) for line in lines):
        return "trust"
    # 信頼確認の選択肢やシェルのプロンプトも ❯ で始まるので、罫線の直下にある ❯ だけを入力欄とみなす
    for prev, line in zip(lines, lines[1:]):
        if prev.startswith("─") and line.startswith("❯"):
            return "ready"
    return "starting"


def wait_ready(run, name: str, timeout: float, interval: float = 0.5, sleep=time.sleep, clock=time.monotonic):
    start = clock()
    pane, state = None, "starting"
    while clock() - start < timeout:
        pane = pick_claude_pane(run(["tmux", "list-panes", "-s", "-t", name, "-F", PANE_FORMAT]) or "")
        if pane:
            state = screen_state(run(["tmux", "capture-pane", "-p", "-t", pane["pane"]]) or "")
            if state != "starting":
                return state, pane, round(clock() - start, 1)
        sleep(interval)
    return "timeout", pane, round(clock() - start, 1)


def tmux(*args: str) -> None:
    subprocess.run(["tmux", *args], check=True, timeout=15)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--name", required=True, help="セッション名（場所-課題番号）")
    ap.add_argument("--dir", required=True, help="起動する場所")
    ap.add_argument("--prompt", required=True, help="最初に送るプロンプト（1行）")
    ap.add_argument("--worktree", help="claude -w に渡すブランチ名・'#<PR番号>'")
    ap.add_argument("--timeout", type=float, default=60.0, help="入力欄を待つ秒数")
    a = ap.parse_args()

    err = validate(a.name, a.prompt)
    if err:
        print(f"error: {err}", file=sys.stderr)
        return 2
    result = {"name": a.name, "status": None, "ready_seconds": None, "pane": None, "tail": []}
    if subprocess.run(["tmux", "has-session", "-t", f"={a.name}"], capture_output=True).returncode == 0:
        result["status"] = "exists"
        print(json.dumps(result, ensure_ascii=False, indent=1))
        return 1

    tmux("new-session", "-d", "-s", a.name, "-c", a.dir)
    tmux("send-keys", "-t", a.name, "-l", claude_command(a.worktree))
    tmux("send-keys", "-t", a.name, "Enter")
    state, pane, secs = wait_ready(run_cmd, a.name, a.timeout)
    result.update({"status": state, "ready_seconds": secs, "pane": pane and pane["pane"]})
    if state == "ready":
        tmux("send-keys", "-t", pane["pane"], "-l", a.prompt)
        # 文字列と Enter を続けて送ると、長い文が貼り付け扱いになる前に Enter が届くことがある
        time.sleep(0.3)
        tmux("send-keys", "-t", pane["pane"], "Enter")
        result["status"] = "sent"
        time.sleep(1.5)
    if pane:
        cap = (run_cmd(["tmux", "capture-pane", "-p", "-t", pane["pane"]]) or "").splitlines()
        result["tail"] = [s.rstrip() for s in cap if s.strip()][-8:]
    print(json.dumps(result, ensure_ascii=False, indent=1))
    return 0 if result["status"] == "sent" else 1


if __name__ == "__main__":
    sys.exit(main())
