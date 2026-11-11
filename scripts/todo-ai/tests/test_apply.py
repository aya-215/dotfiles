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
            "1. 方針を決める [policy epc#1202]",
            "   事実: PR が2本",
            "   選択: A まとめる（おすすめ） / B 分ける",
            "   回答:",
            "2. タスク？ [is_task title:インターン資料修正]",
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

    def test_confirm_requires_ref_and_known_kind(self):
        base = {"ref": "epc#1", "kind": "policy", "question": "q", "facts": "", "options": []}
        for bad in ({"ref": ""}, {"ref": None}, {"kind": "other"}, {"kind": None}, {"ref": "a\nb"}):
            with self.assertRaises(ChangeError, msg=bad):
                self.run_ops([], confirm=[{**base, **bad}])

    def test_existing_tag_in_question_not_doubled(self):
        new, _ = self.run_ops([], confirm=[
            {"ref": "epc#1", "kind": "policy", "question": "q [manual rc:x]", "facts": "", "options": []}])
        self.assertEqual(new.confirm[0], "1. q [policy epc#1]")

    def test_tag_helpers(self):
        self.assertEqual(apply.parse_tag("まだ要る？ [still_needed rc:abc#1]"), ("still_needed", "rc:abc#1"))
        self.assertEqual(apply.parse_tag("タスク？ [is_task title:返信 [件] の件]"), ("is_task", "title:返信 [件] の件"))
        self.assertEqual(apply.parse_tag("相談する？"), (None, None))
        self.assertEqual(apply.parse_tag("相談する？ [foo epc#1]"), (None, None))
        self.assertEqual(apply.strip_tag("相談する？ [policy epc#1]"), "相談する？")
        self.assertEqual(apply.strip_tag("相談する？"), "相談する？")

    ANSWERED = ["1. q1 [policy epc#1]", "   事実: f", "   選択: A x", "   回答: A", "",
                "2. q2 [manual rc:x]", "   事実: f", "   選択: B y", "   回答:  B にする、理由は来週"]

    def test_answer_records_come_from_tags(self):
        self.assertEqual(apply.answer_records(apply.parse_confirm(self.ANSWERED)),
                         [("epc#1", "policy", "A"), ("rc:x", "manual", "B にする、理由は来週")])

    def test_answered_optional_but_must_match_tags_when_given(self):
        self.doc.confirm = list(self.ANSWERED)
        new, body = self.run_ops([], confirm=[])
        self.assertEqual(new.confirm, [])
        self.assertIn("answer: 2. q2 [manual rc:x]", body)
        self.assertIn("   回答:  B にする、理由は来週", body)
        ok = [{"ref": "rc:x", "kind": "manual", "answer": "B にする、理由は来週"},
              {"ref": "epc#1", "kind": "policy", "answer": "A"}]
        self.run_ops([], confirm=[], answered=ok)
        for answered in ([None, None], [{"answer": "A"}, {"answer": "B"}], ok[:1],
                         [ok[0], {**ok[1], "ref": "epc#2"}], [ok[0], {**ok[1], "kind": "manual"}]):
            with self.assertRaises(ChangeError, msg=answered):
                self.run_ops([], confirm=[], answered=answered)

    def test_answered_untagged_block_rejected(self):
        self.doc.confirm = ["1. q1", "   事実: f", "   選択: A x", "   回答: A"]
        with self.assertRaises(ChangeError):
            self.run_ops([], confirm=[])
        self.doc.confirm = ["1. q1", "   事実: f", "   選択: A x", "   回答:"]
        new, _ = self.run_ops([], confirm=[])
        self.assertEqual(new.confirm, [])

    def test_reopen_move_rejected_before_validate(self):
        doc = todo_md.parse(REOPEN_SWAP)
        with self.assertRaises(ChangeError):
            apply_changes(doc, {"source": "sync", "ops": [
                {"op": "move", "ref": "epc#1", "to": "やる"},
                {"op": "move", "ref": "epc#2", "to": "完了"}]}, human, TODAY)

    def test_keyless_add_not_blocked_by_done_row_with_same_title(self):
        doc = todo_md.parse(BASE.replace("## 完了\n", "## 完了\n- [x] 見積もり送付 (done: 2026-11-01)\n"))
        new, body = apply_changes(doc, {"source": "ai", "ops": [
            {"op": "add", "section": "やる", "title": "見積もり送付", "reason": "is_task 回答 A"}]}, human, TODAY)
        self.assertEqual(titles(new, "やる")[-1], "見積もり送付")
        self.assertEqual(titles(new, "完了")[0], "見積もり送付")
        self.assertEqual(validate(doc, new, human, "ai") + apply.roundtrip_errors(new), [])
        self.assertNotIn("skip: duplicate title:見積もり送付", body)

    def test_keyless_add_duplicate_in_open_sections_skipped(self):
        new, body = self.run_ops([{"op": "add", "section": "待ち", "title": "インターン資料修正"}])
        self.assertEqual(titles(new, "待ち"), ["坂西さんの対応"])
        self.assertIn("skip: duplicate title:インターン資料修正", body)

    def test_keyed_add_duplicate_in_done_still_skipped(self):
        new, body = self.run_ops([{"op": "add", "section": "やる", "key": "epc#1100",
                                   "url": "https://github.com/x/epc/pull/1100", "title": "済んだ"}])
        self.assertIn("skip: duplicate epc#1100", body)

    def test_rejected_key_not_added_or_attached(self):
        recs = [{"ref": "epc#1300", "kind": "reject_add", "value": "やる", "by": "human"}]
        new, body = apply_changes(self.doc, {"source": "ai", "ops": [
            {"op": "add", "section": "やる", "key": "epc#1300", "url": "https://g/1300", "title": "x"},
            {"op": "attach", "ref": "title:インターン資料修正", "key": "epc#1300", "url": "https://g/1300"},
        ]}, human, TODAY, recs)
        self.assertEqual(new.sections, self.doc.sections)
        self.assertEqual(body.count("skip: rejected epc#1300"), 2)

    def test_pin_applies_to_ai_and_only_to_the_undone_destination(self):
        recs = [{"ref": "epc#1202", "kind": "revert_move", "value": "やる", "from": "やる", "to": "待ち"}]
        new, body = apply_changes(self.doc, {"source": "ai", "ops": [
            {"op": "move", "ref": "epc#1202", "to": "待ち"}]}, human, TODAY, recs)
        self.assertIn("epc#1202", [it.key for it in new.sections["やる"]])
        self.assertIn("skip: pinned epc#1202", body)
        new, body = apply_changes(self.doc, {"source": "sync", "ops": [
            {"op": "move", "ref": "epc#1202", "to": "完了"}]}, human, TODAY, recs)
        self.assertEqual(new.sections["完了"][0].key, "epc#1202")

    def answered_doc(self):
        self.doc.confirm = ["1. これはタスク？ [is_task title:見積もり]", "   事実: f", "   選択: A 追加 / B 不要",
                            "   回答: B"]
        return [{"ref": "title:見積もり", "kind": "is_task", "question": "これはタスク？", "facts": "f",
                 "options": [{"label": "A", "text": "追加"}, {"label": "B", "text": "不要"}]},
                {"ref": "epc#1202", "kind": "policy", "question": "方針？", "facts": "g",
                 "options": [{"label": "A", "text": "x", "recommended": True}]}]

    def test_confirm_entry_answered_in_this_run_is_dropped(self):
        entries = self.answered_doc()
        new, body = self.run_ops([], confirm=entries)
        self.assertEqual(new.confirm, ["1. 方針？ [policy epc#1202]", "   事実: g", "   選択: A x（おすすめ）", "   回答:"])
        self.assertIn("skip: answered is_task title:見積もり", body)
        self.assertIn("confirm: 1 件", body)

    def test_confirm_entry_already_recorded_is_dropped(self):
        entries = self.answered_doc()[1:]
        recs = [{"ref": "epc#1202", "kind": "policy", "value": "A", "by": "human"},
                {"ref": "epc#1163", "kind": "revert_move", "value": "やる", "by": "human"}]
        new, body = apply_changes(self.doc, {"source": "ai", "ops": [], "confirm": entries + [
            {"ref": "epc#1163", "kind": "policy", "question": "別？", "options": [{"label": "A", "text": "y"}]}]},
            human, TODAY, recs)
        self.assertEqual(new.confirm[0], "1. 別？ [policy epc#1163]")
        self.assertEqual(len(new.confirm), 4)
        self.assertIn("skip: answered policy epc#1202", body)

    def test_title_with_unicode_line_separator_roundtrips(self):
        new, _ = self.run_ops([{"op": "add", "section": "やる", "title": "a\u2028b\x0cc"}])
        self.assertEqual(apply.roundtrip_errors(new), [])

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

    def run_apply(self, changes, wait=True, extra=(), **env_extra):
        cf = self.repo / "changes.json"
        cf.write_text(json.dumps(changes, ensure_ascii=False), encoding="utf-8")
        cmd = [sys.executable, APPLY, "--changes", str(cf), "--todo", str(self.todo), "--today", TODAY, *extra]
        env = {k: v for k, v in os.environ.items() if k != "TODO_AI_DENY_USER"}
        env.update(LANG="C.UTF-8", **env_extra)
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

    def test_confirm_untagged_answer_exit2(self):
        self.commit(BASE.replace("## 確認待ち\n", "## 確認待ち\n1. 問い\n   事実: f\n   選択: A x\n   回答:\n"),
                    "todo(ai): 確認待ち1")
        text = BASE.replace("## 確認待ち\n", "## 確認待ち\n1. 問い\n   事実: f\n   選択: A x\n   回答: A\n")
        self.commit(text)
        for extra in ({}, {"answered": [{"ref": "epc#1202", "kind": "policy", "answer": "A"}]}):
            r = self.run_apply({"source": "ai", "ops": [], "confirm": [], **extra})
            self.assertEqual(r.returncode, 2)
            self.assertIn("タグ", r.stderr)
            self.assertEqual(self.todo.read_text(encoding="utf-8"), text)

    def test_confirm_answer_recorded_from_tag(self):
        q = "1. 問い [policy epc#1202]\n   事実: f\n   選択: A x\n   回答:\n"
        self.commit(BASE.replace("## 確認待ち\n", "## 確認待ち\n" + q), "todo(ai): 確認待ち1")
        self.commit(BASE.replace("## 確認待ち\n", "## 確認待ち\n" + q.replace("回答:", "回答: A")))
        r = self.run_apply({"source": "ai", "ops": [], "confirm": []})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("回答: A", self.todo.read_text(encoding="utf-8"))
        recs = [json.loads(l) for l in (self.repo / "todo-decisions.jsonl").read_text(encoding="utf-8").splitlines()]
        self.assertEqual([(x["ref"], x["kind"], x["value"]) for x in recs], [("epc#1202", "policy", "A")])

    def test_confirm_baseline_survives_many_commits_without_confirm_change(self):
        q = "1. 問い [policy epc#1202]\n   事実: f\n   選択: A x\n   回答:\n"
        text = BASE.replace("## 確認待ち\n", "## 確認待ち\n" + q)
        self.commit(text, "todo(ai): 確認待ち1")
        for i in range(60):
            self.commit(text.replace("— next: 読む", f"— next: n{i}"), f"todo(sync): next{i}")
        r = self.run_apply({"source": "ai", "ops": [], "confirm": [
            {"ref": "epc#1202", "kind": "policy", "question": "問い", "facts": "f",
             "options": [{"label": "A", "text": "x"}]}]})
        self.assertEqual(r.returncode, 0, r.stderr)

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


