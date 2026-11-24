import io
import json
import os
import subprocess
from contextlib import redirect_stderr, redirect_stdout
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from worktree_hook import (  # noqa: E402
    HookError, copy_env, create, gh_pr_head, is_personal, link_node_modules, main, new_branch_name, placement, remove,
    slug,
)


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


def branch_of(p: Path) -> str:
    return git(p, "branch", "--show-current")


def rev(p: Path, ref: str) -> str:
    return git(p, "rev-parse", ref)


def upstream_of(p: Path) -> str:
    return git(p, "rev-parse", "--abbrev-ref", "@{upstream}")


def push_branch(repo: Path, branch: str, keep_local: bool = False) -> None:
    git(repo, "branch", branch, "origin/main")
    git(repo, "push", "-q", "origin", branch)
    if not keep_local:
        git(repo, "branch", "-D", branch)


def no_gh(root, number):
    return None


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


class CreateTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.repo = make_repo(self.tmp / "r")
        self.home = self.tmp / "home"

    def tearDown(self):
        self._tmp.cleanup()

    def test_new_feat_branch_from_origin_main(self):
        p = create("bold-oak-a3f2", self.repo, home=self.home, gh_head=no_gh)
        self.assertEqual(p, self.repo / ".claude/worktrees/bold-oak-a3f2")
        self.assertEqual(branch_of(p), "feat/bold-oak-a3f2")
        self.assertEqual(rev(p, "HEAD"), rev(self.repo, "origin/main"))

    def test_known_type_kept(self):
        self.assertEqual(branch_of(create("fix/9-a", self.repo, home=self.home, gh_head=no_gh)), "fix/9-a")

    def test_existing_remote_branch_tracked(self):
        push_branch(self.repo, "feat/old")
        p = create("feat/old", self.repo, home=self.home, gh_head=no_gh)
        self.assertEqual(branch_of(p), "feat/old")
        self.assertEqual(upstream_of(p), "origin/feat/old")

    def test_existing_local_branch_opened(self):
        git(self.repo, "branch", "feat/local-only", "origin/main")
        p = create("feat/local-only", self.repo, home=self.home, gh_head=no_gh)
        self.assertEqual(branch_of(p), "feat/local-only")

    def test_github_pr_opens_head_branch(self):
        push_branch(self.repo, "feat/pr-head")
        p = create("pr-77", self.repo, home=self.home, gh_head=lambda r, n: "feat/pr-head" if n == 77 else None)
        self.assertEqual(branch_of(p), "feat/pr-head")
        self.assertEqual(p, self.repo / ".claude/worktrees/pr-77")

    def test_pr_fallback_to_pull_ref(self):
        bare = self.tmp / "r" / "origin.git"
        git(bare, "update-ref", "refs/pull/5/head", git(bare, "rev-parse", "main"))
        p = create("pr-5", self.repo, home=self.home, gh_head=no_gh)
        self.assertEqual(branch_of(p), "pr-5")

    def test_branch_checked_out_elsewhere_fails(self):
        git(self.repo, "checkout", "-q", "-b", "feat/busy")
        with self.assertRaises(HookError) as cm:
            create("feat/busy", self.repo, home=self.home, gh_head=no_gh)
        self.assertIn(str(self.repo), str(cm.exception))

    def test_reenter_returns_same_path(self):
        a = create("feat/again", self.repo, home=self.home, gh_head=no_gh)
        self.assertEqual(create("feat/again", self.repo, home=self.home, gh_head=no_gh), a)

    def test_leftover_dir_fails(self):
        (self.repo / ".claude/worktrees/feat-left").mkdir(parents=True)
        with self.assertRaises(HookError):
            create("feat/left", self.repo, home=self.home, gh_head=no_gh)

    def test_fetch_failure_continues(self):
        git(self.repo, "config", "--unset-all", f"url.{self.tmp / 'r' / 'origin.git'}.insteadOf")
        git(self.repo, "remote", "set-url", "origin", str(self.tmp / "nowhere.git"))
        p = create("feat/offline", self.repo, home=self.home, gh_head=no_gh)
        self.assertTrue(p.is_dir())
        self.assertEqual(rev(p, "HEAD"), rev(self.repo, "origin/main"))

    def test_personal_repo_keeps_name(self):
        repo = make_repo(self.tmp / "p", origin_url="git@github-aya215:aya-215/dotfiles.git")
        self.assertEqual(branch_of(create("bold-oak", repo, home=self.home, gh_head=no_gh)), "bold-oak")

    def test_no_origin_uses_head(self):
        plain = self.tmp / "plain"
        subprocess.run(["git", "init", "-q", "-b", "main", str(plain)], check=True)
        git(plain, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
        p = create("feat/local", plain, home=self.home, gh_head=no_gh)
        self.assertEqual(rev(p, "HEAD"), rev(plain, "HEAD"))

    def test_mnt_root_goes_to_home_worktrees(self):
        import worktree_hook
        orig = worktree_hook.placement
        worktree_hook.placement = lambda root, name, home: home / "worktrees" / f"{root.name}-{slug(name)}"
        try:
            p = create("feat/m", self.repo, home=self.home, gh_head=no_gh)
        finally:
            worktree_hook.placement = orig
        self.assertEqual(p, self.home / "worktrees" / "clone-feat-m")
        self.assertTrue(p.is_dir())


class CopyTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.root = self.tmp / "root"
        self.wt = self.tmp / "wt"
        (self.root / "apps/ui").mkdir(parents=True)
        (self.wt / "apps/ui").mkdir(parents=True)

    def tearDown(self):
        self._tmp.cleanup()

    def put(self, rel, text="x"):
        f = self.root / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text)

    def test_copy_env_same_relative_paths(self):
        for rel in ["apps/ui/.env.local", ".env.keys", "node_modules/x/.env.local", ".claude/worktrees/y/.env.local"]:
            self.put(rel)
        self.assertEqual(sorted(copy_env(self.root, self.wt)), [".env.keys", "apps/ui/.env.local"])
        self.assertTrue((self.wt / "apps/ui/.env.local").exists())
        self.assertFalse((self.wt / "node_modules").exists())

    def test_link_node_modules_only_with_package_lock(self):
        self.put("node_modules/a/index.js")
        self.assertEqual(link_node_modules(self.root, self.wt), [])

    def test_link_node_modules_hardlinks(self):
        self.put("package-lock.json", "{}")
        self.put("node_modules/a/index.js")
        self.put("apps/ui/node_modules/b.js")
        self.put("apps/gone/node_modules/c.js")
        self.assertEqual(sorted(link_node_modules(self.root, self.wt)), ["apps/ui/node_modules", "node_modules"])
        self.assertEqual(os.stat(self.root / "node_modules/a/index.js").st_ino,
                         os.stat(self.wt / "node_modules/a/index.js").st_ino)

    def test_link_failure_cleans_and_continues(self):
        self.put("package-lock.json", "{}")
        self.put("node_modules/a/index.js")

        def cp_fail(src, dst):
            dst.mkdir(parents=True)
            (dst / "partial").write_text("x")
            return False
        self.assertEqual(link_node_modules(self.root, self.wt, cp=cp_fail), [])
        self.assertFalse((self.wt / "node_modules").exists())

    def test_create_copies_env(self):
        repo = make_repo(self.tmp / "r")
        (repo / ".env.local").write_text("SECRET=1")
        p = create("feat/env", repo, home=self.tmp / "home", gh_head=no_gh)
        self.assertEqual((p / ".env.local").read_text(), "SECRET=1")


