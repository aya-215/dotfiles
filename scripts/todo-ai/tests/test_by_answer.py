"""確認待ちの回答に基づく op（by_answer）と、回答の持ち越し（keep_answered）・選択肢ごとの変更案（on_answer）。"""
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply
import context
import decisions
import todo_md
from apply import ChangeError, apply_changes, validate
from test_apply import RepoMixin, git

TODAY = "2026-11-10"

CONFIRM = [
    "1. 『坂西さんの対応』に ebpm:No1・ebpm:No2 を別の行で足す？ [is_task title:坂西さんの対応]",
    "   A 足す★ / B 足さない（今の行で追う）",
    "   回答: これは対応済み。インターン資料修正も要らない",
    "2. 方針は？ [policy epc#1163]",
    "   A x★ / B y",
    "   回答:",
]

BODY = """
## やる
- [ ] インターン資料修正
- [ ] PR レビュー [epc#1163](https://github.com/x/epc/pull/1163) — next: 読む
- [ ] 調査 [epc#1202](https://github.com/x/epc/issues/1202)

## 待ち
- [ ] 坂西さんの対応

## 完了
- [x] 済んだ [epc#1100](https://github.com/x/epc/pull/1100) (done: 2026-11-01)
"""


def text(confirm):
    return "# TODO\n\n## 確認待ち\n" + "".join(l + "\n" for l in confirm) + BODY


def human(_t):
    return "human"


BA = {"ref": "title:坂西さんの対応", "kind": "is_task"}
KEEP2 = [{"ref": "epc#1163", "kind": "policy", "question": "方針は？", "facts": "",
          "options": [{"label": "A", "text": "x", "recommended": True}, {"label": "B", "text": "y"}]}]


