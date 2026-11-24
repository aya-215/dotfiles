"""inline_comments.py のテスト。HTML は ebase-infra の test_gitbucket_api.py から移した合成データ。"""

import unittest

from inline_comments import parse_inline_comments

PAGE = """
<script>
  // 画面内の JS テンプレートにも同じクラス名がある。これを拾ってはならない
  const $v = $('<div class="commit-comment-box reply-comment-box">');
</script>
<div class="panel panel-default">
  <table><tr><th class="line-num newline insert">21</th><td class="body insert">x</td></tr></table>
  <div class="panel-body">
    <div class="commit-comment-box " id="discussion_r374"
      filename="docs/a.md"
      newline="21"
      >
      <div class="commit-comment-374">
        <div class="markdown-body">
          <div>
            <a href="/gitbucket/reviewer" class=""><img alt="@reviewer" /></a>
            <a href="/gitbucket/reviewer" class="username strong">reviewer</a>
            <span class="muted"><span data-toggle="tooltip" title="2026-08-24 14:46:56">2 月 前</span></span>
          </div>
          <div class="commit-commentContent-374">
            <p><code>exclamation-color</code> では？<br>
もう一度確認してください。</p>
            <div class="codeblock-wrapper"><pre>a &lt; b</pre></div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
<div class="commit-comment-box " id="discussion_r375" filename="docs/b.md" oldline="7">
  <div class="commit-comment-375"><div class="markdown-body">
    <div><a class="username strong" href="/gitbucket/other">other</a>
      <span data-toggle="tooltip" title="2026-08-24 15:03:13">x</span></div>
    <div class="commit-commentContent-375"><p>削除行への指摘</p></div>
  </div></div>
</div>
<div class="panel issue-comment-box" id="comment-7110"><div id="commentContent-7110"><p>通常コメント</p></div></div>
"""


THREAD = """
<div id="discussion_reply-form"></div>
<div class="commit-comment-box " id="discussion_r10" filename="src/x.py" newline="3">
  <div class="commit-comment-10"><div class="markdown-body">
    <div><a class="username strong" href="#">alice</a><span data-toggle="tooltip" title="t1">x</span></div>
    <div class="commit-commentContent-10"><p>first</p></div>
  </div></div>
  <div class="commit-comment-11"><div class="markdown-body">
    <div><a class="username strong" href="#">bob</a><span data-toggle="tooltip" title="t2">x</span></div>
    <div class="commit-commentContent-11"><p>reply</p></div>
  </div></div>
</div>
"""


class ParseInlineCommentsTest(unittest.TestCase):
    def test_インラインコメントだけを位置と本文付きで取り出す(self):
        got = parse_inline_comments(PAGE)
        self.assertEqual([c["id"] for c in got], [374, 375])
        a, b = got
        self.assertEqual((a["path"], a["line"], a["side"], a["user"]), ("docs/a.md", 21, "new", "reviewer"))
        self.assertEqual(a["created_at"], "2026-08-24 14:46:56")
        self.assertIn("exclamation-color では？", a["body"])
        self.assertIn("もう一度確認してください。", a["body"])
        self.assertIn("a < b", a["body"])
        self.assertNotIn("2 月 前", a["body"])
        self.assertEqual((b["path"], b["line"], b["side"], b["user"]), ("docs/b.md", 7, "old", "other"))

    def test_インラインコメントが無い画面では空のリストになる(self):
        self.assertEqual(parse_inline_comments('<div class="commit-comment-box reply-comment-box"></div>'), [])

    def test_同じ行への返信は投稿者と時刻ごとに別の1件になる(self):
        got = parse_inline_comments(THREAD)
        self.assertEqual(
            [(c["id"], c["user"], c["created_at"], c["body"]) for c in got],
            [(10, "alice", "t1", "first"), (11, "bob", "t2", "reply")],
        )
        self.assertTrue(all((c["path"], c["line"], c["side"]) == ("src/x.py", 3, "new") for c in got))


if __name__ == "__main__":
    unittest.main()
