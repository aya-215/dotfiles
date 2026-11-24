"""文中の PR・issue・課題No を todo のキー形式に直し、作業場所を引く。"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".dotfiles/scripts/todo-ai"))
import sync_github  # noqa: E402
import todo_md  # noqa: E402

DEFAULT_GB_ROOTS = [Path.home() / "src/192.168.208.80/gitbucket"]
GITHUB_ROOT = Path.home() / "src/github.com" / sync_github.ORG

_ABBR = {repo: abbr for abbr, repo in sync_github.REPOS.items()}
_GITHUB = re.compile(r"github\.com/" + re.escape(sync_github.ORG) + r"/([\w.-]+)/(?:pull|issues)/(\d+)")
_GITBUCKET = re.compile(r"/gitbucket/[\w.-]+/([\w.-]+)/(?:pull|issues)/(\d+)")
_EBPM = re.compile(r"(?<![A-Za-z])No0*(\d{5,})")
# 「src:」の中の「rc:」のような語の途中を拾わないため
_KEY = re.compile(r"(?<![\w:])" + todo_md.KEY_RE.pattern)
_WORKDIR = re.compile(r"作業場所:\s*([^\s（(]+)")


def refs_in_text(text: str) -> "set[str]":
    found = set()
    for repo, num in _GITHUB.findall(text):
        if repo in _ABBR:
            found.add(f"{_ABBR[repo]}#{num}")
    for repo, num in _GITBUCKET.findall(text):
        found.add(f"gb:{repo}#{num}")
    for num in _EBPM.findall(text):
        found.add("ebpm:No" + num.zfill(8))
    for m in _KEY.finditer(text):
        found.add(m.group(0))
    return found


def workdir_in_memo(text: str) -> "str | None":
    m = _WORKDIR.search(text)
    return m.group(1) if m else None


def location_for(ref: str, gitbucket_roots: "list[Path]" = DEFAULT_GB_ROOTS) -> "str | None":
    abbr, sep, _ = ref.partition("#")
    if sep and abbr in sync_github.REPOS:
        return str(GITHUB_ROOT / sync_github.REPOS[abbr])
    if ref.startswith("gb:") and sep:
        repo = abbr[len("gb:"):]
        for root in gitbucket_roots:
            for p in sorted(root.glob(f"*/{repo}")):
                if p.is_dir():
                    return str(p)
    return None
