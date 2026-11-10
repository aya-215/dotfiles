import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import sync_github
import todo_md


def doc(yaru="", matsu="", kanryo=""):
    return todo_md.parse(f"## 確認待ち\n\n## やる\n{yaru}\n## 待ち\n{matsu}\n## 完了\n{kanryo}")


def line(key, url="https://g/1"):
    return f"- [ ] 調査 [{key}]({url})\n"


class BuildOps(unittest.TestCase):
    def ops(self, d, states, pinned=()):
        recs = [{"ref": r, "kind": "revert_move"} for r in pinned]
        return sync_github.build_ops(d, recs, lambda repo, n: states.get((repo, n)))

    def test_merged_moves_to_done(self):
        ops = self.ops(doc(yaru=line("epc#1")), {("ebase-portal-chat", 1): "merged"})
        self.assertEqual(len(ops), 1)
        self.assertEqual((ops[0]["op"], ops[0]["ref"], ops[0]["to"]), ("move", "epc#1", "完了"))
        self.assertIn("https://g/1", ops[0]["reason"])

    def test_closed_in_machi_moves(self):
        ops = self.ops(doc(matsu=line("emm#2")), {("ebase-middleware-mcp", 2): "closed"})
        self.assertEqual([o["ref"] for o in ops], ["emm#2"])

    def test_open_untouched(self):
        self.assertEqual(self.ops(doc(yaru=line("epc#1")), {("ebase-portal-chat", 1): "open"}), [])

    def test_fetch_failure_moves_nothing(self):
        self.assertEqual(self.ops(doc(yaru=line("epc#1")), {}), [])

    def test_pinned_untouched(self):
        ops = self.ops(doc(yaru=line("epc#1")), {("ebase-portal-chat", 1): "merged"}, pinned=["epc#1"])
        self.assertEqual(ops, [])

    def test_pin_on_wait_does_not_block_done(self):
        recs = [{"ref": "epc#1", "kind": "revert_move", "value": "やる", "from": "やる", "to": "待ち"}]
        ops = sync_github.build_ops(doc(yaru=line("epc#1")), recs, lambda r, n: "merged")
        self.assertEqual([(o["ref"], o["to"]) for o in ops], [("epc#1", "完了")])

    def test_pin_on_done_blocks(self):
        recs = [{"ref": "epc#1", "kind": "revert_move", "value": "やる", "from": "やる", "to": "完了"}]
        self.assertEqual(sync_github.build_ops(doc(yaru=line("epc#1")), recs, lambda r, n: "merged"), [])

    def test_gitbucket_keys_ignored(self):
        calls = []
        d = doc(yaru=line("gb:repo#3"))
        ops = sync_github.build_ops(d, [], lambda r, n: calls.append((r, n)) or "merged")
        self.assertEqual((ops, calls), ([], []))

    def test_done_section_ignored(self):
        calls = []
        d = doc(kanryo="- [x] 済 [epc#1](https://g/1) (done: 2026-11-01)\n")
        ops = sync_github.build_ops(d, [], lambda r, n: calls.append(1) or "merged")
        self.assertEqual((ops, calls), ([], []))

    def test_repo_mapping(self):
        self.assertEqual(sync_github.REPOS, {
            "epc": "ebase-portal-chat", "emm": "ebase-middleware-mcp",
            "eae": "eb-api-extended", "eas": "ebase-agent-specs"})


