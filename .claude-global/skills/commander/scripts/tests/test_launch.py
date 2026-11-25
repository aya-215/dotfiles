import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from launch import claude_command, screen_state, validate, wait_ready  # noqa: E402

SHELL = " ~/.dotfiles   main \n❯ claude                                   09:37:29\n"
READY = (" ▐▛███▛█   Claude Code v2.1.331\n ▝▝   ▝▝   ~/.dotfiles\n❯ /color pink\n  ⎿  Session color set to: pink\n"
         "────────────\n❯ Try \"edit summarize.sh to…\"\n────────────\n  ⏵⏵ auto mode on (shift+tab to cycle)\n")
TRUST = ("❯ claude\n────────────\n Accessing workspace:\n /tmp/x\n Quick safety check: Is this a project you created or one you trust?\n"
         " ❯ No, exit\n   Yes, I trust this folder\n Enter to confirm · Esc to cancel\n")


class ScreenStateTest(unittest.TestCase):
    def test_shell_prompt_is_not_ready(self):
        self.assertEqual(screen_state(SHELL), "starting")

    def test_input_box_is_ready(self):
        self.assertEqual(screen_state(READY), "ready")

    def test_trust_dialog(self):
        self.assertEqual(screen_state(TRUST), "trust")


class ValidateTest(unittest.TestCase):
    def test_ok(self):
        self.assertIsNone(validate("pilot-p11", "/pickup p11 返事が来た"))

    def test_bad_name(self):
        for name in ("a.b", "a:b", "a b", ""):
            self.assertIsNotNone(validate(name, "x"))

    def test_newline_in_prompt(self):
        self.assertIsNotNone(validate("s", "1行目\n2行目"))


class ClaudeCommandTest(unittest.TestCase):
    def test_plain(self):
        self.assertEqual(claude_command(None), "claude")

    def test_worktree_pr_is_quoted(self):
        self.assertEqual(claude_command("#1321"), "claude -w '#1321'")


class WaitReadyTest(unittest.TestCase):
    def _run(self, screens):
        it = iter(screens)

        def run(argv):
            if argv[1] == "list-panes":
                return "%1\tzsh\t/x\n%2\tclaude\t/x\n"
            return next(it)
        return run

    def _clock(self):
        t = [0.0]

        def sleep(s):
            t[0] += s
        return sleep, (lambda: t[0])

    def test_waits_until_ready(self):
        sleep, clock = self._clock()
        state, pane, secs = wait_ready(self._run([SHELL, SHELL, READY]), "s", 10, sleep=sleep, clock=clock)
        self.assertEqual((state, pane["pane"], secs), ("ready", "%2", 1.0))

    def test_stops_at_trust(self):
        sleep, clock = self._clock()
        self.assertEqual(wait_ready(self._run([TRUST]), "s", 10, sleep=sleep, clock=clock)[0], "trust")

    def test_timeout(self):
        sleep, clock = self._clock()
        state, _, secs = wait_ready(self._run([SHELL] * 100), "s", 2, sleep=sleep, clock=clock)
        self.assertEqual((state, secs), ("timeout", 2.0))


if __name__ == "__main__":
    unittest.main()
