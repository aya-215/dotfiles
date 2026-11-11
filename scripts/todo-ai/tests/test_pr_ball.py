import io
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import pr_ball

ME = {"eBASE-Mori", "森彪人", "mori.a"}


def pr(state="open", author="eBASE-Mori", reviewers=("alice",), events=()):
    return {"state": state, "author": author, "reviewers": list(reviewers), "events": list(events)}


def ev(user, ts, kind="comment", state=None):
    return {"user": user, "ts": ts, "kind": kind, "state": state}


class TestDecide(unittest.TestCase):
    def test_closed_merged_done(self):
        for st in ("closed", "merged"):
            self.assertEqual(pr_ball.decide(pr(state=st), ME)["ball"], "done")

    def test_not_my_pr_unknown(self):
        self.assertEqual(pr_ball.decide(pr(author="alice"), ME)["ball"], "unknown")

    def test_no_reviewers_mine(self):
        r = pr_ball.decide(pr(reviewers=[]), ME)
        self.assertEqual((r["ball"], r["reason"]), ("mine", "レビュアー未設定"))

    def test_no_reaction_theirs(self):
        r = pr_ball.decide(pr(events=[ev("eBASE-Mori", "2026-01-01T00:00:00Z")]), ME)
        self.assertEqual((r["ball"], r["reason"]), ("theirs", "反応待ち"))

    def test_last_other_mine(self):
        events = [ev("alice", "2026-01-01T00:00:00Z", "review", "COMMENTED")]
        self.assertEqual(pr_ball.decide(pr(events=events), ME)["ball"], "mine")

    def test_last_me_theirs(self):
        events = [ev("alice", "2026-01-01T00:00:00Z"), ev("森彪人", "2026-01-02T00:00:00Z")]
        self.assertEqual(pr_ball.decide(pr(events=events), ME)["ball"], "theirs")

    def test_bot_last_mine(self):
        events = [ev("alice", "2026-01-01T00:00:00Z"), ev("eBASE-Mori", "2026-01-02T00:00:00Z"),
                  ev("claude[bot]", "2026-01-03T00:00:00Z")]
        self.assertEqual(pr_ball.decide(pr(events=events), ME)["ball"], "mine")

    def test_tied_latest_with_other_mine(self):
        events = [ev("alice", "2026-01-01T00:00:00Z"), ev("eBASE-Mori", "2026-01-01T00:00:00Z")]
        self.assertEqual(pr_ball.decide(pr(events=events), ME)["ball"], "mine")

    def test_unsorted_events_use_ts(self):
        events = [ev("eBASE-Mori", "2026-01-03T00:00:00Z"), ev("alice", "2026-01-01T00:00:00Z")]
        self.assertEqual(pr_ball.decide(pr(events=events), ME)["ball"], "theirs")


class TestValidate(unittest.TestCase):
    def test_invalid(self):
        for bad in (None, [], {}, {"state": "open"}, pr(state="weird"),
                    {**pr(), "reviewers": "alice"}, {**pr(), "events": [{"user": "a"}]},
                    {**pr(), "events": [ev("a", "not-a-date")]},
                    {**pr(), "events": [ev("a", "2026-01-01T00:00:00")]}):
            self.assertIsNotNone(pr_ball.validate(bad), bad)

    def test_valid(self):
        self.assertIsNone(pr_ball.validate(pr(events=[ev("a", "2026-01-01T00:00:00Z")])))


def completed(out="", rc=0, err=""):
    return subprocess.CompletedProcess([], rc, out, err)


