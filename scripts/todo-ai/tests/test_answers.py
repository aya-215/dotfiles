"""answers.py: 確認待ちの選択肢の文字1つだけの回答を、保存済みの変更案（on_answer）で AI なしに反映する。"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import context
import decisions
import todo_md

ANSWERS = str(HERE / "answers.py")
APPLY = str(HERE / "apply.py")
TODAY = "2026-11-10"

BASE = """# TODO

## 確認待ち

## やる
- [ ] インターン資料修正
- [ ] PR レビュー [epc#1163](https://github.com/x/epc/pull/1163) — next: 読む

## 待ち
- [ ] 坂西さんの対応

## 完了
- [x] 済んだ [epc#1100](https://github.com/x/epc/pull/1100) (done: 2026-11-01)
"""

ADD_Z = {"op": "add", "section": "やる", "title": "z の件", "reason": "is_task の回答"}
IS_TASK = {"ref": "title:z の件", "kind": "is_task", "question": "『z の件』をタスクに足す？", "facts": "期限 11/14",
           "options": [{"label": "A", "text": "追加する（やる）", "recommended": True},
                       {"label": "B", "text": "タスクではない（追加しない）"}],
           "on_answer": {"A": [ADD_Z], "B": []}}
STILL = {"ref": "title:坂西さんの対応", "kind": "still_needed", "question": "『坂西さんの対応』はまだ要る？", "facts": "",
         "options": [{"label": "A", "text": "要る", "recommended": True}, {"label": "B", "text": "不要（完了にする）"}],
         "on_answer": {"B": [{"op": "move", "ref": "title:坂西さんの対応", "to": "完了"}]}}
POLICY = {"ref": "epc#1163", "kind": "policy", "question": "方針は？", "facts": "",
          "options": [{"label": "A", "text": "x", "recommended": True}, {"label": "B", "text": "y"}]}


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args],
                          check=True, capture_output=True, text=True).stdout


class AnswersTest(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.repo = Path(self._t.name) / "memo"
        self.repo.mkdir()
        (self.repo / ".gitignore").write_text(".todo.lock\n.todo.write.lock\n.*.tmp\n", encoding="utf-8")
        self.logs = Path(self._t.name) / "log"
        self.todo = self.repo / "todo.md"
        git(self.repo, "init", "-q")
        self.todo.write_text(BASE, encoding="utf-8")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-q", "-m", "todo: 2026-11-01 10:00")

    def env(self):
        env = {k: v for k, v in os.environ.items() if k not in ("TODO_MD_PATH", "TODO_AI_DENY_USER")}
        env.update(LANG="C.UTF-8", GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
                   GIT_COMMITTER_EMAIL="t@t")
        return env

    def ask(self, *entries):
        cf = Path(self._t.name) / "ask.json"
        cf.write_text(json.dumps({"source": "ai", "ops": [], "confirm": list(entries)}, ensure_ascii=False),
                      encoding="utf-8")
        r = subprocess.run([sys.executable, APPLY, "--changes", str(cf), "--todo", str(self.todo), "--today", TODAY],
                           capture_output=True, text=True, env=self.env())
        self.assertEqual(r.returncode, 0, r.stderr)

    def answer(self, *answers):
        """確認待ちの回答欄に、上から順に answers を書いて人のコミットにする（None はそのまま）。"""
        lines = self.todo.read_text(encoding="utf-8").split("\n")
        it = iter(answers)
        for i, l in enumerate(lines):
            if l == "   回答:":
                a = next(it, None)
                if a is not None:
                    lines[i] = "   回答:" + a
        self.todo.write_text("\n".join(lines), encoding="utf-8")
        git(self.repo, "commit", "-q", "-am", "todo: 2026-11-10 10:00")

    def run_answers(self, *extra, env_todo=True):
        env = self.env()
        if env_todo:
            env["TODO_MD_PATH"] = str(self.todo)
        return subprocess.run([sys.executable, ANSWERS, "--log-dir", str(self.logs), "--today", TODAY, *extra],
                              capture_output=True, text=True, env=env)

    def head(self):
        return git(self.repo, "rev-parse", "HEAD").strip()

    def records(self):
        return decisions.load(self.repo / "todo-decisions.jsonl")

    def doc(self):
        return todo_md.parse(self.todo.read_text(encoding="utf-8"))

    def logs_written(self):
        return sorted(p.name.rsplit(".", 1)[1] for p in self.logs.rglob("answers-*")) if self.logs.exists() else []

    def assert_untouched(self, r, head):
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.head(), head)
        self.assertEqual(self.logs_written(), [])

    def test_fullwidth_letter_applies_its_ops_and_keeps_the_rest(self):
        self.ask(IS_TASK, POLICY)
        self.answer("Ａ")
        r = self.run_answers()
        self.assertEqual(r.returncode, 0, r.stderr)
        doc = self.doc()
        self.assertEqual([it.title for it in doc.sections["やる"]][-1], "z の件")
        self.assertEqual(doc.confirm, ["1. 方針は？ [policy epc#1163]", "   A x★ / B y", "   回答:"])
        self.assertEqual([(x["kind"], x["ref"]) for x in self.records()],
                         [("intent", "title:z の件"), ("is_task", "title:z の件")])
        self.assertEqual(self.records()[0]["by_answer"], {"ref": "title:z の件", "kind": "is_task"})
        self.assertIn("A 追加する（やる）", self.records()[0]["value"])
        self.assertTrue(git(self.repo, "log", "-1", "--format=%s").startswith("todo(ai): "))
        self.assertEqual(self.logs_written(), ["err", "json", "out"])
        pending = json.loads((self.repo / "todo-pending.json").read_text(encoding="utf-8"))
        self.assertEqual(pending, {"blocks": []})

    def test_lowercase_letter_moves_the_human_line_named_by_the_block(self):
        self.ask(POLICY, STILL)
        self.answer(None, " b ")
        r = self.run_answers()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.doc().sections["完了"][0].title, "坂西さんの対応")
        self.assertEqual(self.records()[-1], {**self.records()[-1], "kind": "still_needed", "value": "b"})

    def test_letter_answers_keep_on_answer_of_unanswered_blocks(self):
        self.ask(IS_TASK, STILL)
        self.answer("A")
        r = self.run_answers()
        self.assertEqual(r.returncode, 0, r.stderr)
        b, = context.build(self.todo, self.repo / "todo-decisions.jsonl", TODAY)["confirm_blocks"]
        self.assertEqual((b["ref"], b["on_answer"]), ("title:坂西さんの対応", STILL["on_answer"]))

    def test_free_text_answer_and_mixed_answers(self):
        self.ask(IS_TASK, STILL)
        self.answer("A にしておいて")
        self.assert_untouched(self.run_answers(), self.head())
        # 文字の回答だけ反映し、文の回答は回答欄ごと残して次の /todo に回す
        git(self.repo, "reset", "-q", "--hard", "HEAD~1")
        self.answer("A", "これは坂西さんに聞く")
        r = self.run_answers()
        self.assertEqual(r.returncode, 0, r.stderr)
        doc = self.doc()
        self.assertEqual([it.title for it in doc.sections["やる"]][-1], "z の件")
        self.assertEqual(doc.sections["待ち"][0].title, "坂西さんの対応")
        self.assertEqual(doc.confirm[-1], "   回答:これは坂西さんに聞く")
        self.assertEqual([x["ref"] for x in self.records()], ["title:z の件", "title:z の件"])
        out = context.build(self.todo, self.repo / "todo-decisions.jsonl", TODAY)
        self.assertEqual(out["confirm_errors"], [])
        self.assertEqual([(a["ref"], a["answer"]) for a in out["answered_now"]],
                         [("title:坂西さんの対応", "これは坂西さんに聞く")])

    def test_letter_not_in_options_or_without_ops_is_left_alone(self):
        self.ask(IS_TASK, STILL)
        self.answer("C", "A")
        self.assert_untouched(self.run_answers(), self.head())

    def test_no_pending_is_left_alone(self):
        self.ask(POLICY)
        self.answer("A")
        self.assertFalse((self.repo / "todo-pending.json").exists())
        self.assert_untouched(self.run_answers(), self.head())

    def test_pending_for_a_different_question_is_not_used(self):
        self.ask(IS_TASK)
        p = self.repo / "todo-pending.json"
        data = json.loads(p.read_text(encoding="utf-8"))
        data["blocks"][0]["line"] = "『z の件』を足す？ [is_task title:z の件]"
        p.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        git(self.repo, "commit", "-q", "-am", "todo: pending を変えた")
        self.answer("A")
        self.assert_untouched(self.run_answers(), self.head())

    def test_human_edited_block_is_left_alone(self):
        self.ask(IS_TASK)
        self.todo.write_text(self.todo.read_text(encoding="utf-8").replace("足す？", "足す？急ぎ"), encoding="utf-8")
        git(self.repo, "commit", "-q", "-am", "todo: 問いを書き換えた")
        self.answer("A")
        self.assert_untouched(self.run_answers(), self.head())

    def test_stale_conflict_answer_is_left_for_todo(self):
        conflict = {"ref": "epc#1100", "kind": "conflict", "question": "完了にした件がまだ開いている。どうする？",
                    "facts": "", "options": [{"label": "A", "text": "完了のまま", "recommended": True},
                                             {"label": "B", "text": "やるに戻す"}],
                    "on_answer": {"B": [{"op": "move", "ref": "epc#1100", "to": "やる"}]}}
        self.ask(conflict)
        with open(self.repo / "todo-decisions.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps({"ref": "epc#1100", "kind": "intent", "value": "完了のまま", "op": "note",
                                "by": "human"}, ensure_ascii=False) + "\n")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-q", "-m", "todo(user): 意図")
        self.answer("B")
        self.assert_untouched(self.run_answers(), self.head())

    def test_conflict_answer_reopens_and_is_not_asked_again(self):
        conflict = {"ref": "epc#1100", "kind": "conflict", "question": "完了にした件がまだ開いている。どうする？",
                    "facts": "", "options": [{"label": "A", "text": "完了のまま", "recommended": True},
                                             {"label": "B", "text": "やるに戻す"}],
                    "on_answer": {"B": [{"op": "move", "ref": "epc#1100", "to": "やる"}]}}
        self.ask(conflict)
        self.answer("B")
        r = self.run_answers()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.doc().sections["やる"][-1].key, "epc#1100")
        recs = self.records()
        self.assertIsNotNone(decisions.already_answered(recs, "epc#1100", "conflict"))
        self.assertEqual(decisions.pinned_sections(recs, "epc#1100"), ["完了"])

    def test_carried_conflict_block_leaves_everything_for_todo(self):
        # 確認待ちを書き直すと conflict の回答が古いかの基準（問いを書いたコミット）が動くので、conflict を持ち越さない
        conflict = {"ref": "epc#1100", "kind": "conflict", "question": "完了にした件がまだ開いている。どうする？",
                    "facts": "", "options": [{"label": "A", "text": "完了のまま", "recommended": True},
                                             {"label": "B", "text": "やるに戻す"}],
                    "on_answer": {"A": [], "B": [{"op": "move", "ref": "epc#1100", "to": "やる"}]}}
        self.ask(conflict, IS_TASK)
        with open(self.repo / "todo-decisions.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps({"ref": "epc#1100", "kind": "intent", "value": "完了のまま", "op": "note",
                                "by": "human"}, ensure_ascii=False) + "\n")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-q", "-m", "todo(user): 意図")
        self.answer("B", "A")
        self.assert_untouched(self.run_answers(), self.head())
        out = context.build(self.todo, self.repo / "todo-decisions.jsonl", TODAY)
        self.assertEqual([(a["ref"], a["superseded"]) for a in out["answered_now"]],
                         [("epc#1100", True), ("title:z の件", False)])
        git(self.repo, "reset", "-q", "--hard", "HEAD~1")
        self.answer(None, "A")
        self.assert_untouched(self.run_answers(), self.head())

    def test_on_answer_with_an_op_answers_cannot_run_is_not_saved(self):
        self.ask(dict(IS_TASK, on_answer={"A": [{"op": "order", "section": "やる", "refs": []}]}))
        self.assertIn("skip: bad on_answer title:z の件", git(self.repo, "log", "-1", "--format=%b"))
        self.answer("A")
        self.assert_untouched(self.run_answers(), self.head())

    def test_choice_whose_ops_would_skip_is_left_for_todo(self):
        self.ask(IS_TASK, STILL)
        t = self.todo.read_text(encoding="utf-8").replace("- [ ] 坂西さんの対応", "- [ ] 坂西さんの対応（済）")
        self.todo.write_text(t, encoding="utf-8")
        git(self.repo, "commit", "-q", "-am", "todo: rename")
        self.answer(None, "B")
        self.assert_untouched(self.run_answers(), self.head())
        # 効かない選択だけ回答欄ごと残し、効く選択は反映する
        git(self.repo, "reset", "-q", "--hard", "HEAD~1")
        self.answer("A", "B")
        r = self.run_answers()
        self.assertEqual(r.returncode, 0, r.stderr)
        doc = self.doc()
        self.assertEqual([it.title for it in doc.sections["やる"]][-1], "z の件")
        self.assertEqual(doc.sections["待ち"][0].title, "坂西さんの対応（済）")
        self.assertEqual(doc.confirm[-1], "   回答:B")
        self.assertEqual([(x["kind"], x["ref"]) for x in self.records()],
                         [("intent", "title:z の件"), ("is_task", "title:z の件")])
        self.assertNotIn("skip:", git(self.repo, "log", "-1", "--format=%b"))

    def test_log_names_carry_pid_and_any_error_is_logged(self):
        self.ask(IS_TASK)
        self.answer("A")
        r = self.run_answers()
        self.assertEqual(r.returncode, 0, r.stderr)
        names = [p.name for p in self.logs.rglob("answers-*")]
        self.assertTrue(names and all(len(n.split(".")[0].split("-")) == 3 for n in names), names)
        os.chmod(self.todo, 0)
        try:
            r = self.run_answers()
        finally:
            os.chmod(self.todo, 0o644)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr, "")
        err, = [p for p in self.logs.rglob("answers-*.err") if "PermissionError" in p.read_text(encoding="utf-8")]

    def test_nvim_editing_propagates_apply_exit_and_logs(self):
        self.ask(IS_TASK)
        self.answer("A")
        (self.repo / ".todo.lock").write_text(str(os.getpid()), encoding="utf-8")
        head = self.head()
        r = self.run_answers()
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.head(), head)
        self.assertEqual(self.logs_written(), ["err", "json", "out"])

    def test_todo_argument_and_unreadable_todo(self):
        self.ask(IS_TASK)
        self.answer("A")
        r = self.run_answers("--todo", str(self.todo), env_todo=False)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([it.title for it in self.doc().sections["やる"]][-1], "z の件")
        r = self.run_answers("--todo", str(self.repo / "nope.md"), env_todo=False)
        self.assertEqual(r.returncode, 1)
        self.assertIn("err", self.logs_written())


if __name__ == "__main__":
    unittest.main()
