import sys
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import check_waits  # noqa: E402
from check_waits import check, returned  # noqa: E402

ME = {"eBASE-Mori", "森彪人", "mori.a"}
SINCE = datetime.fromisoformat("2026-11-20T18:22:00+09:00")


class ReturnedTest(unittest.TestCase):
    def test_merged(self):
        r = returned("merged", [], ME, SINCE)
        self.assertTrue(r["returned"])
        self.assertIn("マージ", r["reason"])

    def test_partner_after_since(self):
        ev = [{"user": "ebase-sato", "ts": "2026-11-20T09:50:00Z", "kind": "comment"}]
        r = returned("open", ev, ME, SINCE)
        self.assertTrue(r["returned"])
        self.assertEqual(r["events"], ev)

    def test_partner_before_since_or_me_only(self):
        ev = [{"user": "ebase-sato", "ts": "2026-11-20T09:00:00Z", "kind": "comment"},
              {"user": "eBASE-Mori", "ts": "2026-11-21T00:00:00Z", "kind": "comment"}]
        r = returned("open", ev, ME, SINCE)
        self.assertFalse(r["returned"])
        self.assertEqual(r["events"], [])


class CheckTest(unittest.TestCase):
    def test_kinds_without_fetch(self):
        out = check([{"ref": "gb:ebase-web#102", "since": SINCE.isoformat()},
                     {"ref": "ebpm:No00007456", "since": SINCE.isoformat()}],
                    ME, fetch_fn=None, token="t")
        self.assertEqual([o["kind"] for o in out], ["gitbucket", "other"])
        self.assertEqual([o["returned"] for o in out], [None, None])
        self.assertIn("MCP", out[0]["reason"])

    def test_fetch_failure_isolated(self):
        def fetch(repo, number, token):
            if number == 1:
                raise check_waits.pr_ball.FetchError("TLS handshake timeout")
            return "merged", []
        out = check([{"ref": "epc#1", "since": SINCE.isoformat()}, {"ref": "epc#2", "since": SINCE.isoformat()}],
                    ME, fetch_fn=fetch, token="t")
        self.assertIsNone(out[0]["returned"])
        self.assertIn("TLS", out[0]["reason"])
        self.assertTrue(out[1]["returned"])

    def test_no_token(self):
        out = check([{"ref": "epc#1", "since": SINCE.isoformat()}], ME, fetch_fn=lambda *a: ("merged", []), token=None)
        self.assertIsNone(out[0]["returned"])


class FetchTest(unittest.TestCase):
    def test_bot_comments_ignored(self):
        bot = {"login": "claude[bot]", "type": "Bot"}
        human = {"login": "ebase-sato", "type": "User"}

        def fake(path, token, paginate=False):
            if path.endswith("/pulls/1"):
                return {"state": "open", "merged": False, "user": {"login": "x"}}
            if path.endswith("/reviews") or path.endswith("/pulls/1/comments"):
                return []
            return [{"user": bot, "created_at": "2026-11-21T00:00:00Z"},
                    {"user": human, "created_at": "2026-11-21T01:00:00Z"}]
        with mock.patch.object(check_waits.pr_ball, "gh_json", side_effect=fake):
            state, events = check_waits.fetch("ebase-portal-chat", 1, "t")
        self.assertEqual(state, "open")
        self.assertEqual([e["user"] for e in events], ["ebase-sato"])

    def test_issue_fallback(self):
        def fake(path, token, paginate=False):
            if "/pulls/" in path:
                raise check_waits.pr_ball.FetchError(f"{path}: gh api 失敗: gh: Not Found (HTTP 404)")
            if path.endswith("/issues/5"):
                return {"state": "closed"}
            return []
        with mock.patch.object(check_waits.pr_ball, "gh_json", side_effect=fake):
            self.assertEqual(check_waits.fetch("ebase-portal-chat", 5, "t"), ("closed", []))


if __name__ == "__main__":
    unittest.main()
