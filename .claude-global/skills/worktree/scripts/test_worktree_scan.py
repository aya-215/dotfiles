import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import worktree_scan  # noqa: E402


class CandidateDirsTest(unittest.TestCase):
    def test_extra_repos_are_candidates(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIn(tmp, worktree_scan.candidate_dirs([], [tmp]))

    def test_missing_extra_repo_ignored(self):
        self.assertNotIn("/nonexistent/repo", worktree_scan.candidate_dirs([], ["/nonexistent/repo"]))


if __name__ == "__main__":
    unittest.main()
