"""意図・回答・pin の行の系譜（key 付け・改名）と、/todo-edit・手作業との取り合いの通し試験。"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import decisions

APPLY = str(HERE / "apply.py")
CONTEXT = str(HERE / "context.py")
TODAY = "2026-11-11"
BASE = ("# TODO\n\n## 確認待ち\n\n## やる\n- [ ] 資料の件\n- [ ] 済PR [epc#5](https://github.com/x/y/pull/5)\n"
        "## 待ち\n- [ ] X [gb:r#2](https://gb/r/pull/2)\n## 完了\n- [x] 済 (done: 2026-11-10)\n")


def conflict(q):
    return [{"ref": "epc#9", "kind": "conflict", "question": q, "facts": "f",
             "options": [{"label": "A", "text": "意図どおり", "recommended": True}, {"label": "B", "text": "閉じる"}]}]


class Flow(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.dir = Path(self._t.name)
        self.todo = self.dir / "todo.md"
        self.git("init", "-q")
        self.hand(BASE)

    def git(self, *a):
        r = subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", str(self.dir), *a],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        return r.stdout

    def hand(self, text):
        self.todo.write_text(text, encoding="utf-8")
        self.git("add", "todo.md")
        self.git("commit", "-q", "-m", "todo: hand")

    def edit(self, old, new):
        text = self.todo.read_text(encoding="utf-8")
        self.assertIn(old, text)
        self.hand(text.replace(old, new))

    def apply(self, changes):
        p = self.dir / "c.json"
        p.write_text(json.dumps(changes, ensure_ascii=False), encoding="utf-8")
        extra = ["--allow-user"] if changes["source"] == "user" else []
        env = {k: v for k, v in os.environ.items() if k != "TODO_AI_DENY_USER"}
        r = subprocess.run([sys.executable, APPLY, "--changes", str(p), "--todo", str(self.todo), "--today", TODAY,
                            *extra], capture_output=True, text=True, env=dict(env, LANG="C.UTF-8"))
        self.assertEqual(r.returncode, 0, r.stderr)
        return self.git("log", "-1", "--format=%s%n%b")

    def ai(self, *ops, confirm=None):
        """ops に関係のない next の書き換えを足し、飛ばしただけの実行でもコミット本文を残す。"""
        self._n = getattr(self, "_n", 0) + 1
        ch = {"source": "ai", "ops": [*ops, {"op": "set_next", "ref": "gb:r#2", "next": f"n{self._n}"}]}
        if confirm is not None:
            ch["confirm"] = confirm
        return self.apply(ch)

    def user(self, *ops):
        return self.apply({"source": "user", "ops": list(ops)})

    def ctx(self):
        r = subprocess.run([sys.executable, CONTEXT, "--todo", str(self.todo), "--today", TODAY],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def item(self, ctx, ref):
        return next(i for i in ctx["items"] if i["ref"] == ref)

    def records(self):
        return decisions.load(self.dir / "todo-decisions.jsonl")

    def attach_9(self):
        return self.apply({"source": "ai", "ops": [
            {"op": "attach", "ref": "title:資料の件", "key": "epc#9", "url": "https://github.com/x/y/pull/9"}]})

    def answer_block(self):
        self.edit("   回答:\n", "   回答: A\n")


class ConflictReask(Flow):
    """I1: 新しい意図が回答より後に記録されたら、同じ行の conflict をもう一度聞ける。"""

    def setUp(self):
        super().setUp()
        self.attach_9()
        self.apply({"source": "ai", "ops": [], "confirm": conflict("q1")})
        self.answer_block()

    def test_recorded_answer_then_new_intent_reasks(self):
        self.apply({"source": "ai", "ops": [], "confirm": []})
        self.assertIn("skip: answered conflict epc#9", self.ai(confirm=conflict("q1")))
        self.user({"op": "set_next", "ref": "epc#9", "next": "すぐ依頼", "intent": "新しい指示: すぐ依頼"})
        self.apply({"source": "ai", "ops": [], "confirm": conflict("q2")})
        self.assertIn("q2 [conflict epc#9]", self.todo.read_text(encoding="utf-8"))

    def test_answer_still_in_block_when_intent_came_is_stale(self):
        self.user({"op": "set_next", "ref": "epc#9", "next": "すぐ依頼", "intent": "新しい指示: すぐ依頼"})
        self.apply({"source": "ai", "ops": [], "confirm": conflict("q2")})
        text = self.todo.read_text(encoding="utf-8")
        self.assertIn("q2 [conflict epc#9]", text)
        self.assertNotIn("q1", text)
        ans = [r for r in self.records() if r.get("kind") == "conflict"]
        self.assertEqual([(r["ref"], r["value"], r.get("stale")) for r in ans], [("epc#9", "A", True)])
        self.assertEqual(self.item(self.ctx(), "epc#9")["answers"][0]["superseded"], True)
        # 書いた問いを写し直しても、古い回答で落ちない
        self.apply({"source": "ai", "ops": [], "confirm": conflict("q2")})
        self.assertIn("q2 [conflict epc#9]", self.todo.read_text(encoding="utf-8"))

    def test_fresh_block_answer_still_skips(self):
        self.apply({"source": "ai", "ops": [], "confirm": conflict("q1")})
        self.assertNotIn("[conflict epc#9]", self.todo.read_text(encoding="utf-8"))
        rec = [r for r in self.records() if r.get("kind") == "conflict"]
        self.assertEqual([r.get("stale") for r in rec], [None])
        ctx = self.ctx()
        self.assertEqual(self.item(ctx, "epc#9")["answers"],
                         [{"kind": "conflict", "value": "A", "ts": rec[0]["ts"], "superseded": False}])
        self.assertEqual([a["superseded"] for a in ctx["answered_refs"]], [False])

    def test_answer_to_a_question_asked_after_the_intent_is_kept(self):
        self.apply({"source": "ai", "ops": [], "confirm": []})
        self.user({"op": "note", "ref": "epc#9", "intent": "残す"})
        self.apply({"source": "ai", "ops": [], "confirm": conflict("q2")})
        self.answer_block()
        self.apply({"source": "ai", "ops": [], "confirm": []})
        self.assertEqual([r.get("stale") for r in self.records() if r.get("kind") == "conflict"], [None, None])
        self.assertIn("skip: answered conflict epc#9", self.ai(confirm=conflict("q3")))
        self.assertEqual(self.item(self.ctx(), "epc#9")["answers"][0]["superseded"], False)


class AttachAlias(Flow):
    """I2: key を付けた行に、付ける前の ref の意図・pin・回答がついてくる。"""

    def test_alias_record_and_intents_follow(self):
        self.user({"op": "set_next", "ref": "title:資料の件", "next": "eas#60 後", "intent": "マージまで残す"})
        body = self.attach_9()
        self.assertIn("record alias epc#9", body)
        alias = [r for r in self.records() if r.get("kind") == "alias"]
        self.assertEqual([{k: v for k, v in r.items() if k != "ts"} for r in alias],
                         [{"ref": "epc#9", "kind": "alias", "prev_ref": "title:資料の件", "by": "ai"}])
        ctx = self.ctx()
        self.assertEqual([i["value"] for i in self.item(ctx, "epc#9")["intents"]], ["マージまで残す"])
        self.assertEqual(ctx["other_intents"], [])
        self.assertNotIn("epc#9", ctx["deleted_refs"])

    def test_alias_is_not_a_human_decision(self):
        self.attach_9()
        recs = self.records()
        self.assertEqual(decisions.intents(recs, "epc#9"), [])
        self.assertIsNone(decisions.already_answered(recs, "epc#9", "conflict"))
        ctx = self.ctx()
        self.assertEqual(ctx["intent_refs"], [])
        self.assertEqual(ctx["answered_refs"], [])

    def test_reopen_pin_follows_attach(self):
        self.user({"op": "move", "ref": "title:済", "to": "やる", "intent": "まだ"})
        self.apply({"source": "ai", "ops": [
            {"op": "attach", "ref": "title:済", "key": "epc#3", "url": "https://github.com/x/y/pull/3"}]})
        self.assertEqual(self.item(self.ctx(), "epc#3")["pinned_to"], ["完了"])
        self.assertIn("skip: pinned epc#3", self.apply({"source": "sync", "ops": [
            {"op": "move", "ref": "epc#3", "to": "完了"}, {"op": "set_next", "ref": "epc#5", "next": "n"}]}))

    def test_answer_before_attach_counts(self):
        self.apply({"source": "ai", "ops": [], "confirm": [{"ref": "title:資料の件", "kind": "policy",
                                                              "question": "方針？", "facts": "",
                                                              "options": [{"label": "A", "text": "x"}]}]})
        self.answer_block()
        self.apply({"source": "ai", "ops": [], "confirm": []})
        self.attach_9()
        self.assertIsNotNone(decisions.already_answered(self.records(), "epc#9", "policy"))
        body = self.ai(confirm=[{"ref": "epc#9", "kind": "policy", "question": "方針？", "facts": "",
                                 "options": [{"label": "A", "text": "x"}]}])
        self.assertIn("skip: answered policy epc#9", body)
        self.assertEqual([a["value"] for a in self.item(self.ctx(), "epc#9")["answers"]], ["A"])

    def test_delete_after_attach_blocks_old_title_too(self):
        self.attach_9()
        self.user({"op": "delete", "ref": "epc#9", "intent": "不要"})
        self.assertEqual(self.ctx()["deleted_refs"], ["epc#9", "title:資料の件"])

    def test_keyless_rename_keeps_pin_and_answers(self):
        self.user({"op": "move", "ref": "title:済", "to": "やる", "intent": "まだ"})
        self.user({"op": "edit_title", "ref": "title:済", "title": "済（続き）", "intent": "改名"})
        self.assertEqual(self.item(self.ctx(), "title:済（続き）")["pinned_to"], ["完了"])


class UserMovesAreNotReverts(Flow):
    """I3: /todo-edit（todo(user)）の移動を、人の戻しとして隠れた pin にしない。"""

    def test_user_move_back_does_not_pin(self):
        self.apply({"source": "ai", "ops": [{"op": "move", "ref": "gb:r#2", "to": "やる"}]})
        self.user({"op": "move", "ref": "gb:r#2", "to": "待ち", "intent": "返事が来るまで待ち"})
        self.assertEqual(self.item(self.ctx(), "gb:r#2")["pinned_to"], [])
        body = self.apply({"source": "ai", "ops": [{"op": "move", "ref": "gb:r#2", "to": "やる", "reason": "返事が来た"}]})
        self.assertIn("move gb:r#2 → やる", body)
        self.assertEqual([r for r in self.records() if r.get("kind") == "revert_move"], [])

    def test_user_reopen_keeps_only_the_explicit_pin(self):
        self.apply({"source": "sync", "ops": [{"op": "move", "ref": "epc#5", "to": "完了"}]})
        self.user({"op": "move", "ref": "epc#5", "to": "やる", "intent": "まだ追加対応がある"})
        self.assertIn("skip: pinned epc#5", self.apply({"source": "sync", "ops": [
            {"op": "move", "ref": "epc#5", "to": "完了"}, {"op": "set_next", "ref": "gb:r#2", "next": "n"}]}))
        pins = [r for r in self.records() if r.get("kind") == "revert_move"]
        self.assertEqual([(r["ref"], r.get("commit")) for r in pins], [("epc#5", None)])

    def test_user_delete_of_ai_add_is_not_reject_add(self):
        self.apply({"source": "ai", "ops": [{"op": "add", "section": "やる", "key": "gb:r#1",
                                             "url": "https://gb/r/pull/1", "title": "T"}]})
        self.user({"op": "delete", "ref": "gb:r#1", "intent": "不要"})
        self.assertEqual(self.ctx()["rejected_refs"], [])
        self.assertEqual(self.ctx()["deleted_refs"], ["gb:r#1"])

    def test_hand_revert_is_still_detected(self):
        self.apply({"source": "ai", "ops": [{"op": "move", "ref": "gb:r#2", "to": "やる"}]})
        line = "- [ ] X [gb:r#2](https://gb/r/pull/2)\n"
        text = self.todo.read_text(encoding="utf-8").replace(line, "")
        self.hand(text.replace("## 待ち\n", "## 待ち\n" + line))
        self.assertEqual(self.item(self.ctx(), "gb:r#2")["pinned_to"], ["やる"])


class CleanupHandDelete(Flow):
    """I4: nvim で消した後片付け行は reject_add になり、別の日の分も足されない。"""

    def test_hand_deleted_cleanup_is_rejected(self):
        self.apply({"source": "ai", "ops": [{"op": "add", "section": "やる", "title": "後片付け（2026-11-10）", "next": "a"}]})
        self.edit("- [ ] 後片付け（2026-11-10） — next: a\n", "")
        self.assertEqual(self.ctx()["rejected_refs"], ["title:後片付け（2026-11-10）"])
        body = self.apply({"source": "ai", "ops": [
            {"op": "add", "section": "やる", "title": "後片付け（2026-11-11）", "next": "b"},
            {"op": "set_next", "ref": "epc#5", "next": "n"}]})
        self.assertIn("skip: intent_deleted title:後片付け（2026-11-10）", body)
        self.assertNotIn("後片付け", self.todo.read_text(encoding="utf-8"))

    def test_renamed_then_done_cleanup_does_not_block_next_day(self):
        self.apply({"source": "ai", "ops": [{"op": "add", "section": "やる", "title": "後片付け（2026-11-10）", "next": "a"}]})
        self.edit("後片付け（2026-11-10） — next", "後片付け（2026-11-10）ブランチ — next")
        self.edit("- [ ] 後片付け（2026-11-10）ブランチ — next: a\n", "")
        self.edit("## 完了\n", "## 完了\n- [x] 後片付け（2026-11-10）ブランチ — next: a (done: 2026-11-10)\n")
        self.edit("- [x] 後片付け（2026-11-10）ブランチ — next: a (done: 2026-11-10)\n", "")
        self.assertEqual(self.ctx()["rejected_refs"], [])
        body = self.apply({"source": "ai", "ops": [{"op": "add", "section": "やる", "title": "後片付け（2026-11-11）", "next": "b"}]})
        self.assertNotIn("skip:", body)
        self.assertIn("後片付け（2026-11-11）", self.todo.read_text(encoding="utf-8"))

    def test_other_title_refs_still_not_rejected(self):
        self.apply({"source": "ai", "ops": [{"op": "add", "section": "やる", "title": "普通の行"}]})
        self.edit("- [ ] 普通の行\n", "")
        self.assertEqual(self.ctx()["rejected_refs"], [])


class HandRestore(Flow):
    """M1: /todo-edit で消した行を人が書き戻したら、deleted_refs から外れて普通に扱う。"""

    def test_restored_row_leaves_deleted_refs(self):
        self.apply({"source": "ai", "ops": [{"op": "add", "section": "やる", "key": "gb:r#1",
                                             "url": "https://gb/r/pull/1", "title": "T"}]})
        self.user({"op": "delete", "ref": "gb:r#1", "intent": "不要"})
        self.edit("## やる\n", "## やる\n- [ ] T [gb:r#1](https://gb/r/pull/1)\n")
        ctx = self.ctx()
        self.assertIn("gb:r#1", [i["ref"] for i in ctx["items"]])
        self.assertEqual(ctx["deleted_refs"], [])
        # 消す指示の意図（「不要」）は、書き戻した行への指示として出さない
        self.assertEqual(self.item(ctx, "gb:r#1")["intents"], [])
        self.user({"op": "note", "ref": "gb:r#1", "intent": "やっぱり要る"})
        self.assertEqual([i["value"] for i in self.item(self.ctx(), "gb:r#1")["intents"]], ["やっぱり要る"])

    def test_restored_cleanup_lets_cleanup_resume(self):
        self.apply({"source": "ai", "ops": [{"op": "add", "section": "やる", "title": "後片付け（2026-11-10）", "next": "a"}]})
        self.user({"op": "delete", "ref": "title:後片付け（2026-11-10）", "intent": "不要"})
        self.assertIn("skip: intent_deleted", self.apply({"source": "ai", "ops": [
            {"op": "add", "section": "やる", "title": "後片付け（2026-11-11）"},
            {"op": "set_next", "ref": "epc#5", "next": "n"}]}))
        self.edit("## 完了\n", "## 完了\n- [x] 後片付け（2026-11-10） — next: a (done: 2026-11-10)\n")
        self.assertEqual(self.ctx()["deleted_refs"], [])
        self.assertIn("add title:後片付け（2026-11-11）", self.apply({"source": "ai", "ops": [
            {"op": "add", "section": "やる", "title": "後片付け（2026-11-11）"}]}))


if __name__ == "__main__":
    unittest.main()
