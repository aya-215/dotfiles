#!/usr/bin/env python3
"""司令塔の材料（todo・待ち中の引き継ぎメモ・祝日・司令塔ファイルの場所・tmux）を JSON で出す。"""
import argparse
import json
import re
import subprocess
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from jp_holidays import holidays_between  # noqa: E402
from refs import location_for, refs_in_text, workdir_in_memo  # noqa: E402

sys.path.insert(0, str(Path.home() / ".dotfiles/scripts/todo-ai"))
import todo_md  # noqa: E402

JST = timezone(timedelta(hours=9))
RANGE_DAYS = 14
FIND_HANDOFF = Path.home() / ".claude/skills/pickup/scripts/find_handoff.py"
_STAMP = re.compile(r"handoff-(\d{8})-(\d{4})")
_DAY_FILE = re.compile(r"\d{4}-\d{2}-\d{2}\.md\Z")
_WAIT = re.compile(r"^## 待っているもの\s*\n(.*?)(?=^## |\Z)", re.S | re.M)
_NUM = re.compile(r"(?:#|No\.?|/|PR\s*)0*(\d+)")


def _since(path: Path, created: str, warnings: "list[str]") -> "str | None":
    m = _STAMP.search(path.name)
    try:
        if m:
            dt = datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M")
        else:
            dt = datetime.fromisoformat(created)
    except ValueError:
        warnings.append(f"待ちに入った日時が分からない: {path.name}")
        return None
    return dt.replace(tzinfo=JST).isoformat()


def _wait_refs(text: str, refs: "list[str]") -> "list[str]":
    m = _WAIT.search(text)
    if not m:
        return list(refs)
    nums = {n.lstrip("0") for n in _NUM.findall(m.group(1))}
    return [r for r in refs if re.split(r"#|No", r)[-1].lstrip("0") in nums]


def _existing(loc: "str | None") -> "str | None":
    return loc if loc and Path(loc).is_dir() else None


def _todo_rows(todo_path: Path, warnings: "list[str]") -> "tuple[list[dict], list[str]]":
    try:
        doc = todo_md.parse(todo_path.read_text(encoding="utf-8"))
    except (OSError, todo_md.ParseError) as e:
        warnings.append(f"todo を読めません: {e}")
        return [], []
    rows = []
    for section in ("やる", "待ち"):
        for it in doc.sections.get(section, []):
            if it.done:
                continue
            rows.append({
                "section": section, "ref": it.ref, "title": it.title, "url": it.url, "next": it.next,
                "location": _existing(location_for(it.key)) if it.key else None, "handoffs": [],
            })
    return rows, list(doc.confirm)


def _handoff(hit: dict, warnings: "list[str]") -> dict:
    path = Path(hit["path"])
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        warnings.append(f"引き継ぎメモを読めません: {path}: {e}")
        text = ""
    refs = sorted(refs_in_text(text))
    location = workdir_in_memo(text)
    if location and not _existing(location):
        warnings.append(f"作業場所が無い: {location}（{path.name}）")
        location = None
    if location is None:
        location = next((loc for loc in (_existing(location_for(r)) for r in refs) if loc), None)
    return {"path": str(path), "summary": hit.get("summary", ""), "since": _since(path, hit.get("created") or "", warnings),
            "refs": refs, "wait_refs": _wait_refs(text, refs), "location": location, "todo_refs": []}


def _files(commander_dir: Path, today: date) -> dict:
    today_path = commander_dir / f"{today.isoformat()}.md"
    days = sorted(p.name for p in commander_dir.glob("*.md") if _DAY_FILE.match(p.name)) if commander_dir.is_dir() else []
    older = [n for n in days if n < today_path.name]
    return {"today": str(today_path), "today_exists": today_path.exists(),
            "previous": str(commander_dir / older[-1]) if older else None}


def collect(todo_path: Path, handoffs: "list[dict]", commander_dir: Path, today: date,
            tmux_sessions: "list[str] | None") -> dict:
    warnings: "list[str]" = []
    rows, confirm = _todo_rows(todo_path, warnings)
    memos = [_handoff(h, warnings) for h in handoffs]
    by_ref = {r["ref"]: r for r in rows}
    for m in memos:
        for ref in m["refs"]:
            if ref in by_ref:
                m["todo_refs"].append(ref)
                by_ref[ref]["handoffs"].append(m["path"])
    end = today + timedelta(days=RANGE_DAYS)
    return {
        "today": today.isoformat(), "range_end": end.isoformat(),
        "holidays": [{"date": d.isoformat(), "name": n} for d, n in holidays_between(today, end)],
        "files": _files(commander_dir, today),
        "todo": rows, "confirm_lines": confirm, "handoffs": memos,
        "tmux_sessions": tmux_sessions, "warnings": warnings,
    }


def _find_handoffs(warnings: "list[str]") -> "list[dict]":
    try:
        out = subprocess.run(["python3", "-I", str(FIND_HANDOFF)], capture_output=True, text=True, timeout=60, check=True)
        return [h for r in json.loads(out.stdout)["results"] for h in r["hits"]]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as e:
        warnings.append(f"引き継ぎメモを集められません: {e}")
        return []


def _tmux_sessions() -> "list[str] | None":
    try:
        out = subprocess.run(["tmux", "list-sessions", "-F", "#S"], capture_output=True, text=True, timeout=10, check=True)
        return [s for s in out.stdout.splitlines() if s]
    except (OSError, subprocess.SubprocessError):
        return None


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--todo", type=Path, default=Path.home() / "memo/todo.md")
    p.add_argument("--commander-dir", type=Path, default=Path.home() / "memo/commander")
    p.add_argument("--today", type=date.fromisoformat, default=datetime.now(JST).date())
    a = p.parse_args(argv)
    pre: "list[str]" = []
    hits = _find_handoffs(pre)
    out = collect(a.todo, hits, a.commander_dir, a.today, _tmux_sessions())
    out["warnings"] = pre + out["warnings"]
    for w in out["warnings"]:
        print(f"warn: {w}", file=sys.stderr)
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
