import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sync_main import main, sync  # noqa: E402
from test_worktree_hook import commit_in, git, make_repo  # noqa: E402


class SyncTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.repo = make_repo(self.tmp / "r", origin_url=None)
        git(self.repo, "config", "pull.rebase", "true")
        self.n = 0

    def tearDown(self):
        self._tmp.cleanup()

    def push_remote(self, name: str, content: str = "remote") -> None:
        self.n += 1
        other = self.tmp / f"other{self.n}"
        subprocess.run(["git", "clone", "-q", str(self.tmp / "r" / "origin.git"), str(other)], check=True)
        git(other, "config", "user.name", "t")
        git(other, "config", "user.email", "t@t")
        (other / name).write_text(content)
        git(other, "add", name)
        git(other, "commit", "-q", "-m", name)
        git(other, "push", "-q", "origin", "main")

    def commit_and_push(self, name: str) -> None:
        commit_in(self.repo, name)
        git(self.repo, "push", "-q", "origin", "main")

    def test_up_to_date(self):
        self.assertEqual(sync(self.repo), (0, "最新"))

    def test_advances_keeping_unrelated_local_change(self):
        self.commit_and_push("a.txt")
        (self.repo / "a.txt").write_text("local edit")
        (self.repo / "u.txt").write_text("untracked")
        self.push_remote("b.txt")
        code, line = sync(self.repo)
        self.assertEqual(code, 0)
        self.assertRegex(line, r"^進めた: [0-9a-f]{7} → [0-9a-f]{7}（1 コミット）$")
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), git(self.repo, "rev-parse", "origin/main"))
        self.assertEqual((self.repo / "a.txt").read_text(), "local edit")
        self.assertTrue((self.repo / "u.txt").exists())
        self.assertTrue((self.repo / "b.txt").exists())

    def test_skips_when_not_on_main(self):
        git(self.repo, "checkout", "-q", "-b", "other")
        self.assertEqual(sync(self.repo), (3, "本体は other を使用中なので進めない"))

    def test_skips_unpushed_local_main(self):
        commit_in(self.repo, "local.txt")
        self.push_remote("b.txt")
        self.assertEqual(sync(self.repo), (3, "本体の main に未 push のコミットが 1 件あるので進めない"))

    def test_reports_git_refusal_on_overlap(self):
        self.commit_and_push("a.txt")
        self.push_remote("a.txt", "remote edit")
        (self.repo / "a.txt").write_text("local edit")
        before = git(self.repo, "rev-parse", "HEAD")
        code, line = sync(self.repo)
        self.assertEqual(code, 3)
        self.assertTrue(line.startswith("git が早送りを断った: "), line)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), before)
        self.assertEqual((self.repo / "a.txt").read_text(), "local edit")

    def test_fetch_failure(self):
        git(self.repo, "remote", "set-url", "origin", str(self.tmp / "missing.git"))
        code, line = sync(self.repo)
        self.assertEqual(code, 1)
        self.assertTrue(line.startswith("fetch に失敗: "), line)

    def test_main_prints_line(self):
        out = io.StringIO()
        with redirect_stdout(out):
            rc = main(["--repo", str(self.repo)])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue(), "最新\n")


if __name__ == "__main__":
    unittest.main()
