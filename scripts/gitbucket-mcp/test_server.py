"""server.py のテスト。実行: uv --directory scripts/gitbucket-mcp run python -m unittest test_server"""

import json
import unittest
from unittest import mock

import server


def _pr(**over):
    pr = {"number": 2, "title": "t", "state": "open", "body": "old", "html_url": "u",
          "user": {"login": "a"}, "head": {"label": "h"}, "base": {"label": "b"},
          "created_at": "c", "updated_at": "c"}
    pr.update(over)
    return pr


class UpdatePrTest(unittest.TestCase):
    def test_body_not_applied_raises(self):
        with mock.patch.object(server, "call_api", return_value=_pr(body="old")):
            with self.assertRaisesRegex(server.GitBucketError, "body"):
                server.gitbucket_update_pr("o", "r", 2, body="new")

    def test_body_applied_returns_updated(self):
        with mock.patch.object(server, "call_api", return_value=_pr(body="new\r\nline")):
            self.assertIn("PRを更新しました", server.gitbucket_update_pr("o", "r", 2, body="new\nline"))

    def test_body_only_sends_current_title(self):
        # GitBucket 4.47 は title を送ったときしか body を書き込まない
        calls = []

        def fake(method, endpoint, data=None):
            calls.append((method, data))
            return _pr(title="current") if method == "GET" else _pr(title="current", body="new")

        with mock.patch.object(server, "call_api", side_effect=fake):
            server.gitbucket_update_pr("o", "r", 2, body="new")
        self.assertEqual(calls[-1], ("PATCH", {"title": "current", "body": "new"}))

    def test_title_only_sends_current_body(self):
        # GitBucket 4.47 は title を送ると body も書き込むため、body を省くと本文が空になる
        calls = []

        def fake(method, endpoint, data=None):
            calls.append((method, data))
            return _pr(body="current") if method == "GET" else _pr(title="new", body="current")

        with mock.patch.object(server, "call_api", side_effect=fake):
            server.gitbucket_update_pr("o", "r", 2, title="new")
        self.assertEqual(calls[-1], ("PATCH", {"title": "new", "body": "current"}))

    def test_state_applied(self):
        with mock.patch.object(server, "call_api", return_value=_pr(state="closed")):
            self.assertIn("PRを更新しました", server.gitbucket_update_pr("o", "r", 2, state="closed"))


INLINE_PAGE = """
<div class="commit-comment-box " id="discussion_r10" filename="src/x.py" newline="3">
  <div class="commit-comment-10"><div class="markdown-body">
    <div><a class="username strong" href="#">alice</a><span data-toggle="tooltip" title="t1">x</span></div>
    <div class="commit-commentContent-10"><p>inline</p></div>
  </div></div>
</div>
"""


def _api(pr_exists: bool):
    def fake(method, endpoint, data=None):
        if endpoint.endswith("/comments"):
            return [{"id": 1, "user": {"login": "bob"}, "body": "normal", "created_at": "c"}]
        if "/pulls/" in endpoint:
            if not pr_exists:
                raise server.NotFoundError("リポジトリまたはリソースが見つかりません")
            return _pr()
        raise AssertionError(endpoint)
    return fake


class ListCommentsTest(unittest.TestCase):
    def _run(self, pr_exists=True, page=(200, INLINE_PAGE)):
        with mock.patch.object(server, "call_api", side_effect=_api(pr_exists)), \
                mock.patch.object(server, "get_page", return_value=page) as gp:
            return json.loads(server.gitbucket_list_comments("o", "r", 2)), gp

    def test_PRなら通常とインラインの両方を返す(self):
        got, gp = self._run()
        self.assertEqual([c["body"] for c in got["comments"]], ["normal"])
        self.assertEqual([(c["path"], c["line"], c["body"]) for c in got["inline_comments"]], [("src/x.py", 3, "inline")])
        self.assertIsNone(got["inline_error"])
        self.assertTrue(gp.call_args.args[0].endswith("/o/r/pull/2"))

    def test_Issueの番号ならインラインは空(self):
        got, gp = self._run(pr_exists=False)
        self.assertEqual(got["inline_comments"], [])
        self.assertIsNone(got["inline_error"])
        gp.assert_not_called()

    def test_画面が開けないときはnullと理由(self):
        for page in [(401, ""), (302, "Redirected to /signin")]:
            got, _ = self._run(page=page)
            self.assertIsNone(got["inline_comments"])
            self.assertIn("0件ではない", got["inline_error"])
            self.assertIn("ブラウザ", got["inline_error"])


