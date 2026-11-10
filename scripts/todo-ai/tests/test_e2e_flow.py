"""/todo スキルが頼る契約を、移行済み todo.md → context.py → 変更案 → apply.py の通しで固定する。

変更案は SKILL.md の規則に従って手で書いたもの（モデルの出力の代わり）。
"""
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
import migrate
import my_tasks_schema
import todo_md
from context import with_tag

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "my-tasks-sample.json"
TODAY = "2026-11-10"
ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin", "LANG": "C.UTF-8",
       "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}

OLD = """# TODO

- [ ] インターン資料修正
- [ ] 坂西さんへの返信 [rc:old1](https://rc.example/direct/x?msg=old1)
## 待ち
- [ ] PR#1202 レビュー待ち [epc#1202](https://github.com/ebase-dev/ebase-portal-chat/pull/1202)
## 完了
- [x] 済んだこと
"""


class E2EFlow(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.dir = Path(self._t.name)
        self.todo = self.dir / "todo.md"
        self.logs = self.dir / "log"
        self.logs.mkdir()
        self.git("init", "-q")

    def git(self, *args, date=None):
        env = dict(ENV)
        if date:
            env.update(GIT_AUTHOR_DATE=f"{date}T10:00:00+09:00", GIT_COMMITTER_DATE=f"{date}T10:00:00+09:00")
        return subprocess.run(["git", "-C", str(self.dir), *args], check=True, capture_output=True,
                              text=True, env=env).stdout

    def human_commit(self, text, date):
        self.todo.write_text(text, encoding="utf-8")
        self.git("add", "todo.md")
        self.git("commit", "-q", "-m", f"todo: {date} 10:00", date=date)

    def script(self, name, *args):
        return subprocess.run([sys.executable, str(HERE / name), *args], capture_output=True, text=True, env=ENV)

    def context(self):
        res = self.script("context.py", "--todo", str(self.todo), "--today", TODAY)
        self.assertEqual(res.returncode, 0, res.stderr)
        return json.loads(res.stdout)

    def apply(self, changes, n):
        cp = self.logs / f"changes-{n}.json"
        cp.write_text(json.dumps(changes, ensure_ascii=False), encoding="utf-8")
        return self.script("apply.py", "--changes", str(cp), "--todo", str(self.todo), "--today", TODAY)

    def section(self, name):
        return todo_md.parse(self.todo.read_text(encoding="utf-8")).sections[name]

    def records(self):
        return decisions.load(self.dir / decisions.DECISIONS_NAME)

    def test_add_attach_confirm_answer_and_not_reasked(self):
        self.human_commit(migrate.migrate(OLD), "2026-10-01")
        cands = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(my_tasks_schema.validate_candidates(cands), [])

        # 1回目: 候補の取り込みと確認待ちの作成
        ctx = self.context()
        old = {i["ref"]: i for i in ctx["items"]}
        self.assertEqual((old["rc:old1"]["origin"], old["rc:old1"]["age_days"]), ("human", 40))
        self.assertEqual(ctx["confirm_blocks"], [])
        is_task_ref = "title:合田さんへのコンテナ設置依頼の返信"
        res = self.apply({"source": "ai", "ops": [
            {"op": "add", "section": "やる", "key": "epc#1163",
             "url": "https://github.com/ebase-dev/ebase-portal-chat/pull/1163",
             "title": "PR#1163 レビュー指摘対応", "next": "N1,N2 を直して push", "reason": "自分の PR に未対応指摘"},
            {"op": "add", "section": "待ち", "key": "gb:tamaki-ai-training#42",
             "url": "https://gitbucket.example/AI_dev/tamaki-ai-training/pull/42",
             "title": "研修PR#42 の再レビュー", "next": "玉木さんの修正待ち", "reason": "Request Changes 済み"},
            {"op": "attach", "ref": "title:インターン資料修正", "key": "rc:Xk3p9aQ2#1",
             "url": "https://rc.example/channel/dev-team?msg=Xk3p9aQ2", "next": "スライド3の数値を差し替えて共有",
             "reason": "同じ作業の依頼発言"},
            {"op": "order", "section": "やる", "refs": ["epc#1163", "rc:Xk3p9aQ2#1"]},
        ], "confirm": [
            {"ref": "rc:old1", "kind": "still_needed",
             "question": with_tag("坂西さんへの返信はまだ要る？", "still_needed", "rc:old1"),
             "facts": "追加から40日、直近2週間に決着・進展の発言なし",
             "options": [{"label": "A", "text": "要る", "recommended": False},
                         {"label": "B", "text": "不要（完了にする）", "recommended": True}]},
            {"ref": is_task_ref, "kind": "is_task",
             "question": with_tag("合田さんへのコンテナ設置依頼の返信はタスク？", "is_task", is_task_ref),
             "facts": "Sent に「Re: コンテナ設置のお願い」あり",
             "options": [{"label": "A", "text": "タスクとして追加", "recommended": False},
                         {"label": "B", "text": "タスクではない", "recommended": True}]},
        ]}, 1)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue(self.git("log", "-1", "--format=%s").startswith("todo(ai): "))
        self.assertEqual([it.ref for it in self.section("やる")], ["epc#1163", "rc:Xk3p9aQ2#1", "rc:old1"])
        self.assertEqual(self.section("やる")[1].title, "インターン資料修正")

        # 人が確認待ちの1件目に回答する（nvim のポップアップを閉じたときのコミット）
        text = self.todo.read_text(encoding="utf-8")
        self.assertEqual(text.count("   回答:\n"), 2)
        self.human_commit(text.replace("   回答:\n", "   回答: B\n", 1), "2026-11-10")

        # 2回目: 回答の反映（context の answered_now をそのまま渡し、未回答の問いは写し直す）
        ctx = self.context()
        self.assertEqual(ctx["confirm_errors"], [])
        self.assertEqual(ctx["answered_now"], [{"ref": "rc:old1", "kind": "still_needed", "answer": "B"}])
        keep = [{k: b[k] for k in ("ref", "kind", "question", "facts", "options")}
                for b in ctx["confirm_blocks"] if not b["answer"]]
        res = self.apply({"source": "ai", "ops": [
            {"op": "move", "ref": "rc:old1", "to": "完了", "reason": "確認待ちの回答 B（不要）"},
        ], "confirm": keep, "answered": ctx["answered_now"]}, 2)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual([(r["ref"], r["kind"], r["value"]) for r in self.records()],
                         [("rc:old1", "still_needed", "B")])
        done = {it.ref: it for it in self.section("完了")}
        self.assertEqual(done["rc:old1"].done_date, TODAY)
        self.assertIn("title:済んだこと", done)

        # 3回目: 同じ問いは出ない
        ctx = self.context()
        self.assertEqual([(b["ref"], b["kind"]) for b in ctx["confirm_blocks"]], [(is_task_ref, "is_task")])
        self.assertEqual(ctx["answered_now"], [])
        self.assertIn({"ref": "rc:old1", "kind": "still_needed", "value": "B", "ts": self.records()[0]["ts"]},
                      ctx["answered_refs"])
        self.assertIsNotNone(decisions.already_answered(self.records(), "rc:old1", "still_needed"))
        keep = [{k: b[k] for k in ("ref", "kind", "question", "facts", "options")} for b in ctx["confirm_blocks"]]
        head = self.git("rev-parse", "HEAD")
        res = self.apply({"source": "ai", "ops": [], "confirm": keep, "answered": ctx["answered_now"]}, 3)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual(len(self.records()), 1)

    def test_human_edited_question_reported_and_ops_still_apply_without_confirm(self):
        self.human_commit(migrate.migrate(OLD), "2026-10-01")
        q = with_tag("坂西さんへの返信はまだ要る？", "still_needed", "rc:old1")
        res = self.apply({"source": "ai", "ops": [], "confirm": [
            {"ref": "rc:old1", "kind": "still_needed", "question": q, "facts": "40日",
             "options": [{"label": "A", "text": "要る"}]}]}, 1)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.human_commit(self.todo.read_text(encoding="utf-8").replace("事実: 40日", "事実: 40日、来週聞く"), "2026-11-10")

        ctx = self.context()
        self.assertEqual(len(ctx["confirm_errors"]), 1)
        # confirm を含めると apply は止まり続ける
        res = self.apply({"source": "ai", "ops": [], "confirm": []}, 2)
        self.assertEqual(res.returncode, 2)
        self.assertIn("確認待ち", res.stderr)
        # confirm を外せば他の op は通り、人の追記は残る
        res = self.apply({"source": "ai", "ops": [
            {"op": "set_next", "ref": "epc#1202", "next": "彌永さんのレビュー", "reason": "r"}]}, 3)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("来週聞く", self.todo.read_text(encoding="utf-8"))
        # 確認待ちに触れない AI/同期コミットの後も、人の追記は守られ続ける
        self.assertEqual(len(self.context()["confirm_errors"]), 1)
        res = self.apply({"source": "ai", "ops": [], "confirm": []}, 4)
        self.assertEqual(res.returncode, 2, res.stdout)
        self.assertIn("来週聞く", self.todo.read_text(encoding="utf-8"))
        res = self.apply({"source": "sync", "ops": [
            {"op": "move", "ref": "epc#1202", "to": "完了", "reason": "merged"}]}, 5)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(len(self.context()["confirm_errors"]), 1)
        res = self.apply({"source": "ai", "ops": [], "confirm": []}, 6)
        self.assertEqual(res.returncode, 2, res.stdout)
        self.assertIn("来週聞く", self.todo.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
