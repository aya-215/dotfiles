"""todo.md と Doc モデルの相互変換（純関数）。

正規形（render の出力）:
  preamble の行、空行1つ、`## 確認待ち`、確認待ちの行、空行1つ、`## やる`、タスク行、
  空行1つ、`## 待ち`、... `## 完了`、タスク行。末尾は改行1つ。
  preamble が空なら先頭の空行は出さない。見出し直下に空行は入れない。
  確認待ちの内側の空行は保持するが、前後の空行は落とす。
  非正規形の入力は parse できるが、render すると正規形に整う。
"""
import re
from dataclasses import dataclass, field

HEADINGS = ["確認待ち", "やる", "待ち", "完了"]
TASK_SECTIONS = ["やる", "待ち", "完了"]

KEY_RE = re.compile(
    r"(?:(?:epc|emm|eae|eas)#\d+"
    r"|gb:[\w.-]+#\d+"
    r"|rc:[\w-]+(?:#\d+)?"
    r"|mail:[^\s\[\]()]+"
    r"|wt:[^\s\[\]()]+)"
)
_KEY_FULL = re.compile(KEY_RE.pattern + r"\Z")
_LINK_TAIL = re.compile(r"(?:^|(?<= ))\[(" + KEY_RE.pattern + r")\]\(([^\s()]+)\)\Z")
_TASK = re.compile(r"- \[([ x])\] (.*)\Z")
_DONE = re.compile(r" \(done: (\d{4}-\d{2}-\d{2})\)\Z")
_NEXT = " — next: "


class ParseError(ValueError):
    pass


def is_key(s: str) -> bool:
    return bool(_KEY_FULL.match(s))


@dataclass
class Item:
    """raw は parse 時の元の行。render は使わない。新しく作った Item では ""。"""

    title: str
    key: "str | None" = None
    url: "str | None" = None
    next: "str | None" = None
    done: bool = False
    done_date: "str | None" = None
    raw: str = ""

    @property
    def ref(self) -> str:
        return self.key if self.key else "title:" + self.title


@dataclass
class Doc:
    preamble: "list[str]" = field(default_factory=list)
    confirm: "list[str]" = field(default_factory=list)
    sections: "dict[str, list[Item]]" = field(
        default_factory=lambda: {k: [] for k in TASK_SECTIONS}
    )


def split_lines(text: str) -> "list[str]":
    """LF と CRLF だけで行に分ける。str.splitlines は U+2028 や \\x0c でも割り、タイトルが別の行になる。"""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [l[:-1] if l.endswith("\r") else l for l in lines]


def _parse_item(line: str, lineno: int) -> Item:
    m = _TASK.match(line)
    if not m:
        raise ParseError(f"line {lineno}: タスク行ではない: {line!r}")
    done = m.group(1) == "x"
    rest = m.group(2)
    done_date = None
    d = _DONE.search(rest)
    if d:
        done_date = d.group(1)
        rest = rest[: d.start()]
    nxt = None
    i = rest.rfind(_NEXT)
    if i >= 0:
        nxt = rest[i + len(_NEXT):]
        rest = rest[:i]
    key = url = None
    lm = _LINK_TAIL.search(rest)
    if lm:
        key, url = lm.group(1), lm.group(2)
        rest = rest[: lm.start()].rstrip(" ")
    return Item(rest, key, url, nxt, done, done_date, line)


def parse(text: str) -> Doc:
    doc = Doc()
    current = None
    seen = []
    confirm = []
    for n, line in enumerate(split_lines(text), 1):
        if line.startswith("## "):
            name = line[3:].strip()
            if name not in HEADINGS:
                raise ParseError(f"line {n}: 未知の見出し: {line!r}")
            if name in seen:
                raise ParseError(f"line {n}: 見出しが重複: {line!r}")
            if seen and HEADINGS.index(name) != HEADINGS.index(seen[-1]) + 1:
                raise ParseError(f"line {n}: 見出しの順序が違う: {line!r}")
            if not seen and name != HEADINGS[0]:
                raise ParseError(f"line {n}: 最初の見出しが確認待ちではない")
            seen.append(name)
            current = name
        elif current is None:
            doc.preamble.append(line)
        elif current == "確認待ち":
            confirm.append(line)
        elif line.strip() == "":
            continue
        else:
            doc.sections[current].append(_parse_item(line, n))
    if seen != HEADINGS:
        missing = [h for h in HEADINGS if h not in seen]
        raise ParseError(f"見出しが足りない: {missing}")
    while doc.preamble and not doc.preamble[-1].strip():
        doc.preamble.pop()
    while confirm and not confirm[0].strip():
        confirm.pop(0)
    while confirm and not confirm[-1].strip():
        confirm.pop()
    doc.confirm = confirm
    return doc


def _render_item(it: Item) -> str:
    if it.key and not it.url:
        raise ValueError(f"key があるのに url が無い: {it.key}")
    for v in (it.title, it.next):
        if v and "\n" in v:
            raise ValueError(f"title/next に改行は入れられない: {v!r}")
    s = "- [x] " if it.done else "- [ ] "
    parts = []
    if it.title:
        parts.append(it.title)
    if it.key:
        parts.append(f"[{it.key}]({it.url})")
    s += " ".join(parts)
    if it.next is not None:
        s += _NEXT + it.next
    if it.done_date:
        s += f" (done: {it.done_date})"
    return s


def render(doc: Doc) -> str:
    out = list(doc.preamble)
    for h in HEADINGS:
        if out:
            out.append("")
        out.append(f"## {h}")
        if h == "確認待ち":
            out.extend(doc.confirm)
        else:
            out.extend(_render_item(it) for it in doc.sections[h])
    return "\n".join(out) + "\n"
