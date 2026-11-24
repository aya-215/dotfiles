import sys
import unittest
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from sessions import git_state, list_sessions, pane_state, pick_claude_pane  # noqa: E402

NOW = datetime.fromisoformat("2026-11-24T16:00:00+09:00")


class PickClaudePaneTest(unittest.TestCase):
    def test_skips_sidebar(self):
        panes = "%1\ttmux-agent-sidebar\t/home/aya\n%2\tclaude\t/home/aya/src/x\n"
        self.assertEqual(pick_claude_pane(panes), {"pane": "%2", "cwd": "/home/aya/src/x"})

    def test_none(self):
        self.assertIsNone(pick_claude_pane("%1\tzsh\t/home/aya\n"))


class PaneStateTest(unittest.TestCase):
    def test_working(self):
        cap = "● 読んでいます\n* 力こそ正義… (1m 0s)\n────\n❯ \n────\n  ⏵⏵ auto mode on · esc to interrupt\n"
        self.assertEqual(pane_state(cap, NOW)["state"], "working")

    def test_idle_minutes_and_tail(self):
        cap = ("コメントの投稿とマージは私がやりますか。\n✻ Cogitated for 8s · done 11:56\n────\n❯ \n────\n"
               "  ⚠ cache-keeper: x\n  󰉋 hankyu | feat\n  5h 3% (16:40)\n  ⏵⏵ auto mode on (shift+tab to cycle)\n")
        st = pane_state(cap, NOW)
        self.assertEqual((st["state"], st["idle_since"], st["idle_minutes"]), ("idle", "11:56", 244))
        self.assertEqual(st["tail"][-1], "✻ Cogitated for 8s · done 11:56")
        self.assertNotIn("❯", "".join(st["tail"]))

    def test_idle_across_midnight(self):
        st = pane_state("✻ done 23:50\n", datetime.fromisoformat("2026-11-25T00:10:00+09:00"))
        self.assertEqual(st["idle_minutes"], 20)


class GitStateTest(unittest.TestCase):
    def test_dirty_and_ahead(self):
        self.assertEqual(git_state("## feat/x...origin/feat/x [ahead 2]\n M a.py\n?? b.py\n"),
                         {"branch": "feat/x", "dirty": 2, "ahead": 2})

    def test_not_git(self):
        self.assertIsNone(git_state(None))


class ListSessionsTest(unittest.TestCase):
    def test_states(self):
        out = {("tmux", "list-sessions"): "me\nwork\nshell\n",
               ("list-panes", "me"): "%0\tclaude\t/home/aya/memo\n",
               ("list-panes", "work"): "%1\ttmux-agent-sidebar\t/\n%2\tclaude\t/w\n",
               ("list-panes", "shell"): "%3\tzsh\t/\n",
               ("capture-pane", "%2"): "✻ done 15:30\n",
               ("git", "/w"): "## main\n"}

        def run(argv):
            for k, v in out.items():
                if all(x in argv for x in k):
                    return v
            return None

        got = {s["name"]: s for s in list_sessions(run, "%0", NOW)}
        self.assertTrue(got["me"]["self"])
        self.assertEqual(got["work"]["state"], "idle")
        self.assertEqual(got["work"]["idle_minutes"], 30)
        self.assertEqual(got["work"]["git"], {"branch": "main", "dirty": 0, "ahead": 0})
        self.assertEqual(got["shell"]["state"], "no_claude")

    def test_tmux_unavailable(self):
        self.assertIsNone(list_sessions(lambda argv: None, None, NOW))


if __name__ == "__main__":
    unittest.main()