def branch_exists(repo: Path, branch: str) -> bool:
    return subprocess.run(["git", "-C", str(repo), "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}"],
                          capture_output=True).returncode == 0


def commit_in(p: Path, name: str) -> None:
    (p / name).write_text("x")
    git(p, "add", name)
    git(p, "commit", "-q", "-m", name)


class RemoveTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.repo = make_repo(self.tmp / "r")
        self.home = self.tmp / "home"

    def tearDown(self):
        self._tmp.cleanup()

    def test_remove_deletes_dir_and_merged_branch(self):
        p = create("feat/done", self.repo, home=self.home, gh_head=no_gh)
        self.assertEqual(remove(p), 0)
        self.assertFalse(p.exists())
        self.assertFalse(branch_exists(self.repo, "feat/done"))

    def test_remove_keeps_branch_with_local_only_commit(self):
        p = create("feat/wip", self.repo, home=self.home, gh_head=no_gh)
        commit_in(p, "a.txt")
        self.assertEqual(remove(p), 0)
        self.assertFalse(p.exists())
        self.assertTrue(branch_exists(self.repo, "feat/wip"))

    def test_remove_with_uncommitted_changes(self):
        p = create("feat/dirty", self.repo, home=self.home, gh_head=no_gh)
        (p / "u.txt").write_text("x")
        self.assertEqual(remove(p), 0)
        self.assertFalse(p.exists())

    def test_remove_missing_path_is_ok(self):
        self.assertEqual(remove(self.tmp / "gone"), 0)

    def test_main_create_prints_only_path(self):
        out = io.StringIO()
        with redirect_stdout(out):
            rc = main(["create"], stdin=io.StringIO(json.dumps({"name": "feat/cli", "cwd": str(self.repo)})))
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue().strip().splitlines(), [str(self.repo / ".claude/worktrees/feat-cli")])

    def test_main_create_with_args(self):
        out = io.StringIO()
        with redirect_stdout(out):
            rc = main(["create", "--name", "feat/args", "--cwd", str(self.repo)], stdin=io.StringIO(""))
        self.assertEqual(rc, 0)
        self.assertTrue(Path(out.getvalue().strip()).is_dir())

    def test_main_create_error_exit_1(self):
        git(self.repo, "checkout", "-q", "-b", "feat/busy")
        out = io.StringIO()
        with redirect_stdout(out):
            rc = main(["create"], stdin=io.StringIO(json.dumps({"name": "feat/busy", "cwd": str(self.repo)})))
        self.assertEqual(rc, 1)
        self.assertEqual(out.getvalue(), "")

    def test_main_remove_from_json(self):
        p = create("feat/rm", self.repo, home=self.home, gh_head=no_gh)
        rc = main(["remove"], stdin=io.StringIO(json.dumps({"worktree_path": str(p)})))
        self.assertEqual(rc, 0)
        self.assertFalse(p.exists())


class ReviewFixesTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.repo = make_repo(self.tmp / "r")
        self.bare = self.tmp / "r" / "origin.git"
        self.home = self.tmp / "home"

    def tearDown(self):
        self._tmp.cleanup()

    def test_recreating_pr_branch_keeps_local_commits(self):
        git(self.bare, "update-ref", "refs/pull/7/head", git(self.bare, "rev-parse", "main"))
        p = create("pr-7", self.repo, home=self.home, gh_head=no_gh)
        commit_in(p, "fix.txt")
        mine = rev(p, "HEAD")
        remove(p)
        p2 = create("pr-7", self.repo, home=self.home, gh_head=no_gh)
        self.assertEqual(branch_of(p2), "pr-7")
        self.assertEqual(rev(p2, "HEAD"), mine)

    def test_pr_head_missing_on_origin_falls_back_to_pull_ref(self):
        git(self.bare, "update-ref", "refs/pull/8/head", git(self.bare, "rev-parse", "main"))
        p = create("pr-8", self.repo, home=self.home, gh_head=lambda r, n: "contributor-branch")
        self.assertEqual(branch_of(p), "pr-8")
        self.assertFalse(branch_exists(self.repo, "contributor-branch"))

    def test_hanging_fetch_times_out_and_continues(self):
        import time
        import worktree_hook
        git(self.repo, "config", "protocol.ext.allow", "always")
        git(self.repo, "config", "--unset-all", f"url.{self.bare}.insteadOf")
        git(self.repo, "remote", "set-url", "origin", "ext::sh -c 'sleep 30'")
        orig = worktree_hook.FETCH_TIMEOUT
        worktree_hook.FETCH_TIMEOUT = 2
        try:
            t0 = time.monotonic()
            p = create("feat/hang", self.repo, home=self.home, gh_head=no_gh)
            self.assertLess(time.monotonic() - t0, 15)
        finally:
            worktree_hook.FETCH_TIMEOUT = orig
        self.assertTrue(p.is_dir())

    def test_cross_device_skips_hardlink(self):
        root, wt = self.tmp / "root", self.tmp / "wt"
        (root / "node_modules/a").mkdir(parents=True)
        (root / "package-lock.json").write_text("{}")
        wt.mkdir()
        calls = []
        got = link_node_modules(root, wt, cp=lambda s, d: calls.append(s) or True, same_device=lambda a, b: False)
        self.assertEqual(got, [])
        self.assertEqual(calls, [])

    def test_broken_env_symlink_does_not_fail_create(self):
        (self.repo / ".env.local").symlink_to(self.tmp / "missing-target")
        p = create("feat/brokenenv", self.repo, home=self.home, gh_head=no_gh)
        self.assertTrue(p.is_dir())


def fake_gh(good_token):
    """good_token の GH_TOKEN のときだけ PR の head を返す gh。"""
    def run(cmd, **kw):
        if cmd[:3] == ["gh", "auth", "token"]:
            return subprocess.CompletedProcess(cmd, 0, f"tok-{cmd[-1]}\n", "")
        if cmd[:3] == ["gh", "pr", "view"]:
            ok = (kw.get("env") or {}).get("GH_TOKEN") == good_token
            return subprocess.CompletedProcess(cmd, 0 if ok else 1, "feat/x\n" if ok else "", "" if ok else "GraphQL: Could not resolve")
        raise AssertionError(cmd)
    return run


class GhAccountTest(unittest.TestCase):
    def test_falls_back_to_other_account(self):
        self.assertEqual(gh_pr_head(Path("."), 1, run=fake_gh("tok-eBASE-Mori"), accounts=["aya-215", "eBASE-Mori"]), "feat/x")

    def test_active_account_tried_first(self):
        calls = []

        def run(cmd, **kw):
            calls.append(cmd[:3])
            return subprocess.CompletedProcess(cmd, 0, "feat/y\n", "")
        self.assertEqual(gh_pr_head(Path("."), 1, run=run, accounts=["aya-215"]), "feat/y")
        self.assertEqual(calls, [["gh", "pr", "view"]])

    def test_all_accounts_fail(self):
        self.assertIsNone(gh_pr_head(Path("."), 1, run=fake_gh("nope"), accounts=["aya-215", "eBASE-Mori"]))

    def test_pr_fallback_warns_push_does_not_update_pr(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            repo = make_repo(tmp / "r")
            bare = tmp / "r" / "origin.git"
            git(bare, "update-ref", "refs/pull/9/head", git(bare, "rev-parse", "main"))
            err = io.StringIO()
            with redirect_stderr(err):
                create("pr-9", repo, home=tmp / "home", gh_head=no_gh)
            self.assertIn("PR は更新されません", err.getvalue())


if __name__ == "__main__":
    unittest.main()