class ByAnswerTest(unittest.TestCase):
    def setUp(self):
        self.doc = todo_md.parse(text(CONFIRM))

    def run_ops(self, ops, source="ai", confirm=KEEP2, records=(), asked_at=None, doc=None, **extra):
        fx = apply.Effects()
        changes = {"source": source, "ops": ops, **({"confirm": confirm} if confirm is not None else {}), **extra}
        new, body = apply_changes(doc or self.doc, changes, human, TODAY, records, effects=fx, asked_at=asked_at)
        return new, body, fx

    def skips(self, body):
        return [l for l in body if l.startswith("skip:")]

    def test_move_of_human_line_named_by_answer(self):
        new, body, fx = self.run_ops([{"op": "move", "ref": "title:坂西さんの対応", "to": "完了", "by_answer": BA}])
        self.assertEqual(new.sections["完了"][0].title, "坂西さんの対応")
        self.assertEqual(validate(self.doc, new, human, "ai", fx), [])
        intent, = fx.answer_intents
        self.assertEqual((intent["ref"], intent["op"], intent["by_answer"]), ("title:坂西さんの対応", "move", BA))
        self.assertIn("これは対応済み", intent["value"])
        self.assertIn("坂西さんの対応", intent["value"])

    def test_delete_and_retitle_of_human_line_named_by_answer(self):
        new, body, fx = self.run_ops([
            {"op": "edit_title", "ref": "title:坂西さんの対応", "title": "坂西さん", "by_answer": BA},
            {"op": "set_next", "ref": "title:坂西さん", "next": "n", "by_answer": BA}])
        self.assertEqual(self.skips(body), [])
        self.assertEqual((new.sections["待ち"][0].title, new.sections["待ち"][0].next), ("坂西さん", "n"))
        self.assertEqual(validate(self.doc, new, human, "ai", fx), [])
        self.assertEqual([i.get("prev_ref") for i in fx.answer_intents], ["title:坂西さんの対応", None])
        new, body, fx = self.run_ops([{"op": "delete", "ref": "title:坂西さんの対応", "by_answer": BA}])
        self.assertEqual(new.sections["待ち"], [])
        self.assertEqual(validate(self.doc, new, human, "ai", fx), [])
        self.assertEqual(fx.answer_intents[0]["op"], "delete")

    def test_without_by_answer_protections_are_unchanged(self):
        with self.assertRaises(ChangeError):
            self.run_ops([{"op": "delete", "ref": "title:坂西さんの対応"}])
        _, body, _ = self.run_ops([{"op": "edit_title", "ref": "title:坂西さんの対応", "title": "x"}])
        self.assertEqual(self.skips(body), ["skip: human title title:坂西さんの対応"])
        with self.assertRaises(ChangeError):
            self.run_ops([{"op": "move", "ref": "epc#1100", "to": "やる"}])

    def test_line_not_named_by_block_is_out_of_scope(self):
        # 回答の文に題が出ていても、問い・事実の『』か ref で名指しされていなければ対象にしない
        for op in ({"op": "delete", "ref": "title:インターン資料修正"},
                   {"op": "edit_title", "ref": "title:インターン資料修正", "title": "x"},
                   {"op": "move", "ref": "epc#1100", "to": "やる"},
                   {"op": "set_next", "ref": "epc#1202", "next": "n"}):
            new, body, fx = self.run_ops([dict(op, by_answer=BA)])
            self.assertEqual(self.skips(body), [f"skip: out of answer scope {op['ref']}"], op)
            self.assertEqual(fx.answer_intents, [])
            self.assertEqual(todo_md.render(new).split("## やる")[1], text(CONFIRM).split("## やる")[1])

    def test_scope_is_fixed_before_ops_so_attach_cannot_launder_a_line(self):
        confirm = ["1. 『坂西さんの対応』と同じ作業？ [is_task ebpm:No1]", "   A 同じ★ / B 別", "   回答: A"]
        doc = todo_md.parse(text(confirm))
        ba = {"ref": "ebpm:No1", "kind": "is_task"}
        new, body, fx = self.run_ops([
            {"op": "attach", "ref": "title:インターン資料修正", "key": "ebpm:No1", "url": "https://e/1"},
            {"op": "delete", "ref": "ebpm:No1", "by_answer": ba}], confirm=[], doc=doc)
        self.assertEqual(self.skips(body), ["skip: out of answer scope ebpm:No1"])
        self.assertEqual(new.sections["やる"][0].key, "ebpm:No1")
        # 名指しされた行への attach は by_answer でも通る
        new, body, fx = self.run_ops([{"op": "attach", "ref": "title:坂西さんの対応", "key": "ebpm:No1",
                                       "url": "https://e/1", "by_answer": ba}], confirm=[], doc=doc)
        self.assertEqual(self.skips(body), [])
        self.assertEqual(new.sections["待ち"][0].key, "ebpm:No1")

    def test_quote_must_match_title_exactly(self):
        confirm = ["1. 『坂西さん』の件は？ [policy rc:x]", "   A a★ / B b", "   回答: 消して"]
        doc = todo_md.parse(text(confirm))
        _, body, _ = self.run_ops([{"op": "delete", "ref": "title:坂西さんの対応",
                                    "by_answer": {"ref": "rc:x", "kind": "policy"}}], confirm=[], doc=doc)
        self.assertEqual(self.skips(body), ["skip: out of answer scope title:坂西さんの対応"])

    def test_quote_in_old_format_facts_counts(self):
        confirm = ["1. まだ要る？ [still_needed rc:x]", "   事実: 『坂西さんの対応』と同じ", "   選択: A 要る / B 不要",
                   "   回答: 不要"]
        doc = todo_md.parse(text(confirm))
        new, body, _ = self.run_ops([{"op": "move", "ref": "title:坂西さんの対応", "to": "完了",
                                      "by_answer": {"ref": "rc:x", "kind": "still_needed"}}], confirm=[], doc=doc)
        self.assertEqual(self.skips(body), [])
        self.assertEqual(new.sections["完了"][0].title, "坂西さんの対応")

    def test_no_answer_cases_skip(self):
        cases = [
            ({"ref": "epc#1163", "kind": "policy"}, KEEP2),          # 回答が空
            ({"ref": "title:坂西さんの対応", "kind": "policy"}, KEEP2),  # kind が違う
            ({"ref": "rc:none", "kind": "is_task"}, KEEP2),          # ブロックが無い
            (BA, None),                                               # confirm を出さない実行
        ]
        for ba, confirm in cases:
            new, body, fx = self.run_ops([{"op": "move", "ref": "title:坂西さんの対応", "to": "完了", "by_answer": ba}],
                                         confirm=confirm)
            self.assertEqual(self.skips(body), [f"skip: no answer {ba['ref']}"], ba)
            self.assertEqual(new.sections["待ち"][0].title, "坂西さんの対応")
            self.assertEqual(fx.answer_intents, [])

    def test_duplicate_block_is_not_an_answer(self):
        doc = todo_md.parse(text(CONFIRM[:3] + CONFIRM[:3]))
        _, body, _ = self.run_ops([{"op": "move", "ref": "title:坂西さんの対応", "to": "完了", "by_answer": BA}],
                                  confirm=[], doc=doc)
        self.assertEqual(self.skips(body), ["skip: no answer title:坂西さんの対応"])

    def test_stale_conflict_answer_is_not_an_answer(self):
        confirm = ["1. 完了にした件がまだ開いている。どうする？ [conflict epc#1100]", "   A 完了のまま★ / B 戻す",
                   "   回答: B"]
        doc = todo_md.parse(text(confirm))
        ba = {"ref": "epc#1100", "kind": "conflict"}
        op = {"op": "move", "ref": "epc#1100", "to": "やる", "by_answer": ba}
        recs = [{"ref": "epc#1100", "kind": "intent", "value": "残す", "op": "note"}]
        _, body, _ = self.run_ops([op], confirm=[], doc=doc, records=recs, asked_at=0)
        self.assertEqual(self.skips(body), ["skip: no answer epc#1100"])
        new, body, fx = self.run_ops([op], confirm=[], doc=doc, records=recs, asked_at=1)
        self.assertEqual(self.skips(body), [])
        self.assertEqual(new.sections["やる"][-1].key, "epc#1100")
        self.assertEqual(fx.reopened, [("epc#1100", "やる")])
        self.assertEqual(validate(doc, new, human, "ai", fx), [])
        self.assertIn("B 戻す", fx.answer_intents[0]["value"])

    def test_pin_does_not_block_a_move_named_by_answer(self):
        recs = [{"ref": "title:坂西さんの対応", "kind": "revert_move", "value": "待ち", "from": "待ち", "to": "完了"}]
        op = {"op": "move", "ref": "title:坂西さんの対応", "to": "完了"}
        _, body, _ = self.run_ops([op], records=recs)
        self.assertEqual(self.skips(body), ["skip: pinned title:坂西さんの対応"])
        new, body, _ = self.run_ops([dict(op, by_answer=BA)], records=recs)
        self.assertEqual(self.skips(body), [])

    def test_validate_still_catches_lines_lost_outside_scope(self):
        new, _, fx = self.run_ops([{"op": "delete", "ref": "title:坂西さんの対応", "by_answer": BA}])
        del new.sections["やる"][0]
        self.assertTrue(any("タスク行が減る" in e for e in validate(self.doc, new, human, "ai", fx)))
        new, _, fx = self.run_ops([{"op": "edit_title", "ref": "title:坂西さんの対応", "title": "x", "by_answer": BA}])
        new.sections["やる"][0].title = "AI が変えた"
        self.assertTrue(any("人が書いたタイトル" in e for e in validate(self.doc, new, human, "ai", fx)))
        # by_answer の免除は ai だけ。sync・user の検証には効かない
        new, _, fx = self.run_ops([{"op": "delete", "ref": "title:坂西さんの対応", "by_answer": BA}])
        self.assertTrue(validate(self.doc, new, human, "sync", fx))

    def test_reopen_exemption_is_per_line(self):
        doc = todo_md.parse(text(["1. 戻す？ [conflict epc#1100]", "   A a★ / B 戻す", "   回答: B"]).replace(
            "## 完了\n", "## 完了\n- [x] 別 [epc#1101](https://g/1101) (done: 2026-11-02)\n"))
        new, _, fx = self.run_ops([{"op": "move", "ref": "epc#1100", "to": "やる",
                                    "by_answer": {"ref": "epc#1100", "kind": "conflict"}}], confirm=[], doc=doc)
        self.assertEqual(validate(doc, new, human, "ai", fx), [])
        other = new.sections["完了"].pop(0)
        other.done, other.done_date = False, None
        new.sections["やる"].append(other)
        self.assertEqual(validate(doc, new, human, "ai", fx), ["ai は完了から戻せない: epc#1101 '別'"])

    def test_by_answer_only_for_ai_and_well_formed(self):
        for source in ("sync", "user"):
            with self.assertRaises(ChangeError, msg=source):
                self.run_ops([{"op": "move", "ref": "title:坂西さんの対応", "to": "完了", "by_answer": BA,
                               "intent": "i"}], source=source, confirm=None)
        for bad in ("x", {"ref": "title:坂西さんの対応"}, {"ref": "", "kind": "is_task"},
                    {"ref": "title:坂西さんの対応", "kind": "nope"}):
            with self.assertRaises(ChangeError, msg=bad):
                self.run_ops([{"op": "move", "ref": "title:坂西さんの対応", "to": "完了", "by_answer": bad}])
        with self.assertRaises(ChangeError):
            self.run_ops([{"op": "note", "ref": "title:坂西さんの対応", "by_answer": BA}])

    def test_add_by_answer_needs_answer_but_no_scope(self):
        add = {"op": "add", "section": "待ち", "key": "ebpm:No1", "url": "https://e/1", "title": "課題1"}
        new, body, fx = self.run_ops([dict(add, by_answer=BA)])
        self.assertEqual(self.skips(body), [])
        self.assertEqual(new.sections["待ち"][-1].key, "ebpm:No1")
        self.assertEqual(fx.answer_intents[0]["ref"], "ebpm:No1")
        _, body, _ = self.run_ops([dict(add, by_answer={"ref": "epc#1163", "kind": "policy"})])
        self.assertEqual(self.skips(body), ["skip: no answer epc#1163"])
        # 人が消した ref は回答があっても足さない
        recs = [{"ref": "ebpm:No1", "kind": "intent", "value": "不要", "op": "delete"}]
        _, body, _ = self.run_ops([dict(add, by_answer=BA)], records=recs)
        self.assertEqual(self.skips(body), ["skip: intent_deleted ebpm:No1"])

    def test_lines_added_in_the_same_run_are_out_of_scope(self):
        _, body, _ = self.run_ops([
            {"op": "add", "section": "やる", "title": "坂西さんの対応 2"},
            {"op": "delete", "ref": "title:坂西さんの対応 2", "by_answer": BA}])
        self.assertEqual(self.skips(body), ["skip: out of answer scope title:坂西さんの対応 2"])