class TestGithub(unittest.TestCase):
    def run_gh(self, answers):
        def fake(cmd, **kw):
            path = cmd[2 if cmd[1] == "api" and not cmd[2].startswith("-") else 0]
            for a in cmd:
                if a.startswith("repos/"):
                    path = a
            for suffix, val in answers.items():
                if path.endswith(suffix):
                    return val if isinstance(val, subprocess.CompletedProcess) else completed(json.dumps(val))
            raise AssertionError(path)
        return fake

    def answers(self):
        return {
            "/pulls/5": {"state": "open", "merged": False, "user": {"login": "eBASE-Mori"},
                         "requested_reviewers": [{"login": "alice"}]},
            "/pulls/5/reviews": [[{"user": {"login": "bob"}, "submitted_at": "2026-01-02T00:00:00Z", "state": "COMMENTED"}]],
            "/issues/5/comments": [[{"user": {"login": "eBASE-Mori"}, "created_at": "2026-01-03T00:00:00Z"}]],
            "/pulls/5/comments": [[]],
        }

    def test_fetch_ok(self):
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch("subprocess.run", side_effect=self.run_gh(self.answers())):
            r = pr_ball.run_github("epc#5", ME)
        self.assertEqual(r["ref"], "epc#5")
        self.assertEqual(r["ball"], "theirs")

    def test_reviews_make_reviewer_and_last_other_mine(self):
        a = self.answers()
        a["/pulls/5"]["requested_reviewers"] = []
        a["/issues/5/comments"] = [[]]
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch("subprocess.run", side_effect=self.run_gh(a)):
            r = pr_ball.run_github("epc#5", ME)
        self.assertEqual(r["ball"], "mine")

    def test_bot_review_not_reviewer(self):
        a = self.answers()
        a["/pulls/5"]["requested_reviewers"] = [{"login": "copilot", "type": "Bot"}]
        a["/pulls/5/reviews"] = [[{"user": {"login": "claude[bot]", "type": "Bot"},
                                   "submitted_at": "2026-01-02T00:00:00Z", "state": "COMMENTED"}]]
        a["/issues/5/comments"] = [[]]
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch("subprocess.run", side_effect=self.run_gh(a)):
            r = pr_ball.run_github("epc#5", ME)
        self.assertEqual((r["ball"], r["reason"]), ("mine", "レビュアー未設定"))

    def test_requested_team_counts(self):
        a = self.answers()
        a["/pulls/5"]["requested_reviewers"] = []
        a["/pulls/5"]["requested_teams"] = [{"slug": "core"}]
        a["/pulls/5/reviews"] = [[]]
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch("subprocess.run", side_effect=self.run_gh(a)):
            r = pr_ball.run_github("epc#5", ME)
        self.assertEqual((r["ball"], r["reason"]), ("theirs", "反応待ち"))

    def test_null_user_is_ghost_other(self):
        a = self.answers()
        a["/issues/5/comments"] = [[{"user": None, "created_at": "2026-01-04T00:00:00Z"}]]
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch("subprocess.run", side_effect=self.run_gh(a)):
            r = pr_ball.run_github("epc#5", ME)
        self.assertEqual(r["ball"], "mine")

    def test_mixed_bad_timestamps_unknown(self):
        for bad in ("2026-01-04T00:00:00", 12345):
            a = self.answers()
            a["/issues/5/comments"] = [[{"user": {"login": "x"}, "created_at": bad}]]
            with mock.patch.object(pr_ball, "get_token", return_value="t"), \
                 mock.patch("subprocess.run", side_effect=self.run_gh(a)):
                r = pr_ball.run_github("epc#5", ME)
            self.assertEqual(r["ball"], "unknown", bad)

    def test_unexpected_exception_unknown(self):
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch.object(pr_ball, "fetch_pr", side_effect=TypeError("x")):
            self.assertEqual(pr_ball.run_github("epc#5", ME)["ball"], "unknown")

    def test_merged(self):
        a = self.answers()
        a["/pulls/5"]["state"] = "closed"
        a["/pulls/5"]["merged"] = True
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch("subprocess.run", side_effect=self.run_gh(a)):
            self.assertEqual(pr_ball.run_github("epc#5", ME)["ball"], "done")

    def test_fetch_failure_unknown(self):
        a = self.answers()
        a["/pulls/5/reviews"] = completed("", 1, "boom")
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch("subprocess.run", side_effect=self.run_gh(a)):
            r = pr_ball.run_github("epc#5", ME)
        self.assertEqual(r["ball"], "unknown")

    def test_timeout_unknown(self):
        with mock.patch.object(pr_ball, "get_token", return_value="t"), \
             mock.patch("subprocess.run", side_effect=subprocess.TimeoutExpired("gh", 1)):
            self.assertEqual(pr_ball.run_github("epc#5", ME)["ball"], "unknown")

    def test_no_token_unknown(self):
        with mock.patch.object(pr_ball, "get_token", return_value=None):
            self.assertEqual(pr_ball.run_github("epc#5", ME)["ball"], "unknown")

    def test_bad_ref_unknown(self):
        for ref in ("zzz#5", "epc5", "epc#x"):
            self.assertEqual(pr_ball.run_github(ref, ME)["ball"], "unknown")


class TestCli(unittest.TestCase):
    def run_main(self, argv, stdin="", env=None):
        out = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO(stdin)), mock.patch("sys.stdout", out), \
             mock.patch("sys.stderr", io.StringIO()), mock.patch.dict(os.environ, env or {}):
            rc = pr_ball.main(argv)
        return rc, json.loads(out.getvalue())

    def test_from_json(self):
        rc, o = self.run_main(["--from-json"], json.dumps(pr(reviewers=[])))
        self.assertEqual((rc, o["ref"], o["ball"]), (0, None, "mine"))

    def test_from_json_invalid(self):
        rc, o = self.run_main(["--from-json"], "{not json")
        self.assertEqual((rc, o["ball"]), (0, "unknown"))
        rc, o = self.run_main(["--from-json"], "{}")
        self.assertEqual((rc, o["ball"]), (0, "unknown"))

    def test_todo_me_env(self):
        p = pr(author="zed", reviewers=[])
        rc, o = self.run_main(["--from-json"], json.dumps(p), env={"TODO_ME": "zed, y"})
        self.assertEqual(o["ball"], "mine")


if __name__ == "__main__":
    unittest.main()
