#!/usr/bin/env python3
"""/my-tasks --json の出力を検証する。

使い方: my_tasks_schema.py <path>  （問題があれば1行1件で標準出力に出して終了コード 1）
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import todo_md

BALLS = ("mine", "theirs", "maybe_done")
_REQUIRED = ("key", "url", "title", "ball", "next", "evidence", "deadline",
             "waiting_person", "blocks")
_DATE = re.compile(r"\d{4}-\d{2}-\d{2}\Z")


def _opt_str(v):
    return v is None or isinstance(v, str)


def validate_candidates(data) -> "list[str]":
    errs: "list[str]" = []
    if not isinstance(data, dict):
        return ["top level must be an object"]
    if not isinstance(data.get("generated_at"), str):
        errs.append("generated_at must be a string")
    w = data.get("window")
    if not (isinstance(w, dict) and all(
            isinstance(w.get(k), str) and _DATE.match(w[k]) for k in ("from", "to"))):
        errs.append("window must be {from, to} as YYYY-MM-DD")
    cands = data.get("candidates")
    if not isinstance(cands, list):
        return errs + ["candidates must be a list"]
    for i, c in enumerate(cands):
        p = f"candidates[{i}]"
        if not isinstance(c, dict):
            errs.append(f"{p}: must be an object")
            continue
        for k in _REQUIRED:
            if k not in c:
                errs.append(f"{p}: missing {k}")
        key = c.get("key")
        if key is not None and not (isinstance(key, str) and todo_md.is_key(key)):
            errs.append(f"{p}: invalid key {key!r}")
        if not _opt_str(c.get("url")):
            errs.append(f"{p}: url must be string or null")
        for k in ("title", "next", "evidence"):
            if k in c and not isinstance(c[k], str):
                errs.append(f"{p}: {k} must be a string")
        if "ball" in c and c["ball"] not in BALLS:
            errs.append(f"{p}: ball must be one of {BALLS}")
        d = c.get("deadline")
        if d is not None and not (isinstance(d, str) and _DATE.match(d)):
            errs.append(f"{p}: deadline must be YYYY-MM-DD or null")
        if not _opt_str(c.get("waiting_person")):
            errs.append(f"{p}: waiting_person must be string or null")
        b = c.get("blocks")
        if "blocks" in c and not (isinstance(b, list) and all(isinstance(x, str) for x in b)):
            errs.append(f"{p}: blocks must be a list of strings")
    return errs


def main(argv) -> int:
    if len(argv) != 2:
        print("usage: my_tasks_schema.py <path>", file=sys.stderr)
        return 2
    try:
        data = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"my_tasks_schema: 読めない: {e}")
        return 1
    errs = validate_candidates(data)
    for e in errs:
        print(e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