class KeepAnsweredTest(unittest.TestCase):
    def setUp(self):
        confirm = CONFIRM[:3] + ["2. 方針は？ [policy epc#1163]", "   A x★ / B y", "   回答: A",
                                 "3. 足す？ [is_task rc:z]", "   A 足す★ / B 足さない", "   回答:"]
        self.doc = todo_md.parse(text(confirm))
        self.rest = [{"ref": "rc:z", "kind": "is_task", "question": "足す？", "facts": "",
                      "options": [{"label": "A", "text": "足す", "recommended": True}, {"label": "B", "text": "足さない"}]}]

    def run_keep(self, ops=(), keep=({"ref": "title:坂西さんの対応", "kind": "is_task"},), **extra):
        fx = apply.Effects()
        new, body = apply_changes(self.doc, {"source": "ai", "ops": list(ops), "confirm": self.rest,
                                             "keep_answered": list(keep), **extra}, human, TODAY, effects=fx)
        return new, body, fx

    def test_kept_block_stays_verbatim_and_is_not_consumed(self):
        new, body, _ = self.run_keep()
        self.assertEqual(new.confirm, ["1. 足す？ [is_task rc:z]", "   A 足す★ / B 足さない", "   回答:",
                                       "2. " + CONFIRM[0].split(". ", 1)[1], *CONFIRM[1:3]])
        self.assertIn("answer: 2. 方針は？ [policy epc#1163]", body)
        self.assertFalse(any("坂西" in l for l in body if l.startswith("answer:")))
        self.assertEqual(apply.consumed_answers(apply.parse_confirm(self.doc.confirm), self.run_keep_set()),
                         [("epc#1163", "policy", "A")])

    def run_keep_set(self):
        return {("title:坂西さんの対応", "is_task")}

    def test_kept_answer_gives_no_by_answer_power(self):
        _, body, _ = self.run_keep([{"op": "move", "ref": "title:坂西さんの対応", "to": "完了", "by_answer": BA}])
        self.assertIn("skip: no answer title:坂西さんの対応", body)

    def test_keep_must_name_an_answered_block_not_also_rewritten(self):
        for keep in ([{"ref": "rc:z", "kind": "is_task"}], [{"ref": "rc:none", "kind": "policy"}], ["x"]):
            with self.assertRaises(ChangeError, msg=keep):
                self.run_keep(keep=keep)
        self.rest.append({"ref": "title:坂西さんの対応", "kind": "is_task", "question": "q", "options": []})
        with self.assertRaises(ChangeError):
            self.run_keep()

    def test_keep_needs_confirm(self):
        with self.assertRaises(ChangeError):
            apply_changes(self.doc, {"source": "ai", "ops": [], "keep_answered": [BA]}, human, TODAY)