def confirm_entries(n):
    return [{"ref": f"epc#{2000 + i}", "kind": "policy", "question": f"問い{i}", "facts": "f",
             "options": [{"label": "A", "text": "x"}]} for i in range(n)]


class UserSourceTest(unittest.TestCase):
    def setUp(self):
        self.doc = todo_md.parse(BASE)

    def run_ops(self, ops, source="user", effects=None, records=(), **extra):
        return apply_changes(self.doc, {"source": source, "ops": ops, **extra}, human, TODAY, records,
                             effects=effects)

    def test_user_reopen_allowed(self):
        fx = apply.Effects()
        new, body = self.run_ops([{"op": "move", "ref": "epc#1100", "to": "やる", "intent": "まだ終わっていない"}],
                                 effects=fx)
        it = new.sections["やる"][-1]
        self.assertEqual((it.key, it.done, it.done_date), ("epc#1100", False, None))
        self.assertEqual(new.sections["完了"], [])
        self.assertEqual(validate(self.doc, new, human, "user", fx) + apply.roundtrip_errors(new), [])
        self.assertEqual(fx.intents, [{"ref": "epc#1100", "value": "まだ終わっていない"}])

    def test_ai_reopen_still_rejected(self):
        for source in ("ai", "sync"):
            with self.assertRaises(ChangeError):
                self.run_ops([{"op": "move", "ref": "epc#1100", "to": "やる", "intent": "x"}], source=source)
        reopened = copy.deepcopy(self.doc)
        it = reopened.sections["完了"].pop(0)
        it.done, it.done_date = False, None
        reopened.sections["やる"].append(it)
        self.assertTrue(validate(self.doc, reopened, human, "ai"))
        self.assertTrue(validate(self.doc, reopened, human, "sync"))
        self.assertEqual(validate(self.doc, reopened, human, "user"), [])

    def test_user_ops_rejected_for_ai_and_sync(self):
        for source in ("ai", "sync"):
            for op in ({"op": "edit_title", "ref": "epc#1163", "title": "x", "intent": "i"},
                       {"op": "delete", "ref": "epc#1163", "intent": "i"},
                       {"op": "note", "ref": "epc#1163", "intent": "i"}):
                with self.assertRaises(ChangeError):
                    self.run_ops([op], source=source)

    def test_exemptions_ignored_for_ai(self):
        fx = apply.Effects()
        new, _ = self.run_ops([
            {"op": "edit_title", "ref": "title:インターン資料修正", "title": "別名", "intent": "i"},
            {"op": "delete", "ref": "epc#1202", "intent": "i"}], effects=fx)
        self.assertEqual(validate(self.doc, new, human, "user", fx), [])
        errs = validate(self.doc, new, human, "ai", fx)
        self.assertTrue(any("タスク行が減る" in e for e in errs))
        self.assertTrue(any("リンク付きの行が消える" in e for e in errs))
        self.assertTrue(any("人が書いたタイトル" in e for e in errs))

    def test_user_validate_still_protects_lines_not_named(self):
        fx = apply.Effects()
        new, _ = self.run_ops([{"op": "delete", "ref": "epc#1202", "intent": "i"}], effects=fx)
        del new.sections["待ち"][0]
        self.assertTrue(validate(self.doc, new, human, "user", fx))
        fx = apply.Effects()
        new, _ = self.run_ops([{"op": "delete", "ref": "epc#1202", "intent": "i"}], effects=fx)
        new.sections["やる"][0].title = "AI が変えた"
        self.assertTrue(any("人が書いたタイトル" in e for e in validate(self.doc, new, human, "user", fx)))

    def test_delete_of_line_added_in_same_run_gives_no_exemption(self):
        fx = apply.Effects()
        new, _ = self.run_ops([
            {"op": "add", "section": "やる", "title": "一時", "intent": "i"},
            {"op": "delete", "ref": "title:一時", "intent": "i"}], effects=fx)
        self.assertEqual(fx.deleted, [])
        del new.sections["待ち"][0]
        self.assertTrue(validate(self.doc, new, human, "user", fx))

    def test_user_ignores_pins_and_rejects(self):
        recs = [{"ref": "epc#1202", "kind": "revert_move", "value": "やる", "from": "やる", "to": "待ち"},
                {"ref": "epc#1300", "kind": "reject_add", "value": "やる"}]
        new, body = self.run_ops([
            {"op": "move", "ref": "epc#1202", "to": "待ち", "intent": "i"},
            {"op": "add", "section": "やる", "key": "epc#1300", "url": "https://g/1300", "title": "x", "intent": "i"},
        ], records=recs)
        self.assertEqual(new.sections["待ち"][-1].key, "epc#1202")
        self.assertEqual(new.sections["やる"][-1].key, "epc#1300")
        self.assertFalse(any(l.startswith("skip:") for l in body))

    def test_user_skip_is_an_error(self):
        for op in ({"op": "move", "ref": "epc#9999", "to": "完了", "intent": "i"},
                   {"op": "note", "ref": "title:無い行", "intent": "i"},
                   {"op": "add", "section": "やる", "title": "インターン資料修正", "intent": "i"},
                   {"op": "order", "section": "やる", "refs": ["epc#9999"], "intent": "i"}):
            with self.assertRaises(ChangeError):
                self.run_ops([op])

    def test_edit_title_collision_rejected(self):
        with self.assertRaises(ChangeError):
            self.run_ops([{"op": "edit_title", "ref": "title:坂西さんの対応", "title": "インターン資料修正",
                           "intent": "i"}])

    def test_user_confirm_rejected(self):
        with self.assertRaises(ChangeError):
            self.run_ops([], confirm=[])

    def test_ai_intent_checked_but_not_recorded(self):
        fx = apply.Effects()
        self.run_ops([{"op": "set_next", "ref": "epc#1163", "next": "n", "intent": "AI の考え"}], source="ai",
                     effects=fx)
        self.assertEqual(fx.intents, [])
        with self.assertRaises(ChangeError):
            self.run_ops([{"op": "set_next", "ref": "epc#1163", "next": "n", "intent": 3}], source="ai")

    def test_attach_on_keyless_line_records_new_ref(self):
        fx = apply.Effects()
        self.run_ops([{"op": "attach", "ref": "title:インターン資料修正", "key": "rc:abc",
                       "url": "https://chat.example/abc", "intent": "RC の依頼と同じ"}], effects=fx)
        self.assertEqual(fx.intents, [{"ref": "rc:abc", "value": "RC の依頼と同じ",
                                       "prev_ref": "title:インターン資料修正"}])


