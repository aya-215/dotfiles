import copy
import fcntl
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import apply
import todo_md
from apply import ChangeError, apply_changes, confirm_edit_errors, split_archive, validate

APPLY = str(HERE / "apply.py")
TODAY = "2026-11-10"

BASE = """# TODO

## 確認待ち

## やる
- [ ] インターン資料修正
- [ ] PR レビュー [epc#1163](https://github.com/x/epc/pull/1163) — next: 読む
- [ ] 調査 [epc#1202](https://github.com/x/epc/issues/1202)

## 待ち
- [ ] 坂西さんの対応

## 完了
- [x] 済んだ [epc#1100](https://github.com/x/epc/pull/1100) (done: 2026-11-01)
"""


REOPEN_SWAP = """## 確認待ち

## やる
- [ ] レビュー [epc#2](https://g/2)

## 待ち

## 完了
- [x] レビュー [epc#1](https://g/1) (done: 2026-11-05)
"""


def human(_title):
    return "human"


def ai(_title):
    return "ai"


def titles(doc, section):
    return [it.title for it in doc.sections[section]]


def git(repo, *args):
    return subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args],
        check=True, capture_output=True, text=True,
    ).stdout


class ApplyChangesTest(unittest.TestCase):
    def setUp(self):
        self.doc = todo_md.parse(BASE)

    def run_ops(self, ops, source="ai", **extra):
        changes = {"source": source, "ops": ops, **extra}
        return apply_changes(self.doc, changes, human, TODAY)

    def test_add_goes_to_section_with_link_and_next(self):
        new, body = self.run_ops([{
            "op": "add", "section": "待ち", "key": "epc#1300",
            "url": "https://github.com/x/epc/pull/1300", "title": "新規",
            "next": "返事を待つ", "reason": "PR が来た",
        }])
        it = new.sections["待ち"][-1]
        self.assertEqual((it.title, it.key, it.url, it.next), (
            "新規", "epc#1300", "https://github.com/x/epc/pull/1300", "返事を待つ"))
        self.assertFalse(it.done)
        self.assertTrue(any("PR が来た" in l and "pull/1300" in l for l in body))

    def test_add_duplicate_key_is_skipped(self):
        new, body = self.run_ops([{
            "op": "add", "section": "やる", "key": "epc#1163",
            "url": "https://github.com/x/epc/pull/1163", "title": "重複", "reason": "r",
        }])
        self.assertEqual(len(new.sections["やる"]), 3)
        self.assertTrue(any(l.startswith("skip: duplicate") for l in body))

    def test_move_to_done_adds_date(self):
        new, _ = self.run_ops([{"op": "move", "ref": "epc#1202", "to": "完了", "reason": "closed"}])
        it = new.sections["完了"][0]
        self.assertEqual(it.key, "epc#1202")
        self.assertTrue(it.done)
        self.assertEqual(it.done_date, TODAY)
        self.assertNotIn("調査", titles(new, "やる"))

    def test_move_to_wait_appends_at_end(self):
        new, _ = self.run_ops([{"op": "move", "ref": "title:インターン資料修正", "to": "待ち", "reason": "r"}])
        self.assertEqual(titles(new, "待ち"), ["坂西さんの対応", "インターン資料修正"])

    def test_set_next_replaces_only_next(self):
        new, _ = self.run_ops([{"op": "set_next", "ref": "epc#1163", "next": "直して push", "reason": "r"}])
        it = new.sections["やる"][1]
        self.assertEqual((it.title, it.key, it.url, it.next), (
            "PR レビュー", "epc#1163", "https://github.com/x/epc/pull/1163", "直して push"))

    def test_attach_to_human_line_keeps_title(self):
        new, _ = self.run_ops([{
            "op": "attach", "ref": "title:インターン資料修正", "key": "rc:abc",
            "url": "https://chat.example/abc", "next": "資料を直す", "reason": "RC で依頼",
        }])
        it = new.sections["やる"][0]
        self.assertEqual(it.title, "インターン資料修正")
        self.assertEqual((it.key, it.url, it.next), ("rc:abc", "https://chat.example/abc", "資料を直す"))
        self.assertEqual(validate(self.doc, new, human, "ai"), [])

    def test_attach_never_overwrites_existing_link(self):
        new, body = self.run_ops([{
            "op": "attach", "ref": "epc#1163", "key": "rc:zzz", "url": "https://chat.example/zzz",
            "reason": "r",
        }])
        self.assertEqual(new.sections["やる"][1].key, "epc#1163")
        self.assertTrue(any(l.startswith("skip: already linked") for l in body))

    def test_unknown_ref(self):
        new, body = self.run_ops([
            {"op": "move", "ref": "epc#9999", "to": "完了", "reason": "r"},
            {"op": "set_next", "ref": "epc#1163", "next": "n2", "reason": "r"},
        ])
        self.assertIn("skip: unknown ref epc#9999", body)
        self.assertEqual(new.sections["やる"][1].next, "n2")

    def test_ambiguous_ref_is_skipped(self):
        self.doc = todo_md.parse(BASE.replace("- [ ] 坂西さんの対応", "- [ ] インターン資料修正"))
        new, body = self.run_ops([{"op": "move", "ref": "title:インターン資料修正", "to": "完了", "reason": "r"}])
        self.assertIn("skip: ambiguous ref title:インターン資料修正", body)
        self.assertEqual(len(new.sections["完了"]), 1)

    def test_order_keeps_unlisted_relative(self):
        new, _ = self.run_ops([{"op": "order", "section": "やる", "refs": ["epc#1202", "epc#9999"]}])
        self.assertEqual(titles(new, "やる"), ["調査", "インターン資料修正", "PR レビュー"])

    def test_input_doc_not_mutated(self):
        before = copy.deepcopy(self.doc)
        self.run_ops([
            {"op": "move", "ref": "epc#1202", "to": "完了", "reason": "r"},
            {"op": "set_next", "ref": "epc#1163", "next": "x", "reason": "r"},
        ])
        self.assertEqual(self.doc, before)

    def test_confirm_rendered(self):
        self.doc.confirm = ["1. 古い問い", "   事実: f", "   選択: A x", "   回答:"]
        new, _ = self.run_ops([], confirm=[
            {"ref": "epc#1202", "kind": "policy", "question": "方針を決める", "facts": "PR が2本",
             "options": [{"label": "A", "text": "まとめる", "recommended": True},
                         {"label": "B", "text": "分ける"}]},
            {"ref": "title:インターン資料修正", "kind": "is_task", "question": "タスク？",
             "facts": "依頼あり", "options": [{"label": "A", "text": "はい"}]},
        ])
        self.assertEqual(new.confirm, [
            "1. 方針を決める",
            "   事実: PR が2本",
            "   選択: A まとめる（おすすめ） / B 分ける",
            "   回答:",
            "2. タスク？",
            "   事実: 依頼あり",
            "   選択: A はい",
            "   回答:",
        ])

    def test_numbered_free_text_in_confirm_rejected(self):
        self.doc.confirm = ["1. 古い問い", "   事実: f", "   選択: A x", "   回答:", "2. 来週までに自分でやるメモ"]
        with self.assertRaises(ChangeError):
            self.run_ops([], confirm=[])

    def test_text_appended_inside_block_rejected(self):
        self.doc.confirm = ["1. 古い問い", "   事実: f", "   選択: A x", "   人の補足", "   回答:"]
        with self.assertRaises(ChangeError):
            self.run_ops([], confirm=[])

    def test_answers_must_match_answered_verbatim(self):
        self.doc.confirm = ["1. q1", "   事実: f", "   選択: A x", "   回答: A", "",
                            "2. q2", "   事実: f", "   選択: B y", "   回答: B にする、理由は来週"]
        for answered in ([None, None], [{"answer": "A"}, {"answer": "B"}], [{"answer": "A"}, {"answer": "A"}]):
            with self.assertRaises(ChangeError, msg=answered):
                self.run_ops([], confirm=[], answered=answered)
        new, body = self.run_ops([], confirm=[], answered=[
            {"ref": "epc#1", "kind": "policy", "answer": "B にする、理由は来週"},
            {"ref": "epc#2", "kind": "policy", "answer": "A"}])
        self.assertEqual(new.confirm, [])
        self.assertIn("answer: 2. q2", body)
        self.assertIn("   回答: B にする、理由は来週", body)

    def test_reopen_move_rejected_before_validate(self):
        doc = todo_md.parse(REOPEN_SWAP)
        with self.assertRaises(ChangeError):
            apply_changes(doc, {"source": "sync", "ops": [
                {"op": "move", "ref": "epc#1", "to": "やる"},
                {"op": "move", "ref": "epc#2", "to": "完了"}]}, human, TODAY)

    def test_confirm_absent_keeps_section(self):
        self.doc.confirm = ["1. 問い", "   回答: A"]
        new, _ = self.run_ops([], source="sync")
        self.assertEqual(new.confirm, ["1. 問い", "   回答: A"])