class _Recorder:
    def __init__(self, responses=None):
        self.calls, self.responses = [], responses or {}

    def __call__(self, method, endpoint, data=None):
        self.calls.append((method, endpoint, data))
        return self.responses.get((method, endpoint), {"ok": True})


class NewToolsTest(unittest.TestCase):
    def _with(self, rec):
        return mock.patch.object(server, "call_api", side_effect=rec)

    def test_マージはPUTで既定のメッセージに任せる(self):
        rec = _Recorder()
        with self._with(rec):
            server.gitbucket_merge_pr("o", "r", 2)
        self.assertEqual(rec.calls, [("PUT", "/repos/o/r/pulls/2/merge", None)])

    def test_マージにメッセージを渡せる(self):
        rec = _Recorder()
        with self._with(rec):
            server.gitbucket_merge_pr("o", "r", 2, commit_message="m")
        self.assertEqual(rec.calls, [("PUT", "/repos/o/r/pulls/2/merge", {"commit_message": "m"})])

    def test_既定ブランチは消さない(self):
        rec = _Recorder({("GET", "/repos/o/r"): {"default_branch": "main"}})
        with self._with(rec), self.assertRaises(server.GitBucketError):
            server.gitbucket_delete_branch("o", "r", "main")
        self.assertNotIn("DELETE", [c[0] for c in rec.calls])

    def test_日本語のブランチ名をURLエンコードして消す(self):
        rec = _Recorder({("GET", "/repos/o/r"): {"default_branch": "main"}})
        with self._with(rec):
            server.gitbucket_delete_branch("o", "r", "【No00000005】x")
        method, endpoint, _ = rec.calls[-1]
        self.assertEqual(method, "DELETE")
        self.assertEqual(endpoint, "/repos/o/r/git/refs/heads/%E3%80%90No00000005%E3%80%91x")

    def test_汎用GETはhttpやドット2つのパスを断る(self):
        for bad in ["http://x/repos", "/repos/../admin", "repos/o/r"]:
            with self._with(_Recorder()), self.assertRaises(server.GitBucketError):
                server.gitbucket_api_get(bad)

    def test_汎用GETはそのままGETする(self):
        rec = _Recorder({("GET", "/repos/o/r/collaborators"): [{"login": "a"}]})
        with self._with(rec):
            self.assertEqual(json.loads(server.gitbucket_api_get("/repos/o/r/collaborators")), [{"login": "a"}])

    def test_ユーザー指定の有無で組織一覧のエンドポイントが変わる(self):
        rec = _Recorder({("GET", "/user/orgs"): [{"login": "eBASE"}], ("GET", "/users/x/orgs"): [{"login": "AI_dev"}]})
        with self._with(rec):
            self.assertEqual(json.loads(server.gitbucket_list_user_orgs()), ["eBASE"])
            self.assertEqual(json.loads(server.gitbucket_list_user_orgs("x")), ["AI_dev"])

    def test_ユーザー情報は主要な項目だけ返す(self):
        rec = _Recorder({("GET", "/user"): {"login": "mori.a", "name": "M", "site_admin": False, "extra": 1}})
        with self._with(rec):
            self.assertEqual(json.loads(server.gitbucket_get_user()), {"login": "mori.a", "name": "M", "site_admin": False})


class ErrorTypeTest(unittest.TestCase):
    def test_更新が反映されないとGitBucketErrorを投げる(self):
        with mock.patch.object(server, "call_api", return_value=_pr(body="old")):
            with self.assertRaises(server.GitBucketError):
                server.gitbucket_update_pr("o", "r", 2, body="new")


if __name__ == "__main__":
    unittest.main()
