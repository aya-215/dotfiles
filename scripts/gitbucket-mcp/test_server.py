"""server.py のテスト。実行: uv --directory scripts/gitbucket-mcp run python -m unittest test_server"""

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
            with self.assertRaisesRegex(RuntimeError, "body"):
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


if __name__ == "__main__":
    unittest.main()
