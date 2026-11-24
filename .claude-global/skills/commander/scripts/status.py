#!/usr/bin/env python3
"""「現在の状況をまとめて」の材料（tmux・GitHub・引き継ぎメモの変化・到達性・git）を1回で JSON に出す。"""
import re
import sys
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import carry  # noqa: E402

JST = timezone(timedelta(hours=9))
PORTS = (22, 80, 445, 3389)
PROBE_TIMEOUT = 2
_LAST = re.compile(r"^最終確認:\s*(.+?)\s*$", re.M)
_WAIT = re.compile(r"^## 待っているもの\s*\n(.*?)(?=^## |\Z)", re.S | re.M)
_IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
_HEADING = re.compile(r"^## (.+?)\s*$", re.M)


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


def changed_handoffs(memo_dir: Path, since: datetime) -> "list[dict]":
    out = []
    for p in sorted(memo_dir.glob("handoff-*.md")):
        if p.stat().st_mtime <= since.timestamp():
            continue
        text = p.read_text(encoding="utf-8")
        headings = _HEADING.findall(text)
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
