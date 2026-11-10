import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from origin import origin_of


def git(repo, *args):
    subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args],
        check=True, capture_output=True,
    )


class OriginTest(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.repo = Path(self._td.name)
        git(self.repo, "init", "-q")
        self.f = self.repo / "todo.md"

    def tearDown(self):
        self._td.cleanup()

    def commit(self, text, msg):
        self.f.write_text(text)
        git(self.repo, "add", "todo.md")
        git(self.repo, "commit", "-q", "-m", msg)

    def test_origin_ai(self):
        self.commit("- [ ] human one\n", "todo: 2026-01-01 10:00")
        self.commit("- [ ] human one\n- [ ] ai one\n", "todo(ai): add")
        self.commit("- [ ] ai one\n\n- [ ] human one\n", "todo: 2026-01-02 10:00")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "ai")

    def test_origin_human(self):
        self.commit("- [ ] human one\n", "todo: 2026-01-01 10:00")
        self.commit("- [ ] human one\n- [ ] ai one\n", "todo(ai): add")
        self.assertEqual(origin_of(self.repo, "todo.md", "human one"), "human")

    def test_origin_duplicate_title_is_human(self):
        self.commit("- [ ] same\n", "todo(ai): add")
        self.commit("- [ ] same\n- [ ] same\n", "todo: 2026-01-02 10:00")
        self.assertEqual(origin_of(self.repo, "todo.md", "same"), "human")

    def test_uncommitted_duplicate_is_human(self):
        self.commit("- [ ] ai one\n", "todo(ai): add")
        self.f.write_text("- [ ] ai one\n- [ ] ai one\n")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "human")

    def test_removed_and_retyped_is_human(self):
        self.commit("- [ ] x\n- [ ] ai one\n", "todo(ai): add")
        self.commit("- [ ] x\n", "todo: 2026-01-02 10:00")
        self.commit("- [ ] x\n- [ ] ai one\n", "todo: 2026-01-03 10:00")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "human")

    def test_invalid_utf8_worktree_is_human(self):
        self.commit("- [ ] ai one\n", "todo(ai): add")
        self.f.write_bytes("- [ ] ai one\n- [ ] 日本語\n".encode("shift_jis"))
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "human")

    def test_invalid_utf8_in_head_too_is_human(self):
        self.f.write_bytes("- [ ] ai one 日本語\n".encode("shift_jis"))
        git(self.repo, "add", "todo.md")
        git(self.repo, "commit", "-q", "-m", "todo(ai): add")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "human")

    def test_unknown_title_is_human(self):
        self.commit("- [ ] a\n", "todo(ai): add")
        self.assertEqual(origin_of(self.repo, "todo.md", "zzz"), "human")


if __name__ == "__main__":
    unittest.main()
