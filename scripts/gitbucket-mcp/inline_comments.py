"""GitBucket の PR 画面（会話タブ）の HTML から、インラインのコードコメントを取り出す。

GitBucket にはインラインコメントを返す REST API が無い（/pulls/:n/comments 等は 404）。
ebase-infra プラグインの gitbucket-api スキル（gitbucket_api.py）から移植した。
"""

import re
from html.parser import HTMLParser


class InlineCommentParser(HTMLParser):
    """PR画面HTMLから、インラインのコードコメントを1件ずつ抜き出す。

    GitBucket はインラインコメントを返す REST API を持たない（/pulls/:n/comments 等は404）。
    位置は id="discussion_rNNN" のブロックが filename/newline/oldline 属性で持ち、
    そのブロックの中に同じ行への指摘と返信が class="commit-comment-{id}" の div で並ぶ。
    同じクラス名 commit-comment-box が画面内の JS テンプレートにもあるため、クラス名だけで数えない。
    """

    BREAK_TAGS = {"br", "p", "li", "pre", "div", "tr", "blockquote"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.comments: list[dict] = []
        self.depth = 0  # 文書全体の div の深さ
        self.block: dict | None = None  # 位置情報と、discussion ブロックが始まった深さ
        self.cur: dict | None = None  # 読み取り中のコメント1件
        self.cur_depth = 0
        self.body_depth = 0  # 本文 div（commit-commentContent-N）が始まった深さ。0 は本文の外
        self.in_user = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "div":
            self.depth += 1
            cls = a.get("class") or ""
            if self.block is None:
                m = re.fullmatch(r"discussion_r(\d+)", a.get("id") or "")
                if m:
                    new, old = a.get("newline"), a.get("oldline")
                    line = new or old
                    self.block = {
                        "path": a.get("filename"),
                        "line": int(line) if line else None,
                        "side": "new" if new else ("old" if old else None),
                        "depth": self.depth,
                    }
                return
            if self.cur is None:
                m = re.fullmatch(r"commit-comment-(\d+)", cls.strip())
                if m:
                    pos = {k: v for k, v in self.block.items() if k != "depth"}
                    self.cur = {"id": int(m.group(1)), **pos, "user": None, "created_at": None, "body": []}
                    self.cur_depth = self.depth
                return
            if not self.body_depth and re.match(r"commit-commentContent-\d+", cls):
                self.body_depth = self.depth
                return
        if self.cur is None:
            return
        if self.body_depth:
            if tag in self.BREAK_TAGS:
                self.cur["body"].append("\n")
            return
        if tag == "a" and "username" in (a.get("class") or "").split():
            self.in_user = True
        elif tag == "span" and a.get("data-toggle") == "tooltip" and not self.cur["created_at"]:
            self.cur["created_at"] = a.get("title")

    def handle_endtag(self, tag):
        if tag == "a":
            self.in_user = False
        if tag != "div":
            if self.cur is not None and self.body_depth and tag in self.BREAK_TAGS:
                self.cur["body"].append("\n")
            return
        if self.cur is not None:
            if self.depth == self.body_depth:
                self.body_depth = 0
            elif self.body_depth:
                self.cur["body"].append("\n")
            if self.depth == self.cur_depth:
                self.cur["body"] = re.sub(r"\n{3,}", "\n\n", "".join(self.cur["body"])).strip()
                self.comments.append(self.cur)
                self.cur = None
        if self.block is not None and self.depth == self.block["depth"]:
            self.block = None
        self.depth -= 1

    def handle_data(self, data):
        if self.cur is None:
            return
        if self.body_depth:
            self.cur["body"].append(data)
        elif self.in_user and data.strip():
            self.cur["user"] = data.strip()


def parse_inline_comments(html: str) -> list[dict]:
    p = InlineCommentParser()
    p.feed(html)
    seen, out = set(), []
    for c in p.comments:
        if c["id"] not in seen:
            seen.add(c["id"])
            out.append(c)
    return out
