"""Find handoff notes in agent-memory by PR / issue numbers or words.

Usage: find_handoff.py [--root <memories dir>] [terms...]

Prints one JSON object: {"stage": ..., "hits": [{"path", "summary", "created", "status"}]}.
Stages are tried in order and the first with hits wins:
handoff-open (tag handoff, status blocked) -> handoff-all -> work-in-progress -> all -> none.
With no terms, lists the open handoffs.
"""

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_ROOT = Path.home() / ".claude/skills/agent-memory/memories"
NUMBER_TERM = re.compile(r"^(?:#|pr|no)?0*(\d+)$", re.IGNORECASE)


def matches(text: str, terms: list[str]) -> bool:
    """True when every term appears in text: numbers as whole numbers ignoring leading zeros, words case-insensitively."""
    lowered = text.lower()
    for term in terms:
        number = NUMBER_TERM.match(term)
        if number:
            if not re.search(rf"(?<!\d)0*{number.group(1)}(?!\d)", text):
                return False
        elif term.lower() not in lowered:
            return False
    return True


def _front_matter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    fields = {}
    for line in text[3:end if end != -1 else len(text)].splitlines():
        m = re.match(r"^(summary|created|status|tags):\s*(.*)$", line)
        if m:
            fields[m.group(1)] = m.group(2).strip().strip('"')
    return fields


def _notes(root: Path):
    for path in sorted(root.rglob("*.md")):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        meta = _front_matter(text)
        tags = [t.strip() for t in meta.get("tags", "").strip("[]").split(",")]
        yield path, text, meta, "handoff" in tags


def search(root: Path, terms: list[str]) -> dict:
    """Search the memories under root, widening stage by stage until something matches."""
    notes = list(_notes(root))
    wip = root / "work-in-progress"
    stages = [
        ("handoff-open", lambda p, m, h: h and m.get("status") == "blocked"),
        ("handoff-all", lambda p, m, h: h),
        ("work-in-progress", lambda p, m, h: wip in p.parents),
        ("all", lambda p, m, h: True),
    ]
    for name, keep in stages:
        hits = [
            {"path": str(p), "summary": m.get("summary", ""), "created": m.get("created", ""), "status": m.get("status", "")}
            for p, text, m, is_handoff in notes
            if keep(p, m, is_handoff) and matches(text, terms)
        ]
        if hits or not terms:
            hits.sort(key=lambda h: h["created"], reverse=True)
            return {"stage": name, "hits": hits}
    return {"stage": "none", "hits": []}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("terms", nargs="*")
    args = parser.parse_args(argv)
    print(json.dumps(search(args.root, args.terms), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