class UserCliTest(RepoMixin, unittest.TestCase):
    def run_apply(self, changes, wait=True, extra=("--allow-user",), **env_extra):
        return super().run_apply(changes, wait, extra, **env_extra)

    def test_user_source_needs_allow_user(self):
        note = {"source": "user", "ops": [{"op": "note", "ref": "epc#1202", "intent": "i"}]}
        r = self.run_apply(note, extra=())
        self.assertEqual(r.returncode, 2)
        self.assertIn("--allow-user", r.stderr)
        self.assertFalse((self.repo / "todo-decisions.jsonl").exists())
        r = self.run_apply(note, TODO_AI_DENY_USER="1")
        self.assertEqual(r.returncode, 2)
        self.assertIn("TODO_AI_DENY_USER", r.stderr)
        self.assertFalse((self.repo / "todo-decisions.jsonl").exists())
        self.assertEqual(self.run_apply(note).returncode, 0)

    def test_allow_user_does_not_change_ai(self):
        r = self.run_apply({"source": "ai", "ops": [{"op": "move", "ref": "epc#1100", "to": "やる"}]},
                           TODO_AI_DENY_USER="1")
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.run_apply(self.move_1202(), TODO_AI_DENY_USER="1").returncode, 0)

    def test_user_reopen_pins_against_done(self):
        r = self.run_apply({"source": "user", "ops": [{"op": "move", "ref": "epc#1100", "to": "待ち",
                                                       "intent": "相手の返事待ちに戻す"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        pins = [x for x in self.records() if x["kind"] == "revert_move"]
        self.assertEqual([{k: v for k, v in x.items() if k != "ts"} for x in pins], [
            {"ref": "epc#1100", "kind": "revert_move", "value": "待ち", "from": "待ち", "to": "完了", "by": "human"}])
        for source in ("sync", "ai"):
            r = self.run_apply({"source": source, "ops": [
                {"op": "move", "ref": "epc#1100", "to": "完了"},
                {"op": "set_next", "ref": "epc#1163", "next": f"{source} が来た"}]}, extra=())
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("- [ ] 済んだ [epc#1100]", self.todo.read_text(encoding="utf-8"))
            self.assertIn("skip: pinned epc#1100", self.head("%b"))

    def test_user_reopen_pin_follows_rename(self):
        self.commit(BASE.replace("(done: 2026-11-01)\n", "(done: 2026-11-01)\n- [x] 鍵なし (done: 2026-11-02)\n"))
        r = self.run_apply({"source": "user", "ops": [
            {"op": "move", "ref": "title:鍵なし", "to": "やる", "intent": "i"},
            {"op": "edit_title", "ref": "title:鍵なし", "title": "鍵なし（続き）", "intent": "i"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([x["ref"] for x in self.records() if x["kind"] == "revert_move"], ["title:鍵なし（続き）"])

    def test_whitespace_intent_exit2(self):
        r = self.run_apply({"source": "user", "ops": [{"op": "note", "ref": "epc#1202", "intent": "  　"}]})
        self.assertEqual(r.returncode, 2)
        self.assertFalse((self.repo / "todo-decisions.jsonl").exists())

    def records(self):
        p = self.repo / "todo-decisions.jsonl"
        if not p.exists():
            return []
        return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines()]

    def test_user_edit_title_records_intent_with_prev_ref(self):
        r = self.run_apply({"source": "user", "ops": [
            {"op": "edit_title", "ref": "title:インターン資料修正", "title": "インターン資料の修正",
             "intent": "資料は来週の研修用"},
            {"op": "edit_title", "ref": "epc#1163", "title": "PR を見る", "intent": "題を短く"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        text = self.todo.read_text(encoding="utf-8")
        self.assertIn("- [ ] インターン資料の修正\n", text)
        self.assertIn("- [ ] PR を見る [epc#1163]", text)
        self.assertTrue(self.head("%s").startswith("todo(user): "))
        recs = self.records()
        self.assertEqual([{k: v for k, v in x.items() if k != "ts"} for x in recs], [
            {"ref": "title:インターン資料の修正", "kind": "intent", "value": "資料は来週の研修用", "by": "human",
             "prev_ref": "title:インターン資料修正"},
            {"ref": "epc#1163", "kind": "intent", "value": "題を短く", "by": "human"}])
        self.assertTrue(all(x["ts"] for x in recs))
        self.assertEqual(git(self.repo, "status", "--porcelain", "--untracked-files=no").strip(), "")

    def test_user_delete_allowed_ai_delete_rejected(self):
        r = self.run_apply({"source": "ai", "ops": [{"op": "delete", "ref": "epc#1202", "intent": "不要"}]})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)
        r = self.run_apply({"source": "user", "ops": [
            {"op": "delete", "ref": "epc#1202", "intent": "別チケットで対応済み"},
            {"op": "delete", "ref": "title:坂西さんの対応", "intent": "もう不要"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        text = self.todo.read_text(encoding="utf-8")
        self.assertNotIn("epc#1202", text)
        self.assertNotIn("坂西さんの対応", text)
        self.assertEqual([(x["ref"], x["value"]) for x in self.records()],
                         [("epc#1202", "別チケットで対応済み"), ("title:坂西さんの対応", "もう不要")])

    def test_user_reopen_cli(self):
        r = self.run_apply({"source": "user", "ops": [{"op": "move", "ref": "epc#1100", "to": "待ち",
                                                       "intent": "相手の返事待ちに戻す"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("## 待ち\n- [ ] 坂西さんの対応\n- [ ] 済んだ [epc#1100](https://github.com/x/epc/pull/1100)\n",
                      self.todo.read_text(encoding="utf-8"))

    def test_user_op_without_intent_exit2(self):
        for op in ({"op": "move", "ref": "epc#1202", "to": "完了"},
                   {"op": "note", "ref": "epc#1202", "intent": ""}):
            r = self.run_apply({"source": "user", "ops": [op]})
            self.assertEqual(r.returncode, 2, op)
            self.assertIn("intent", r.stderr)
            self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)
            self.assertFalse((self.repo / "todo-decisions.jsonl").exists())

    def test_user_validation_failure_records_no_intent(self):
        r = self.run_apply({"source": "user", "ops": [
            {"op": "edit_title", "ref": "title:インターン資料修正", "title": "a — next: b", "intent": "i"}]})
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)
        self.assertFalse((self.repo / "todo-decisions.jsonl").exists())

    def test_user_lock_records_no_intent(self):
        (self.repo / ".todo.lock").write_text(f"{os.getpid()}\n")
        r = self.run_apply({"source": "user", "ops": [{"op": "note", "ref": "epc#1202", "intent": "i"}]})
        self.assertEqual(r.returncode, 3)
        self.assertFalse((self.repo / "todo-decisions.jsonl").exists())

    def test_note_records_intent_only(self):
        r = self.run_apply({"source": "user", "ops": [
            {"op": "note", "ref": "epc#1202", "intent": "A5 は eas#60 のマージ後にレビュー依頼する"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), BASE)
        self.assertEqual([(x["ref"], x["kind"], x["value"]) for x in self.records()],
                         [("epc#1202", "intent", "A5 は eas#60 のマージ後にレビュー依頼する")])
        self.assertEqual(self.head("%s"), "todo(user): 意図1")
        self.assertEqual(git(self.repo, "show", "--name-only", "--format=", "HEAD").split(), ["todo-decisions.jsonl"])

    def test_user_commit_is_human_origin(self):
        r = self.run_apply({"source": "user", "ops": [
            {"op": "add", "section": "やる", "title": "見積もり作成", "intent": "金曜までに"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        from origin import origin_of
        self.assertEqual(origin_of(self.repo, "todo.md", "見積もり作成"), "human")

    def test_subject_confirm_count(self):
        r = self.run_apply({"source": "ai", "ops": [], "confirm": confirm_entries(19)})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("確認待ち19", self.head("%s"))
        self.assertIn("confirm: 19 件", self.head("%b"))

    def test_subject_confirm_cleared(self):
        self.commit(BASE.replace("## 確認待ち\n", "## 確認待ち\n1. q [policy epc#1202]\n   事実: f\n   選択: A x\n   回答:\n"),
                    "todo(ai): 確認待ち1")
        r = self.run_apply({"source": "ai", "ops": [], "confirm": []})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.head("%s"), "todo(ai): 確認待ち0")


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
