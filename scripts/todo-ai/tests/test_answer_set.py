"""answer_set.py: 確認待ちの回答欄を (ref, kind) で特定して書き、人のコミットにしてから answers.py で反映する。"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import todo_md

ANSWER_SET = str(HERE / "answer_set.py")
APPLY = str(HERE / "apply.py")
TODAY = "2026-11-10"

BASE = """# TODO

## 確認待ち

## やる
- [ ] インターン資料修正

## 待ち
- [ ] 坂西さんの対応

## 完了
"""

IS_TASK = {"ref": "title:z の件", "kind": "is_task", "question": "『z の件』をタスクに足す？", "facts": "",
           "options": [{"label": "A", "text": "追加する（やる）", "recommended": True},
                       {"label": "B", "text": "タスクではない（追加しない）"}],
           "on_answer": {"A": [{"op": "add", "section": "やる", "title": "z の件", "reason": "回答 A"}], "B": []}}
STILL = {"ref": "title:坂西さんの対応", "kind": "still_needed", "question": "坂西さんの対応はまだ要る？", "facts": "",
         "options": [{"label": "A", "text": "要る", "recommended": True}, {"label": "B", "text": "不要（完了にする）"}],
         "on_answer": {"A": [], "B": [{"op": "move", "ref": "title:坂西さんの対応", "to": "完了"}]}}


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args],
                          check=True, capture_output=True, text=True).stdout


class AnswerSetTest(unittest.TestCase):
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
        cf = Path(self._t.name) / "ask.json"
        cf.write_text(json.dumps({"source": "ai", "ops": [], "confirm": [IS_TASK, STILL]}, ensure_ascii=False),
                      encoding="utf-8")
        r = subprocess.run([sys.executable, APPLY, "--changes", str(cf), "--todo", str(self.todo), "--today", TODAY],
                           capture_output=True, text=True, env=self.env())
        self.assertEqual(r.returncode, 0, r.stderr)

    def env(self):
        env = {k: v for k, v in os.environ.items() if k not in ("TODO_MD_PATH", "TODO_AI_DENY_USER")}
        env.update(LANG="C.UTF-8", GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
                   GIT_COMMITTER_EMAIL="t@t")
        return env

    def run_set(self, answers):
        return subprocess.run([sys.executable, ANSWER_SET, "--answers", json.dumps(answers, ensure_ascii=False),
                               "--todo", str(self.todo), "--log-dir", str(self.logs), "--today", TODAY],
                              capture_output=True, text=True, env=self.env())

    def doc(self):
        return todo_md.parse(self.todo.read_text(encoding="utf-8"))

    def subjects(self):
        return git(self.repo, "log", "--format=%s").splitlines()

    def test_writes_answers_commits_as_human_and_reflects(self):
        r = self.run_set([{"ref": "title:z の件", "kind": "is_task", "answer": "A"},
                          {"ref": "title:坂西さんの対応", "kind": "still_needed", "answer": "B"}])
        self.assertEqual(r.returncode, 0, r.stderr)
        subj = self.subjects()
        self.assertTrue(subj[0].startswith("todo(ai): "), subj)
        self.assertTrue(subj[1].startswith("todo: "), subj)
        self.assertIn(f"反映: {subj[0]}", r.stdout)
        human = git(self.repo, "show", "HEAD~1", "--", "todo.md")
        self.assertIn("+   回答:A", human)
        self.assertIn("+   回答:B", human)
        d = self.doc()
        self.assertIn("z の件", [it.title for it in d.sections["やる"]])
        self.assertIn("坂西さんの対応", [it.title for it in d.sections["完了"]])
        self.assertEqual([l for l in d.confirm if l.strip()], [])

    def test_free_text_is_written_but_left_for_todo(self):
        r = self.run_set([{"ref": "title:z の件", "kind": "is_task", "answer": "もう済んでるかも"}])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(self.subjects()[0].startswith("todo: "))
        self.assertIn("反映なし", r.stdout)
        self.assertIn("   回答:もう済んでるかも", self.todo.read_text(encoding="utf-8").split("\n"))

    def test_unknown_block_changes_nothing(self):
        before = self.todo.read_text(encoding="utf-8")
        r = self.run_set([{"ref": "title:z の件", "kind": "is_task", "answer": "A"},
                          {"ref": "title:無い問い", "kind": "is_task", "answer": "B"}])
        self.assertEqual(r.returncode, 2)
        self.assertIn("title:無い問い", r.stderr)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), before)

    def test_kind_must_match(self):
        r = self.run_set([{"ref": "title:z の件", "kind": "still_needed", "answer": "A"}])
        self.assertEqual(r.returncode, 2)
        self.assertIn("answer_set: 未適用", r.stderr)

    def test_does_not_overwrite_a_different_answer(self):
        lines = self.todo.read_text(encoding="utf-8").split("\n")
        lines[lines.index("   回答:")] = "   回答:B"
        self.todo.write_text("\n".join(lines), encoding="utf-8")
        git(self.repo, "commit", "-q", "-am", "todo: 2026-11-10 09:00")
        before = self.todo.read_text(encoding="utf-8")
        r = self.run_set([{"ref": "title:z の件", "kind": "is_task", "answer": "A"}])
        self.assertEqual(r.returncode, 2)
        self.assertIn("回答済み", r.stderr)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), before)

    def test_rejects_bad_spec(self):
        for bad in ([{"ref": "title:z の件", "kind": "is_task", "answer": "A\nB"}],
                    [{"ref": "title:z の件", "kind": "is_task", "answer": "  "}],
                    [{"ref": "title:z の件", "answer": "A"}],
                    [], {"ref": "x"}):
            r = self.run_set(bad)
            self.assertEqual(r.returncode, 2, bad)
            self.assertIn("answer_set: 未適用", r.stderr)

    def test_refuses_in_unattended_run(self):
        before = self.todo.read_text(encoding="utf-8")
        env = dict(self.env(), TODO_AI_DENY_USER="1")
        r = subprocess.run([sys.executable, ANSWER_SET, "--answers",
                            json.dumps([{"ref": "title:z の件", "kind": "is_task", "answer": "A"}], ensure_ascii=False),
                            "--todo", str(self.todo), "--log-dir", str(self.logs), "--today", TODAY],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 2)
        self.assertIn("TODO_AI_DENY_USER", r.stderr)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), before)

    def test_unreadable_pending_is_not_reflected(self):
        (self.repo / "todo-pending.json").write_text("{broken", encoding="utf-8")
        git(self.repo, "add", "todo-pending.json")
        git(self.repo, "commit", "-q", "-m", "x")
        r = self.run_set([{"ref": "title:z の件", "kind": "is_task", "answer": "A"}])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("反映なし", r.stdout)

    def test_reports_failed_reflection(self):
        bad = Path(self._t.name) / "decisions-dir"
        bad.mkdir()
        r = subprocess.run([sys.executable, ANSWER_SET, "--answers",
                            json.dumps([{"ref": "title:z の件", "kind": "is_task", "answer": "A"}], ensure_ascii=False),
                            "--todo", str(self.todo), "--decisions", str(bad), "--log-dir", str(self.logs),
                            "--today", TODAY], capture_output=True, text=True, env=self.env())
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertIn("反映失敗", r.stdout)
        self.assertIn("   回答:A", self.todo.read_text(encoding="utf-8").split("\n"))

    def test_skips_while_nvim_is_editing(self):
        (self.repo / ".todo.lock").write_text(str(os.getpid()), encoding="utf-8")
        before = self.todo.read_text(encoding="utf-8")
        r = self.run_set([{"ref": "title:z の件", "kind": "is_task", "answer": "A"}])
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.todo.read_text(encoding="utf-8"), before)


if __name__ == "__main__":
    unittest.main()
