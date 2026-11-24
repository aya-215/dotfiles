#!/usr/bin/env python3
"""前の司令塔ファイルの「## 引き継ぐ欄」を読み、掃除して書き出す。"""
import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".dotfiles/scripts/todo-ai"))
import todo_md  # noqa: E402

SECTION = "## 引き継ぐ欄"
SUBS = [("期限", "deadlines"), ("済んだこと", "done"), ("作業中の tmux セッション", "tmux"), ("メモ", "memo")]
_REF = re.compile(r"\[ref:([^\]]+)\]\s*\Z")
_TMUX = re.compile(r"- ([^:\s]+):")


@dataclass
class Carry:
    deadlines: "list[str]" = field(default_factory=list)
    done: "list[str]" = field(default_factory=list)
    tmux: "list[str]" = field(default_factory=list)
    memo: "list[str]" = field(default_factory=list)


def extract(text: str) -> Carry:
    c = Carry()
    names = {f"### {title}": attr for title, attr in SUBS}
    inside, current = False, "memo"
    for line in text.splitlines():
        if line.startswith("## "):
            inside = line.strip() == SECTION
            current = "memo"
            continue
        if not inside:
            continue
        if line.startswith("### "):
            # 知らない小見出しの下の行は落とさずメモへ
            current = names.get(line.strip(), "memo")
            continue
        if line.strip():
            getattr(c, current).append(line)
    return c


def prune(c: Carry, live_sessions: "list[str] | None", open_refs: "set[str] | None") -> "tuple[Carry, dict]":
    info = {"removed_tmux": [], "removed_done": [], "done_still_in_todo": [], "unparsed_done": []}
    tmux = []
    for line in c.tmux:
        m = _TMUX.match(line)
        if live_sessions is not None and m and m.group(1) not in live_sessions:
            info["removed_tmux"].append(line)
        else:
            tmux.append(line)
    done = []
    for line in c.done:
        m = _REF.search(line)
        if not m:
            info["unparsed_done"].append(line)
            done.append(line)
        elif open_refs is None:
            done.append(line)
        elif m.group(1) in open_refs:
            info["done_still_in_todo"].append(line)
            done.append(line)
        else:
            info["removed_done"].append(line)
    return Carry(list(c.deadlines), done, tmux, list(c.memo)), info


def render(c: Carry) -> str:
    out = [SECTION]
    for title, attr in SUBS:
        out.append(f"### {title}")
        out += getattr(c, attr)
    return "\n".join(out) + "\n"


def open_refs_of(todo_path: Path) -> "set[str] | None":
    try:
        doc = todo_md.parse(todo_path.read_text(encoding="utf-8"))
    except (OSError, todo_md.ParseError):
        return None
    refs = {it.ref for s in ("やる", "待ち") for it in doc.sections.get(s, []) if not it.done}
    for line in doc.confirm:
        refs.update(m.group(0) for m in todo_md.KEY_RE.finditer(line))
    return refs


def _live_sessions() -> "list[str] | None":
    try:
        out = subprocess.run(["tmux", "list-sessions", "-F", "#S"], capture_output=True, text=True, timeout=10, check=True)
        return [s for s in out.stdout.splitlines() if s]
    except (OSError, subprocess.SubprocessError):
        return None


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--prev", type=Path)
    p.add_argument("--todo", type=Path, default=Path.home() / "memo/todo.md")
    a = p.parse_args(argv)
    try:
        text = a.prev.read_text(encoding="utf-8") if a.prev else ""
    except OSError as e:
        print(f"warn: 前の司令塔ファイルを読めません: {e}", file=sys.stderr)
        text = ""
    refs = open_refs_of(a.todo)
    if refs is None:
        print(f"warn: todo を読めないので済んだことは消しません: {a.todo}", file=sys.stderr)
    sessions = _live_sessions()
    if sessions is None:
        print("warn: tmux の一覧を取れないので tmux セッションの行は消しません", file=sys.stderr)
    c, info = prune(extract(text), sessions, refs)
    print(json.dumps({"section": render(c), **info}, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