class GhPath(unittest.TestCase):
    def setUp(self):
        import tempfile
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.home = Path(self._t.name)

    def fake_gh(self, d):
        d.mkdir(parents=True)
        gh = d / "gh"
        gh.write_text("#!/bin/sh\n")
        gh.chmod(0o755)
        return gh

    def test_nix_profile_prepended_when_gh_not_on_path(self):
        import shutil
        gh = self.fake_gh(self.home / ".nix-profile" / "bin")
        env = {"PATH": "/nonexistent", "HOME": str(self.home), "USER": "nobody"}
        sync_github.ensure_gh_path(env)
        self.assertEqual(env["PATH"].split(":"),
                         [str(self.home / ".nix-profile" / "bin"), "/etc/profiles/per-user/nobody/bin", "/nonexistent"])
        self.assertEqual(shutil.which("gh", path=env["PATH"]), str(gh))

    def test_user_falls_back_when_unset(self):
        import getpass
        env = {"PATH": "/nonexistent", "HOME": str(self.home)}
        sync_github.ensure_gh_path(env)
        self.assertIn(f"/etc/profiles/per-user/{getpass.getuser()}/bin", env["PATH"].split(":"))

    def test_path_untouched_when_gh_found(self):
        self.fake_gh(self.home / "bin")
        env = {"PATH": str(self.home / "bin"), "HOME": str(self.home)}
        sync_github.ensure_gh_path(env)
        self.assertEqual(env["PATH"], str(self.home / "bin"))


class LoadRecords(unittest.TestCase):
    def test_unrecorded_revert_is_merged(self):
        import subprocess, tempfile
        with tempfile.TemporaryDirectory() as t:
            repo = Path(t)
            todo = repo / "todo.md"

            def commit(text, msg):
                todo.write_text(text, encoding="utf-8")
                subprocess.run(["git", "-C", t, "-c", "user.name=t", "-c", "user.email=t@t", "add", "todo.md"], check=True)
                subprocess.run(["git", "-C", t, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", msg],
                               check=True)

            subprocess.run(["git", "-C", t, "init", "-q"], check=True)
            base = f"## 確認待ち\n\n## やる\n{line('epc#1')}\n## 待ち\n\n## 完了\n"
            commit(base, "todo: base")
            commit(f"## 確認待ち\n\n## やる\n\n## 待ち\n{line('epc#1')}\n## 完了\n", "todo(sync): 移動")
            commit(base, "todo: 戻した")
            recs = sync_github.load_records(todo)
            self.assertTrue(sync_github.decisions.is_pinned(recs, "epc#1", "待ち"))
            self.assertFalse((repo / "todo-decisions.jsonl").exists())


class StateOf(unittest.TestCase):
    def test_states(self):
        f = sync_github.state_from_json
        self.assertEqual(f({"state": "open"}), "open")
        self.assertEqual(f({"state": "closed"}), "closed")
        self.assertEqual(f({"state": "closed", "pull_request": {"merged_at": "2026-01-01T00:00:00Z"}}), "merged")
        self.assertEqual(f({"state": "closed", "pull_request": {"merged_at": None}}), "closed")
        self.assertIsNone(f({"state": "weird"}))
        self.assertIsNone(f([]))


class Main(unittest.TestCase):
    def setUp(self):
        import tempfile
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.todo = Path(self._t.name) / "todo.md"
        self.todo.write_text(f"## 確認待ち\n\n## やる\n{line('epc#1')}\n## 待ち\n\n## 完了\n", encoding="utf-8")

    def run_main(self, token, state, extra=()):
        from unittest import mock
        with mock.patch.object(sync_github, "get_token", return_value=token), \
             mock.patch.object(sync_github, "fetch_state", return_value=state), \
             mock.patch.object(sync_github, "load_records", return_value=[]), \
             mock.patch.object(sync_github.subprocess, "run") as run:
            run.return_value.returncode = 3
            rc = sync_github.main(["--todo", str(self.todo), *extra])
        return rc, run

    def test_token_failure_exits_1_without_apply(self):
        rc, run = self.run_main(None, "merged")
        self.assertEqual(rc, 1)
        run.assert_not_called()

    def test_no_ops_skips_apply(self):
        rc, run = self.run_main("t", "open")
        self.assertEqual(rc, 0)
        run.assert_not_called()

    def test_dry_run_skips_apply(self):
        rc, run = self.run_main("t", "merged", ["--dry-run"])
        self.assertEqual(rc, 0)
        run.assert_not_called()

    def test_apply_exit_code_propagates(self):
        rc, run = self.run_main("t", "merged")
        self.assertEqual(rc, 3)
        self.assertIn("apply.py", run.call_args[0][0][1])


if __name__ == "__main__":
    unittest.main()
