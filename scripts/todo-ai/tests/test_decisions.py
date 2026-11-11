import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import apply
import decisions

APPLY = str(HERE / "apply.py")
TODAY = "2026-11-10"
L = "- [ ] 調査 [epc#1](https://g/1)\n"


def doc(yaru="", matsu="", kanryo="", confirm=""):
    return f"## 確認待ち\n{confirm}\n## やる\n{yaru}\n## 待ち\n{matsu}\n## 完了\n{kanryo}"


class Repo:
    def __init__(self, tmp):
        self.dir = Path(tmp)
        self.todo = self.dir / "todo.md"
        self.git("init", "-q")

    def git(self, *a):
        r = subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", str(self.dir), *a],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        return r.stdout

    def commit(self, text, msg):
        self.todo.write_text(text, encoding="utf-8")
        self.git("add", "todo.md")
        self.git("commit", "-q", "-m", msg)


class DetectReverts(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.r = Repo(self._t.name)

    def test_revert_move(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.r.commit(doc(matsu=L), "todo(ai): 移動1")
        self.r.commit(doc(yaru=L), "todo: 戻した")
        recs = decisions.detect_reverts(self.r.dir, "todo.md")
        self.assertEqual([(x["ref"], x["kind"], x["value"], x["by"]) for x in recs],
                         [("epc#1", "revert_move", "やる", "human")])
        self.assertIn("commit", recs[0])

    def test_reject_add(self):
        self.r.commit(doc(), "todo: base")
        self.r.commit(doc(yaru=L), "todo(sync): 追加1")
        self.r.commit(doc(), "todo: 消した")
        recs = decisions.detect_reverts(self.r.dir, "todo.md")
        self.assertEqual([(x["ref"], x["kind"]) for x in recs], [("epc#1", "reject_add")])

    def test_untouched_ai_move_to_done_not_recorded(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.r.commit(doc(kanryo="- [x] 調査 [epc#1](https://g/1) (done: 2026-11-10)\n"), "todo(ai): 完了1")
        self.r.commit(doc(kanryo="- [x] 調査 [epc#1](https://g/1) (done: 2026-11-10)\n- [ ] 別\n"), "todo: 追記")
        self.assertEqual(decisions.detect_reverts(self.r.dir, "todo.md"), [])

    def test_not_double_recorded(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.r.commit(doc(matsu=L), "todo(ai): 移動1")
        self.r.commit(doc(yaru=L), "todo: 戻した")
        first = decisions.detect_reverts(self.r.dir, "todo.md")
        decisions.append(self.r.dir / "todo-decisions.jsonl", first)
        self.assertEqual(decisions.detect_reverts(self.r.dir, "todo.md"), [])
        self.assertEqual(len(decisions.load(self.r.dir / "todo-decisions.jsonl")), 1)

    def test_unparsable_history_skipped(self):
        self.r.commit("# 古い形式\n- [ ] x\n", "todo: base")
        self.r.commit("# 古い形式\n- [ ] x\n- [ ] y\n", "todo(ai): 追加")
        self.assertEqual(decisions.detect_reverts(self.r.dir, "todo.md"), [])

    def test_revert_of_c_after_later_ai_commit(self):
        a = "- [ ] 別 [epc#2](https://g/2)\n"
        self.r.commit(doc(yaru=L), "todo: base")
        self.r.commit(doc(matsu=L), "todo(sync): 移動")
        self.r.commit(doc(matsu=L, yaru=a), "todo(ai): 追加")
        self.r.commit(doc(yaru=L + a), "todo: 戻した")
        recs = decisions.detect_reverts(self.r.dir, "todo.md")
        self.assertEqual([(x["ref"], x["kind"]) for x in recs], [("epc#1", "revert_move")])

    def test_later_commit_moving_same_ref_not_a_revert(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.r.commit(doc(matsu=L), "todo(sync): 待ちへ")
        self.r.commit(doc(yaru=L), "todo(ai): やるへ")
        self.assertEqual(decisions.detect_reverts(self.r.dir, "todo.md"), [])

    def test_title_ref_add_removed_not_recorded(self):
        self.r.commit(doc(), "todo: base")
        self.r.commit(doc(yaru="- [ ] 手書き\n"), "todo(ai): 追加")
        self.r.commit(doc(yaru="- [ ] 直した\n"), "todo: 直した")
        self.assertEqual(decisions.detect_reverts(self.r.dir, "todo.md"), [])

    def test_no_ai_commit(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.assertEqual(decisions.detect_reverts(self.r.dir, "todo.md"), [])

    def test_second_revert_from_same_commit_recorded(self):
        b = "- [ ] 別 [epc#2](https://g/2)\n"
        dpath = self.r.dir / "todo-decisions.jsonl"
        self.r.commit(doc(yaru=L + b), "todo: base")
        self.r.commit(doc(matsu=L + b), "todo(ai): 移動2")
        self.r.commit(doc(yaru=L, matsu=b), "todo: 1件戻した")
        first = decisions.detect_reverts(self.r.dir, "todo.md")
        self.assertEqual([x["ref"] for x in first], ["epc#1"])
        decisions.append(dpath, first)
        self.r.commit(doc(yaru=L + b), "todo: もう1件戻した")
        second = decisions.detect_reverts(self.r.dir, "todo.md")
        self.assertEqual([x["ref"] for x in second], ["epc#2"])
        decisions.append(dpath, second)
        self.assertEqual(decisions.detect_reverts(self.r.dir, "todo.md"), [])

    def test_revert_move_keeps_undone_destination(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.r.commit(doc(matsu=L), "todo(ai): 移動1")
        self.r.commit(doc(yaru=L), "todo: 戻した")
        rec = decisions.detect_reverts(self.r.dir, "todo.md")[0]
        self.assertEqual((rec["value"], rec["from"], rec["to"]), ("やる", "やる", "待ち"))


C = "- [ ] 後片付け（2026-11-10） — next: a\n"
C_DONE = "- [x] 後片付け（2026-11-10） — next: a (done: 2026-11-10)\n"
C_REF = "title:後片付け（2026-11-10）"


class CleanupRejectAdd(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.r = Repo(self._t.name)
        self.r.commit(doc(), "todo: base")
        self.r.commit(doc(yaru=C), "todo(ai): 追加1")

    def refs(self):
        return [(x["ref"], x["kind"]) for x in decisions.detect_reverts(self.r.dir, "todo.md")]

    def test_deleted_from_yaru_rejected(self):
        self.r.commit(doc(), "todo: 消した")
        self.assertEqual(self.refs(), [(C_REF, "reject_add")])

    def test_deleted_from_matsu_rejected(self):
        self.r.commit(doc(matsu=C), "todo: 待ちへ")
        self.r.commit(doc(), "todo: 消した")
        self.assertEqual(self.refs(), [(C_REF, "reject_add")])

    def test_deleted_from_done_not_rejected(self):
        self.r.commit(doc(kanryo=C_DONE), "todo: 完了にした")
        self.r.commit(doc(), "todo: 完了から片付けた")
        self.assertEqual(self.refs(), [])

    def test_rename_keeping_cleanup_prefix_not_rejected(self):
        self.r.commit(doc(yaru="- [ ] 後片付け（2026-11-10）ブランチ — next: a\n"), "todo: 直した")
        self.assertEqual(self.refs(), [])

    def test_renamed_cleanup_later_done_and_tidied_not_rejected(self):
        self.r.commit(doc(yaru="- [ ] 後片付け（2026-11-10）ブランチ — next: a\n"), "todo: 直した")
        self.r.commit(doc(kanryo="- [x] 後片付け（2026-11-10）ブランチ — next: a (done: 2026-11-10)\n"), "todo: 完了")
        self.assertEqual(self.refs(), [])
        self.r.commit(doc(), "todo: 完了から片付けた")
        self.assertEqual(self.refs(), [])

    def test_deleted_beside_other_cleanup_not_rejected_after_other_done(self):
        other = "- [ ] 後片付け（2026-11-09） — next: b\n"
        self.r.commit(doc(yaru=C + other), "todo: 別の後片付け")
        self.r.commit(doc(yaru=other), "todo: 消した")
        self.r.commit(doc(), "todo: もう1つも消した")
        self.assertEqual(self.refs(), [])

    def test_rename_dropping_cleanup_prefix_rejected(self):
        self.r.commit(doc(yaru="- [ ] ブランチ掃除 — next: a\n"), "todo: 直した")
        self.assertEqual(self.refs(), [(C_REF, "reject_add")])


class Records(unittest.TestCase):
    def test_load_append_pinned_answered(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "d.jsonl"
            self.assertEqual(decisions.load(p), [])
            decisions.append(p, [{"ts": "x", "ref": "a", "kind": "revert_move", "value": "やる", "by": "human"}])
            decisions.append(p, [{"ts": "y", "ref": "b", "kind": "policy", "value": "A", "by": "human"}])
            recs = decisions.load(p)
            self.assertEqual(len(recs), 2)
            self.assertTrue(decisions.is_pinned(recs, "a", "待ち"))
            self.assertFalse(decisions.is_pinned(recs, "b", "待ち"))
            self.assertEqual(decisions.already_answered(recs, "b", "policy")["value"], "A")
            self.assertIsNone(decisions.already_answered(recs, "b", "manual"))

    def test_pin_blocks_only_the_undone_destination(self):
        recs = [{"ref": "a", "kind": "revert_move", "value": "やる", "from": "やる", "to": "待ち", "by": "human"}]
        self.assertTrue(decisions.is_pinned(recs, "a", "待ち"))
        self.assertFalse(decisions.is_pinned(recs, "a", "完了"))
        self.assertFalse(decisions.is_pinned(recs, "a", "やる"))
        self.assertEqual(decisions.pinned_sections(recs, "a"), ["待ち"])
        self.assertEqual(decisions.pinned_sections(recs, "b"), [])

    def test_legacy_pin_without_destination_blocks_moves_away(self):
        recs = [{"ref": "a", "kind": "revert_move", "value": "やる", "by": "human"}]
        self.assertEqual(decisions.pinned_sections(recs, "a"), ["待ち", "完了"])
        self.assertFalse(decisions.is_pinned(recs, "a", "やる"))

    def test_is_rejected(self):
        recs = [{"ref": "epc#9", "kind": "reject_add", "value": "やる"}, {"kind": "reject_add"}]
        self.assertTrue(decisions.is_rejected(recs, "epc#9"))
        self.assertFalse(decisions.is_rejected(recs, "epc#8"))

    def test_intents_newest_first(self):
        recs = [{"ts": "t1", "ref": "epc#1", "kind": "intent", "value": "古い", "by": "human"},
                {"ts": "t1", "ref": "epc#1", "kind": "policy", "value": "A", "by": "human"},
                {"ts": "t2", "ref": "epc#2", "kind": "intent", "value": "別の行", "by": "human"},
                {"ts": "t3", "ref": "epc#1", "kind": "intent", "value": "新しい", "by": "human"},
                {"kind": "intent", "value": "ref なし"}]
        self.assertEqual([r["value"] for r in decisions.intents(recs, "epc#1")], ["新しい", "古い"])
        self.assertEqual(decisions.intents(recs, "epc#9"), [])

    def test_intents_follow_rename_only_backwards(self):
        recs = [{"ts": "t1", "ref": "title:旧", "kind": "intent", "value": "改名前"},
                {"ts": "t2", "ref": "title:新", "kind": "intent", "value": "改名", "prev_ref": "title:旧"},
                {"ts": "t3", "ref": "title:旧", "kind": "intent", "value": "改名後に同名で作った別行"}]
        self.assertEqual([r["value"] for r in decisions.intents(recs, "title:新")], ["改名", "改名前"])
        self.assertEqual([r["value"] for r in decisions.intents(recs, "title:旧")],
                         ["改名後に同名で作った別行", "改名前"])

    def test_deleted_refs_only_from_delete_and_renamed_away(self):
        recs = [{"ref": "epc#1", "kind": "intent", "value": "不要", "op": "delete"},
                {"ref": "title:新", "kind": "intent", "value": "改名", "op": "edit_title", "prev_ref": "title:旧"},
                {"ref": "rc:a", "kind": "intent", "value": "台帳に無い key へのメモ", "op": "note"},
                {"ref": "rc:b", "kind": "intent", "value": "紐付け", "op": "attach", "prev_ref": "title:手書き"},
                {"ref": "epc#2", "kind": "intent", "value": "古い記録（op 無し）"},
                {"ref": "epc#3", "kind": "intent", "value": "消す", "op": "delete"},
                {"ref": "epc#3", "kind": "intent", "value": "やっぱり要る", "op": "add"},
                {"ref": "epc#1", "kind": "intent", "value": "消した後のメモ", "op": "note"},
                {"ref": "epc#4", "kind": "reject_add", "value": "やる", "op": "delete"}]
        self.assertEqual(decisions.deleted_refs(recs), ["epc#1", "title:旧"])

    def test_load_keeps_unicode_line_separators_inside_a_record(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "d.jsonl"
            decisions.append(p, [{"ref": "title:a\u2028b\x0cc", "kind": "is_task", "value": "A"},
                                 {"ref": "epc#1", "kind": "policy", "value": "B"}])
            self.assertEqual([r["ref"] for r in decisions.load(p)], ["title:a\u2028b\x0cc", "epc#1"])


CONF = "1. 方針は？ [policy epc#1]\n   事実: f\n   選択: A x / B y\n   回答: A\n"


class ApplyIntegration(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.r = Repo(self._t.name)

    def run_apply(self, changes):
        cp = self.r.dir / "c.json"
        cp.write_text(json.dumps(changes), encoding="utf-8")
        return subprocess.run([sys.executable, APPLY, "--changes", str(cp), "--todo", str(self.r.todo),
                               "--today", TODAY], capture_output=True, text=True,
                              env={"PATH": "/usr/bin:/bin:/usr/local/bin", "GIT_AUTHOR_NAME": "t",
                                   "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                                   "GIT_COMMITTER_EMAIL": "t@t"})

    def test_answered_recorded_and_committed(self):
        self.r.commit(doc(yaru=L, confirm=CONF), "todo(ai): base")
        res = self.run_apply({"source": "ai", "ops": [], "confirm": [],
                              "answered": [{"ref": "epc#1", "kind": "policy", "answer": "A"}]})
        self.assertEqual(res.returncode, 0, res.stderr)
        recs = decisions.load(self.r.dir / "todo-decisions.jsonl")
        self.assertEqual([(x["ref"], x["kind"], x["value"], x["by"]) for x in recs],
                         [("epc#1", "policy", "A", "human")])
        self.assertIn("todo-decisions.jsonl", self.r.git("show", "--stat", "--format=%s", "HEAD"))
        self.assertEqual(self.r.git("status", "--porcelain", "--untracked-files=no").strip(), "")

    def test_revert_recorded_even_without_other_changes(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.r.commit(doc(matsu=L), "todo(ai): 移動1")
        self.r.commit(doc(yaru=L), "todo: 戻した")
        res = self.run_apply({"source": "ai", "ops": []})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual([x["kind"] for x in decisions.load(self.r.dir / "todo-decisions.jsonl")], ["revert_move"])
        self.assertEqual(self.r.git("log", "-1", "--format=%s").strip(), "todo(ai): 判断の記録")
        self.assertEqual(self.run_apply({"source": "ai", "ops": []}).returncode, 0)
        self.assertEqual(len(decisions.load(self.r.dir / "todo-decisions.jsonl")), 1)

    def test_sync_move_skipped_when_pinned(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.r.commit(doc(matsu=L), "todo(sync): 移動1")
        self.r.commit(doc(yaru=L), "todo: 戻した")
        res = self.run_apply({"source": "sync", "ops": [{"op": "move", "ref": "epc#1", "to": "待ち"}]})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("## やる\n- [ ] 調査", self.r.todo.read_text(encoding="utf-8"))
        self.assertIn("skip: pinned epc#1", self.r.git("log", "-1", "--format=%b"))

    def test_answer_recorded_without_answered(self):
        self.r.commit(doc(yaru=L, confirm=CONF), "todo(ai): base")
        res = self.run_apply({"source": "ai", "ops": [], "confirm": []})
        self.assertEqual(res.returncode, 0, res.stderr)
        recs = decisions.load(self.r.dir / "todo-decisions.jsonl")
        self.assertEqual([(x["ref"], x["kind"], x["value"]) for x in recs], [("epc#1", "policy", "A")])

    def test_answered_without_ref_kind_rejected(self):
        self.r.commit(doc(yaru=L, confirm=CONF), "todo(ai): base")
        res = self.run_apply({"source": "ai", "ops": [], "confirm": [], "answered": [{"answer": "A"}]})
        self.assertEqual(res.returncode, 2)
        self.assertFalse((self.r.dir / "todo-decisions.jsonl").exists())

    def add_epc1(self):
        return {"source": "ai", "ops": [{"op": "add", "section": "やる", "key": "epc#1", "url": "https://g/1",
                                         "title": "調査", "reason": "r"}]}

    def body(self):
        return self.r.git("log", "-1", "--format=%b")

    def test_ai_readd_of_rejected_key_skipped(self):
        self.r.commit(doc(), "todo: base")
        self.assertEqual(self.run_apply(self.add_epc1()).returncode, 0)
        self.r.commit(doc(), "todo: 消した")
        res = self.run_apply(self.add_epc1())
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertNotIn("epc#1", self.r.todo.read_text(encoding="utf-8"))
        self.assertIn("skip: rejected epc#1", self.body())
        self.assertEqual([x["kind"] for x in decisions.load(self.r.dir / "todo-decisions.jsonl")], ["reject_add"])

    def test_ai_attach_of_rejected_key_skipped(self):
        self.r.commit(doc(), "todo: base")
        self.assertEqual(self.run_apply(self.add_epc1()).returncode, 0)
        self.r.commit(doc(yaru="- [ ] 手書き\n"), "todo: 消して手で書いた")
        res = self.run_apply({"source": "ai", "ops": [
            {"op": "attach", "ref": "title:手書き", "key": "epc#1", "url": "https://g/1", "reason": "r"}]})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("- [ ] 手書き\n", self.r.todo.read_text(encoding="utf-8"))
        self.assertIn("skip: rejected epc#1", self.body())

    def test_ai_move_of_pinned_ref_skipped(self):
        self.r.commit(doc(yaru=L), "todo: base")
        mv = {"source": "ai", "ops": [{"op": "move", "ref": "epc#1", "to": "待ち", "reason": "theirs"}]}
        self.assertEqual(self.run_apply(mv).returncode, 0)
        self.r.commit(doc(yaru=L), "todo: 戻した")
        res = self.run_apply(mv)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("## やる\n- [ ] 調査", self.r.todo.read_text(encoding="utf-8"))
        self.assertIn("skip: pinned epc#1", self.body())

    def test_pin_lets_sync_finish_a_pr_the_human_tabbed_back(self):
        self.r.commit(doc(yaru=L), "todo: base")
        to_wait = {"source": "ai", "ops": [{"op": "move", "ref": "epc#1", "to": "待ち", "reason": "theirs"}]}
        self.assertEqual(self.run_apply(to_wait).returncode, 0)
        self.r.commit(doc(yaru=L), "todo: Tab で戻した")
        self.assertEqual(self.run_apply(to_wait).returncode, 0)
        self.assertIn("## やる\n- [ ] 調査", self.r.todo.read_text(encoding="utf-8"))
        self.assertIn("skip: pinned epc#1", self.body())
        res = self.run_apply({"source": "sync", "ops": [
            {"op": "move", "ref": "epc#1", "to": "完了", "reason": "GitHub 上でマージ済み"}]})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("## 完了\n- [x] 調査 [epc#1](https://g/1) (done: 2026-11-10)", self.r.todo.read_text(encoding="utf-8"))
        self.assertEqual(self.run_apply({"source": "ai", "ops": []}).returncode, 0)
        self.assertEqual([x["kind"] for x in decisions.load(self.r.dir / "todo-decisions.jsonl")], ["revert_move"])

    def test_pin_on_undone_done_blocks_sync(self):
        self.r.commit(doc(yaru=L), "todo: base")
        done = {"source": "sync", "ops": [{"op": "move", "ref": "epc#1", "to": "完了", "reason": "merged"}]}
        self.assertEqual(self.run_apply(done).returncode, 0)
        self.r.commit(doc(yaru=L), "todo: 完了から戻した")
        res = self.run_apply(done)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("## やる\n- [ ] 調査", self.r.todo.read_text(encoding="utf-8"))
        self.assertIn("skip: pinned epc#1", self.body())

    def test_answered_question_does_not_come_back(self):
        self.r.commit(doc(yaru=L, confirm=CONF), "todo(ai): base")
        again = {"ref": "epc#1", "kind": "policy", "question": "方針は？", "facts": "f",
                 "options": [{"label": "A", "text": "x"}, {"label": "B", "text": "y"}]}
        res = self.run_apply({"source": "ai", "ops": [], "confirm": [again]})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("## 確認待ち\n\n## やる", self.r.todo.read_text(encoding="utf-8"))
        res = self.run_apply({"source": "ai", "ops": [], "confirm": [again]})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("## 確認待ち\n\n## やる", self.r.todo.read_text(encoding="utf-8"))
        self.assertEqual(len(decisions.load(self.r.dir / "todo-decisions.jsonl")), 1)

    def test_hand_edited_record_without_ref_does_not_crash(self):
        self.r.commit(doc(yaru=L), "todo: base")
        (self.r.dir / "todo-decisions.jsonl").write_text(
            '{"kind": "revert_move", "value": "やる"}\n{"kind": "reject_add"}\n', encoding="utf-8")
        res = self.run_apply({"source": "ai", "ops": [{"op": "move", "ref": "epc#1", "to": "待ち"}]})
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("## 待ち\n- [ ] 調査", self.r.todo.read_text(encoding="utf-8"))

    def test_not_recorded_on_validation_failure(self):
        self.r.commit(doc(yaru=L, confirm=CONF), "todo(ai): base")
        res = self.run_apply({"source": "ai", "ops": [], "confirm": [], "answered": []})
        self.assertEqual(res.returncode, 2)
        self.assertFalse((self.r.dir / "todo-decisions.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
