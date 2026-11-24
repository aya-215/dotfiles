import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from worktree_hook import is_personal, new_branch_name, placement, slug  # noqa: E402


def git(cwd, *args) -> str:
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True).stdout.strip()


def make_repo(tmp: Path, origin_url: "str | None" = "git@github.com:ebase-dev/x.git") -> Path:
    """tmp/origin.git（bare、main に1コミット）を作って clone し、clone 先を返す。"""
    tmp.mkdir(parents=True, exist_ok=True)
    seed, bare, clone = tmp / "seed", tmp / "origin.git", tmp / "clone"
    subprocess.run(["git", "init", "-q", "-b", "main", str(seed)], check=True)
    git(seed, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
    subprocess.run(["git", "clone", "-q", "--bare", str(seed), str(bare)], check=True)
    subprocess.run(["git", "clone", "-q", str(bare), str(clone)], check=True)
    git(clone, "config", "user.name", "t")
    git(clone, "config", "user.email", "t@t")
    if origin_url:
        # 表示上の URL を差し替え、fetch は insteadOf で本物の bare へ向ける
        git(clone, "config", f"url.{bare}.insteadOf", origin_url)
        git(clone, "remote", "set-url", "origin", origin_url)
    return clone


class NamingTest(unittest.TestCase):
    def test_slug(self):
        self.assertEqual(slug("feat/1296-mensapo"), "feat-1296-mensapo")

    def test_placement_inside(self):
        self.assertEqual(placement(Path("/home/aya/src/github.com/o/app"), "feat/x", Path("/home/aya")),
                         Path("/home/aya/src/github.com/o/app/.claude/worktrees/feat-x"))

    def test_placement_mnt(self):
        self.assertEqual(placement(Path("/mnt/d/tomcat/webapps/hankyu"), "feat/x", Path("/home/aya")),
                         Path("/home/aya/worktrees/hankyu-feat-x"))

    def test_is_personal(self):
        self.assertTrue(is_personal("git@github-aya215:aya-215/dotfiles.git"))
        self.assertTrue(is_personal("https://github.com/aya-215/x.git"))
        self.assertFalse(is_personal("git@github.com:ebase-dev/ebase-portal-chat.git"))
        self.assertFalse(is_personal(None))

    def test_new_branch_name(self):
        self.assertEqual(new_branch_name("fix/12-a", personal=False), "fix/12-a")
        self.assertEqual(new_branch_name("bold-oak-a3f2", personal=False), "feat/bold-oak-a3f2")
        self.assertEqual(new_branch_name("bold-oak-a3f2", personal=True), "bold-oak-a3f2")
        self.assertEqual(new_branch_name("featx", personal=False), "feat/featx")


class MakeRepoTest(unittest.TestCase):
    def test_make_repo_fetches_through_fake_url(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(Path(tmp), origin_url="git@github-aya215:aya-215/dotfiles.git")
            self.assertEqual(git(repo, "config", "--get", "remote.origin.url"), "git@github-aya215:aya-215/dotfiles.git")
            git(repo, "fetch", "-q", "origin")
            self.assertTrue(git(repo, "rev-parse", "origin/main"))


if __name__ == "__main__":
    unittest.main()