class ValidateTest(unittest.TestCase):
    def setUp(self):
        self.before = todo_md.parse(BASE)
        self.after = copy.deepcopy(self.before)

    def test_reject_human_title_change(self):
        self.after.sections["やる"][0].title = "インターン資料修正（AI が直した）"
        self.assertTrue(validate(self.before, self.after, human, "ai"))
        self.assertEqual(validate(self.before, self.after, ai, "ai"), [])

    def test_reject_line_loss(self):
        del self.after.sections["待ち"][0]
        self.assertTrue(validate(self.before, self.after, ai, "ai"))

    def test_reject_reopen_direct(self):
        it = self.after.sections["完了"].pop(0)
        it.done, it.done_date = False, None
        self.after.sections["やる"].append(it)
        self.assertTrue(validate(self.before, self.after, human, "sync"))

    def test_reopen_swap_same_title_rejected(self):
        before = todo_md.parse(REOPEN_SWAP)
        after = copy.deepcopy(before)
        e1, e2 = after.sections["完了"].pop(0), after.sections["やる"].pop(0)
        e1.done, e1.done_date = False, None
        e2.done, e2.done_date = True, TODAY
        after.sections["やる"].append(e1)
        after.sections["完了"].append(e2)
        self.assertTrue(validate(before, after, human, "sync"))

    def test_attach_to_done_keyless_line_is_not_reopen(self):
        before = todo_md.parse(BASE.replace("(done: 2026-11-01)\n", "(done: 2026-11-01)\n- [x] 鍵なし (done: 2026-11-02)\n"))
        after = copy.deepcopy(before)
        after.sections["完了"][1].key, after.sections["完了"][1].url = "rc:a", "https://c/a"
        self.assertEqual(validate(before, after, human, "ai"), [])

    def test_confirm_edit_errors(self):
        written = ["1. q", "   事実: f", "   選択: A x", "   回答:"]
        self.assertEqual(confirm_edit_errors(["1. q", "   事実: f", "   選択: A x", "   回答: A"], written), [])
        self.assertEqual(confirm_edit_errors([], written), [])
        self.assertTrue(confirm_edit_errors(["1. q", "   事実: f（人が追記）", "   選択: A x", "   回答:"], written))
        self.assertTrue(confirm_edit_errors(["1. q", "   事実: f", "   選択: A x", "   回答:"], []))

    def test_duplicate_human_titles_count(self):
        before = todo_md.parse(BASE.replace("- [ ] 坂西さんの対応", "- [ ] インターン資料修正"))
        after = copy.deepcopy(before)
        after.sections["待ち"][0].title = "別物"
        self.assertTrue(validate(before, after, human, "ai"))

    def test_split_archive_31_vs_30_days(self):
        doc = todo_md.parse(BASE.replace(
            "(done: 2026-11-01)\n",
            "(done: 2026-11-01)\n- [x] 古い (done: 2026-10-10)\n- [x] ぎりぎり (done: 2026-10-11)\n"
            "- [x] 日付なし\n- [x] 変な日付 (done: 2026-02-31)\n",
        ))
        kept, archived = split_archive(doc, TODAY)
        self.assertEqual(titles(kept, "完了"), ["済んだ", "ぎりぎり", "日付なし", "変な日付"])
        self.assertEqual({m: [i.title for i in its] for m, its in archived.items()}, {"2026-10": ["古い"]})


