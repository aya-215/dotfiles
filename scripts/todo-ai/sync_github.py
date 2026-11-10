#!/usr/bin/env python3
"""GitHub の PR/Issue の状態から、マージ・クローズ済みの行を完了へ移す変更案を作る（AI なし）。"""
import argparse
import getpass
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import decisions
import todo_md

REPOS = {
    "epc": "ebase-portal-chat",
    "emm": "ebase-middleware-mcp",
    "eae": "eb-api-extended",
    "eas": "ebase-agent-specs",
}
ORG = "ebase-dev"
ACCOUNT = "eBASE-Mori"
HERE = Path(__file__).resolve().parent

_token = None


def warn(msg: str) -> None:
    print(f"warn: {msg}", file=sys.stderr)


def ensure_gh_path(env=os.environ) -> None:
    """cron の PATH には Nix の gh が無いので、見つからなければ Home Manager の bin を前に足す。"""
    if shutil.which("gh", path=env.get("PATH")):
        return
    home = env.get("HOME") or str(Path.home())
    user = env.get("USER") or getpass.getuser()
    dirs = [f"{home}/.nix-profile/bin", f"/etc/profiles/per-user/{user}/bin"]
    env["PATH"] = ":".join(dirs + ([env["PATH"]] if env.get("PATH") else []))


def load_records(todo: Path) -> "list[dict]":
    """判断記録に、まだ記録していない人の戻しを足したもの（書かない。記録は次の apply が行う）。"""
    records = decisions.load(todo.parent / decisions.DECISIONS_NAME)
    return records + decisions.detect_reverts(todo.parent, todo.name, records)


def get_token() -> "str | None":
    try:
        r = subprocess.run(["gh", "auth", "token", "--user", ACCOUNT], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    tok = r.stdout.strip()
    return tok if r.returncode == 0 and tok else None


def state_from_json(data) -> "str | None":
    if not isinstance(data, dict):
        return None
    st = data.get("state")
    if st == "open":
        return "open"
    if st == "closed":
        pr = data.get("pull_request")
        if isinstance(pr, dict) and pr.get("merged_at"):
            return "merged"
        return "closed"
    return None


def fetch_state(repo: str, number: int) -> "str | None":
    """失敗はすべて None。None を「閉じた」と扱わせない。"""
    if not _token:
        warn("GH_TOKEN がありません")
        return None
    env = {**os.environ, "GH_TOKEN": _token}
    try:
        r = subprocess.run(["gh", "api", f"repos/{ORG}/{repo}/issues/{number}"],
                           capture_output=True, text=True, env=env, timeout=60)
        if r.returncode != 0:
            warn(f"{repo}#{number}: gh api 失敗: {r.stderr.strip()[:200]}")
            return None
        st = state_from_json(json.loads(r.stdout))
    except (OSError, subprocess.TimeoutExpired, ValueError) as e:
        warn(f"{repo}#{number}: {e}")
        return None
    if st is None:
        warn(f"{repo}#{number}: 状態を解釈できません")
    return st


def build_ops(doc: todo_md.Doc, records: "list[dict]", fetch) -> "list[dict]":
    ops = []
    for section in ("やる", "待ち"):
        for it in doc.sections[section]:
            if not it.key or "#" not in it.key or ":" in it.key:
                continue
            abbr, _, num = it.key.partition("#")
            repo = REPOS.get(abbr)
            if repo is None:
                if abbr in ("epc", "emm", "eae", "eas"):
                    continue
                warn(f"未知のリポジトリ略称: {it.key}")
                continue
            if decisions.is_pinned(records, it.ref, "完了"):
                continue
            st = fetch(repo, int(num))
            if st not in ("merged", "closed"):
                continue
            label = "マージ済み" if st == "merged" else "クローズ済み"
            ops.append({"op": "move", "ref": it.ref, "to": "完了",
                        "reason": f"GitHub 上で{label}: {it.url or it.key}"})
    return ops


def main(argv=None) -> int:
    global _token
    p = argparse.ArgumentParser()
    p.add_argument("--todo", type=Path)
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args(argv)
    todo = (a.todo or Path(os.environ.get("TODO_MD_PATH") or Path.home() / "memo" / "todo.md")).expanduser().absolute()

    os.environ.setdefault("LANG", "C.UTF-8")
    ensure_gh_path()
    _token = get_token()
    if not _token:
        print(f"error: gh auth token --user {ACCOUNT} に失敗", file=sys.stderr)
        return 1
    try:
        doc = todo_md.parse(todo.read_text(encoding="utf-8"))
    except (OSError, todo_md.ParseError) as e:
        print(f"error: {todo}: {e}", file=sys.stderr)
        return 1
    records = load_records(todo)

    ops = build_ops(doc, records, fetch_state)
    changes = {"source": "sync", "ops": ops}
    if a.dry_run:
        print(json.dumps(changes, ensure_ascii=False, indent=2))
        return 0
    if not ops:
        return 0
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8", delete=False) as f:
        json.dump(changes, f, ensure_ascii=False)
        tmp = f.name
    try:
        cmd = [sys.executable, str(HERE / "apply.py"), "--changes", tmp, "--todo", str(todo)]
        return subprocess.run(cmd).returncode
    finally:
        os.unlink(tmp)


if __name__ == "__main__":
    sys.exit(main())