class OnAnswerTest(unittest.TestCase):
    def entry(self, **kw):
        e = {"ref": "rc:z", "kind": "is_task", "question": "足す？", "facts": "期限 11/14",
             "options": [{"label": "A", "text": "追加する（やる）", "recommended": True},
                         {"label": "B", "text": "タスクではない（追加しない）"}],
             "on_answer": {"A": [{"op": "add", "section": "やる", "title": "z の件"}], "B": []}}
        e.update(kw)
        return e

    def test_pending_holds_rendered_block_and_ops(self):
        fx = apply.Effects()
        new, body = apply_changes(todo_md.parse(text([])), {"source": "ai", "ops": [], "confirm": [
            self.entry(), dict(self.entry(ref="rc:y"), on_answer=None)]}, human, TODAY, effects=fx)
        self.assertEqual(fx.pending, [{
            "ref": "rc:z", "kind": "is_task", "line": "足す？（期限 11/14） [is_task rc:z]",
            "options": "A 追加する（やる）★ / B タスクではない（追加しない）",
            "on_answer": {"A": [{"op": "add", "section": "やる", "title": "z の件"}], "B": []}}])
        self.assertEqual(new.confirm[0], "1. " + fx.pending[0]["line"])

    def test_bad_on_answer_is_dropped_not_fatal(self):
        for bad in ({"C": []}, {"A": "x"}, {"A": ["x"]}, ["A"],
                    {"A": [{"op": "add", "section": "やる", "title": "t", "by_answer": BA}]}):
            fx = apply.Effects()
            new, body = apply_changes(todo_md.parse(text([])), {"source": "ai", "ops": [], "confirm": [
                self.entry(on_answer=bad)]}, human, TODAY, effects=fx)
            self.assertEqual(fx.pending, [], bad)
            self.assertIn("skip: bad on_answer rc:z", body)
            self.assertEqual(len(new.confirm), 3)

    def test_no_confirm_leaves_pending_alone(self):
        fx = apply.Effects()
        apply_changes(todo_md.parse(text([])), {"source": "ai", "ops": []}, human, TODAY, effects=fx)
        self.assertIsNone(fx.pending)