class RepoMixin:
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.repo = Path(self._td.name)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.name", "t")
        git(self.repo, "config", "user.email", "t@t")
        self.todo = self.repo / "todo.md"
        self.commit(BASE)

    def tearDown(self):
        self._td.cleanup()

    def commit(self, text, msg="todo: 2026-11-01 10:00"):
        self.todo.write_text(text, encoding="utf-8")
        git(self.repo, "add", "todo.md")
        git(self.repo, "commit", "-q", "-m", msg)

    def run_apply(self, changes, wait=True):
        cf = self.repo / "changes.json"
        cf.write_text(json.dumps(changes, ensure_ascii=False), encoding="utf-8")
        cmd = [sys.executable, APPLY, "--changes", str(cf), "--todo", str(self.todo), "--today", TODAY]
        env = dict(os.environ, LANG="C.UTF-8")
        if not wait:
            return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        return subprocess.run(cmd, capture_output=True, text=True, env=env)

    def head(self, fmt):
        return git(self.repo, "log", "-1", f"--format={fmt}").strip()

    def move_1202(self, source="ai"):
        return {"source": source, "ops": [
            {"op": "move", "ref": "epc#1202", "to": "完了", "reason": "closed on GitHub"}]}


class CliTest(RepoMixin, unittest.TestCase):
    def test_commit_message(self):
        r = self.run_apply({"source": "ai", "ops": [
            {"op": "set_next", "ref": "epc#1163", "next": "直す", "reason": "指摘が来た"},
            {"op": "move", "ref": "epc#9999", "to": "完了", "reason": "r"},
        ]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(self.head("%s").startswith("todo(ai): "))
        body = self.head("%b")
        self.assertIn("指摘が来た", body)
        self.assertIn("https://github.com/x/epc/pull/1163", body)
        self.assertIn("skip: unknown ref epc#9999", body)

    def test_sync_subject(self):
        r = self.run_apply(self.move_1202("sync"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(self.head("%s").startswith("todo(sync): "))
        self.assertIn("- [x] 調査 [epc#1202](https://github.com/x/epc/issues/1202) (done: 2026-11-10)",
                      self.todo.read_text(encoding="utf-8"))

    def test_reject_reopen(self):
        r = self.run_apply({"source": "ai", "ops": [{"op": "move", "ref": "epc#1100", "to": "やる", "reason": "r"}]})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)

    def test_unknown_source_exit2(self):
        r = self.run_apply(self.move_1202("human"))
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)

    def test_title_injection_exit2(self):
        r = self.run_apply({"source": "ai", "ops": [
            {"op": "add", "section": "やる", "title": "a — next: b", "reason": "r"}]})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)

    def test_parse_error_exit2(self):
        broken = BASE.replace("## 待ち", "## まち")
        self.commit(broken)
        r = self.run_apply(self.move_1202())
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), broken)

    def test_confirm_free_text_exit2(self):
        text = BASE.replace("## 確認待ち\n", "## 確認待ち\nこれはメモ\n")
        self.commit(text)
        r = self.run_apply({"source": "ai", "ops": [], "confirm": []})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), text)

    def test_confirm_unrecorded_answer_exit2(self):
        self.commit(BASE.replace("## 確認待ち\n", "## 確認待ち\n1. 問い\n   事実: f\n   選択: A x\n   回答:\n"),
                    "todo(ai): 確認待ち1")
        text = BASE.replace("## 確認待ち\n", "## 確認待ち\n1. 問い\n   事実: f\n   選択: A x\n   回答: A\n")
        self.commit(text)
        r = self.run_apply({"source": "ai", "ops": [], "confirm": []})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), text)
        r = self.run_apply({"source": "ai", "ops": [], "confirm": [],
                            "answered": [{"ref": "epc#1202", "kind": "policy", "answer": "A"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("回答: A", self.todo.read_text(encoding="utf-8"))

    def test_human_edit_of_confirm_block_exit2(self):
        self.commit(BASE.replace("## 確認待ち\n", "## 確認待ち\n1. 問い\n   事実: f\n   選択: A x\n   回答:\n"),
                    "todo(ai): 確認待ち1")
        text = BASE.replace("## 確認待ち\n", "## 確認待ち\n1. 問い\n   事実: f、ただし来週は不在\n   選択: A x\n   回答:\n")
        self.commit(text)
        r = self.run_apply({"source": "ai", "ops": [], "confirm": []})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), text)

    def test_reopen_swap_exit2(self):
        self.commit(REOPEN_SWAP)
        r = self.run_apply({"source": "sync", "ops": [
            {"op": "move", "ref": "epc#1", "to": "やる"}, {"op": "move", "ref": "epc#2", "to": "完了"}]})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), REOPEN_SWAP)

    def test_huge_pid_lock_is_stale(self):
        lock = self.repo / ".todo.lock"
        lock.write_text("99999999999999999999\n")
        r = self.run_apply(self.move_1202())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(lock.exists())

    def test_index_lock_is_retried(self):
        (self.repo / ".git" / "index.lock").write_text("")
        r = self.run_apply(self.move_1202())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(self.head("%s").startswith("todo(ai): "))
        self.assertEqual(git(self.repo, "status", "--porcelain", "--", "todo.md").strip(), "")

    def test_lock_skip(self):
        lock = self.repo / ".todo.lock"
        lock.write_text(f"{os.getpid()}\n")
        r = self.run_apply(self.move_1202())
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)
        self.assertTrue(lock.exists())

        lock.write_text("99999999\n")
        r = self.run_apply(self.move_1202())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(lock.exists())
        self.assertIn("(done: 2026-11-10)", self.todo.read_text(encoding="utf-8"))

    def test_archive_30days(self):
        text = BASE.replace(
            "(done: 2026-11-01)\n",
            "(done: 2026-11-01)\n- [x] 古い [epc#1000](https://github.com/x/epc/pull/1000) (done: 2026-10-10)\n"
            "- [x] ぎりぎり (done: 2026-10-11)\n",
        )
        self.commit(text)
        r = self.run_apply({"source": "sync", "ops": []})
        self.assertEqual(r.returncode, 0, r.stderr)
        body = self.todo.read_text(encoding="utf-8")
        self.assertNotIn("古い", body)
        self.assertIn("- [x] ぎりぎり (done: 2026-10-11)", body)
        archive = (self.repo / "todo-archive" / "2026-10.md").read_text(encoding="utf-8")
        self.assertIn("- [x] 古い [epc#1000](https://github.com/x/epc/pull/1000) (done: 2026-10-10)", archive)
        self.assertEqual(git(self.repo, "status", "--porcelain", "--", "todo.md", "todo-archive").strip(), "")
        self.assertTrue(self.head("%s").startswith("todo(sync): "))

    def test_noop_no_commit(self):
        before = self.head("%H")
        r = self.run_apply({"source": "sync", "ops": [{"op": "move", "ref": "epc#1100", "to": "完了", "reason": "r"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.head("%H"), before)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)

    def test_noncanonical_noop_not_rewritten(self):
        text = BASE.replace("- [ ] 坂西さんの対応", "\n- [ ] 坂西さんの対応")
        self.commit(text)
        before = self.head("%H")
        r = self.run_apply({"source": "sync", "ops": []})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.head("%H"), before)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), text)

    def test_bad_confirm_options_exit2(self):
        r = self.run_apply({"source": "ai", "ops": [], "confirm": [
            {"ref": "epc#1202", "kind": "policy", "question": "q", "facts": "f", "options": ["A"]}]})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)

    def test_missing_todo_exit1_without_commit(self):
        before = self.head("%H")
        self.todo.unlink()
        r = self.run_apply(self.move_1202())
        self.assertEqual(r.returncode, 1)
        self.assertEqual(self.head("%H"), before)

    def test_dirty_human_edit_committed_as_human_first(self):
        self.todo.write_text(BASE.replace("- [ ] 坂西さんの対応", "- [ ] 坂西さんの対応\n- [ ] 手で足した"), encoding="utf-8")
        r = self.run_apply(self.move_1202())
        self.assertEqual(r.returncode, 0, r.stderr)
        subjects = git(self.repo, "log", "-S手で足した", "--format=%s", "--", "todo.md").splitlines()
        self.assertEqual(len(subjects), 1)
        self.assertTrue(subjects[0].startswith("todo: "), subjects)
        self.assertTrue(self.head("%s").startswith("todo(ai): "))

    def test_commit_only_target_paths(self):
        other = self.repo / "other.md"
        other.write_text("x\n")
        git(self.repo, "add", "other.md")
        r = self.run_apply(self.move_1202())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("other.md", git(self.repo, "show", "--name-only", "--format=", "HEAD"))
        self.assertIn("A  other.md", git(self.repo, "status", "--porcelain"))

    def test_waits_for_write_lock(self):
        with open(self.repo / ".todo.write.lock", "w") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            p = self.run_apply(self.move_1202(), wait=False)
            time.sleep(0.5)
            self.assertIsNone(p.poll())
            self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)
        _, err = p.communicate(timeout=10)
        self.assertEqual(p.returncode, 0, err)
        self.assertIn("(done: 2026-11-10)", self.todo.read_text(encoding="utf-8"))


