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

    def test_no_ai_commit(self):
        self.r.commit(doc(yaru=L), "todo: base")
        self.assertEqual(decisions.detect_reverts(self.r.dir, "todo.md"), [])


class Records(unittest.TestCase):
    def test_load_append_pinned_answered(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "d.jsonl"
            self.assertEqual(decisions.load(p), [])
            decisions.append(p, [{"ts": "x", "ref": "a", "kind": "revert_move", "value": "やる", "by": "human"}])
            decisions.append(p, [{"ts": "y", "ref": "b", "kind": "policy", "value": "A", "by": "human"}])
            recs = decisions.load(p)
            self.assertEqual(len(recs), 2)
            self.assertTrue(decisions.is_pinned(recs, "a"))
            self.assertFalse(decisions.is_pinned(recs, "b"))
            self.assertEqual(decisions.already_answered(recs, "b", "policy")["value"], "A")
            self.assertIsNone(decisions.already_answered(recs, "b", "manual"))


CONF = "1. 方針は？\n   事実: f\n   選択: A x / B y\n   回答: A\n"


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

    def test_not_recorded_on_validation_failure(self):
        self.r.commit(doc(yaru=L, confirm=CONF), "todo(ai): base")
        res = self.run_apply({"source": "ai", "ops": [], "confirm": [], "answered": []})
        self.assertEqual(res.returncode, 2)
        self.assertFalse((self.r.dir / "todo-decisions.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