class ByAnswerCliTest(RepoMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.commit(text(CONFIRM[:2] + ["   回答:"] + CONFIRM[3:]), msg="todo(ai): 確認待ち1")
        self.commit(text(CONFIRM), msg="todo: 2026-11-10 10:00")

    def records(self):
        return decisions.load(self.repo / "todo-decisions.jsonl")

    def test_delete_records_intent_before_answer_and_blocks_re_add(self):
        r = self.run_apply({"source": "ai", "confirm": KEEP2, "ops": [
            {"op": "delete", "ref": "title:坂西さんの対応", "by_answer": BA}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("坂西さんの対応", self.todo.read_text(encoding="utf-8").split("## やる")[1])
        recs = self.records()
        self.assertEqual([(x["kind"], x["ref"]) for x in recs],
                         [("intent", "title:坂西さんの対応"), ("is_task", "title:坂西さんの対応")])
        self.assertEqual((recs[0]["by"], recs[0]["op"], recs[0]["by_answer"]), ("human", "delete", BA))
        self.assertEqual(decisions.deleted_refs(recs), ["title:坂西さんの対応"])
        self.assertIsNotNone(decisions.already_answered(recs, "title:坂西さんの対応", "is_task"))
        self.assertTrue(self.head("%s").startswith("todo(ai): "))
        r = self.run_apply({"source": "ai", "ops": [{"op": "add", "section": "待ち", "title": "坂西さんの対応"}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("坂西さんの対応", self.todo.read_text(encoding="utf-8").split("## やる")[1])

    def test_out_of_scope_delete_changes_nothing(self):
        before = self.todo.read_text(encoding="utf-8")
        r = self.run_apply({"source": "ai", "ops": [
            {"op": "delete", "ref": "title:インターン資料修正", "by_answer": BA}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), before)
        self.assertEqual(self.records(), [])

    def test_conflict_answer_acted_on_is_not_superseded(self):
        confirm = ["1. 完了にした件がまだ開いている。どうする？ [conflict epc#1100]", "   A 完了のまま★ / B 戻す", "   回答:"]
        self.commit(text(confirm), msg="todo(ai): 確認待ち1")
        self.commit(text(confirm[:2] + ["   回答: B"]))
        r = self.run_apply({"source": "ai", "confirm": [], "ops": [
            {"op": "move", "ref": "epc#1100", "to": "やる", "by_answer": {"ref": "epc#1100", "kind": "conflict"}}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        recs = self.records()
        self.assertEqual([x["kind"] for x in recs], ["intent", "conflict", "revert_move"])
        self.assertIsNotNone(decisions.already_answered(recs, "epc#1100", "conflict"))
        self.assertEqual(decisions.pinned_sections(recs, "epc#1100"), ["完了"])

    def dirty(self):
        return [l for l in git(self.repo, "status", "--porcelain").splitlines()
                if l not in ("?? changes.json", "?? .todo.write.lock")]

    def test_pending_written_committed_and_cleared(self):
        entry = dict(KEEP2[0], on_answer={"A": [{"op": "set_next", "ref": "epc#1163", "next": "x"}]})
        r = self.run_apply({"source": "ai", "ops": [], "confirm": [entry]})
        self.assertEqual(r.returncode, 0, r.stderr)
        pending = json.loads((self.repo / "todo-pending.json").read_text(encoding="utf-8"))
        self.assertEqual([(p["ref"], p["kind"]) for p in pending["blocks"]], [("epc#1163", "policy")])
        self.assertEqual(self.dirty(), [])
        self.assertIn("todo-pending.json", git(self.repo, "show", "--name-only", "--format=", "HEAD"))
        # 確認待ちが同じでも on_answer だけ変われば書き直してコミットする
        entry["on_answer"] = {"B": []}
        r = self.run_apply({"source": "ai", "ops": [], "confirm": [entry]})
        self.assertEqual(r.returncode, 0, r.stderr)
        pending = json.loads((self.repo / "todo-pending.json").read_text(encoding="utf-8"))
        self.assertEqual(pending["blocks"][0]["on_answer"], {"B": []})
        self.assertEqual(self.dirty(), [])
        r = self.run_apply({"source": "ai", "ops": [], "confirm": []})
        self.assertEqual(json.loads((self.repo / "todo-pending.json").read_text(encoding="utf-8")), {"blocks": []})
        self.assertEqual(self.dirty(), [])

    def test_no_pending_file_without_on_answer(self):
        r = self.run_apply({"source": "ai", "ops": [], "confirm": KEEP2})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((self.repo / "todo-pending.json").exists())

    def test_kept_answer_is_not_recorded_and_stays_visible_to_context(self):
        r = self.run_apply({"source": "ai", "ops": [], "confirm": KEEP2, "keep_answered": [BA],
                            "answered": [{"ref": BA["ref"], "kind": BA["kind"], "answer": CONFIRM[2].split(":", 1)[1]}]})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.records(), [])
        out = context.build(self.todo, self.repo / "todo-decisions.jsonl", TODAY)
        self.assertEqual(out["confirm_errors"], [])
        self.assertEqual([(a["ref"], a["answer"]) for a in out["answered_now"]],
                         [("title:坂西さんの対応", "これは対応済み。インターン資料修正も要らない")])


if __name__ == "__main__":
    unittest.main()