class InProcessRunTest(RepoMixin, unittest.TestCase):
    """apply.run を同じプロセスで呼び、読み込み後の書き換えやコミット失敗を差し込む。"""

    def patch(self, name, value):
        orig = getattr(apply, name)
        setattr(apply, name, value)
        self.addCleanup(setattr, apply, name, orig)
        return orig

    def changes_file(self, changes):
        cf = self.repo / "changes.json"
        cf.write_text(json.dumps(changes, ensure_ascii=False), encoding="utf-8")
        return cf

    def test_human_write_after_read_is_kept(self):
        text = BASE.replace("(done: 2026-11-01)\n", "(done: 2026-11-01)\n- [x] 古い (done: 2026-10-01)\n")
        self.commit(text)
        head = self.head("%H")
        calls = [0]
        orig = apply.nvim_editing

        def fake(d):
            calls[0] += 1
            if calls[0] == 2:
                self.todo.write_text(text.replace("- [ ] 坂西さんの対応", "- [ ] 坂西さんの対応 — next: 人が今書いた"),
                                     encoding="utf-8")
            return orig(d)

        self.patch("nvim_editing", fake)
        self.assertEqual(apply.run(self.changes_file(self.move_1202()), self.todo, TODAY), 3)
        self.assertIn("人が今書いた", self.todo.read_text(encoding="utf-8"))
        self.assertEqual(self.head("%H"), head)
        self.assertFalse((self.repo / "todo-archive").exists())

    def test_human_write_just_before_replace_rolls_back_archive(self):
        text = BASE.replace("(done: 2026-11-01)\n", "(done: 2026-11-01)\n- [x] 古い (done: 2026-10-01)\n")
        self.commit(text)
        orig = apply._write_atomic

        def racing(path, content, expect=None):
            if path == self.todo and expect is not None:
                path.write_text(expect + "- [ ] 人の追記\n", encoding="utf-8")
            return orig(path, content, expect)

        self.patch("_write_atomic", racing)
        self.assertEqual(apply.run(self.changes_file(self.move_1202()), self.todo, TODAY), 3)
        self.assertTrue(self.todo.read_text(encoding="utf-8").endswith("- [ ] 人の追記\n"))
        self.assertFalse((self.repo / "todo-archive" / "2026-10.md").exists())
        self.assertEqual(list(self.repo.glob(".todo.md.tmp")), [])

    def test_commit_failure_restores_files(self):
        orig = apply._git

        def failing(repo, *args, retry=False):
            if args[0] == "commit":
                raise RuntimeError("simulated")
            return orig(repo, *args, retry=retry)

        self.patch("_git", failing)
        with self.assertRaises(RuntimeError):
            apply.run(self.changes_file(self.move_1202()), self.todo, TODAY)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)


if __name__ == "__main__":
    unittest.main()
