import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import review

REVIEW = str(HERE / "review.py")


def jl(path, recs):
    Path(path).write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in recs), encoding="utf-8")


def put(logs, date, name, data):
    d = Path(logs) / date
    d.mkdir(parents=True, exist_ok=True)
    (d / name).write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


class Review(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dec = Path(self.tmp.name) / "d.jsonl"
        self.logs = Path(self.tmp.name) / "logs"
        self.logs.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def test_joins_reason_and_evidence(self):
        jl(self.dec, [
            {"ts": "2026-11-09T10:00:00+09:00", "ref": "epc#1", "kind": "revert_move", "value": "やる", "by": "human"},
            {"ts": "2026-11-09T10:00:00+09:00", "ref": "epc#2", "kind": "is_task", "value": "不要", "by": "human"},
            {"ts": "2026-10-01T10:00:00+09:00", "ref": "epc#9", "kind": "reject_add", "value": "やる", "by": "human"},
        ])
        put(self.logs, "2026-11-08", "changes.json", {"ops": [
            {"op": "move", "ref": "epc#1", "to": "待ち", "reason": "レビュー待ちに見えた | 要確認"}], "confirm": []})
        put(self.logs, "2026-11-08", "my-tasks.json", {"candidates": [
            {"key": "epc#1", "ball": "theirs", "evidence": "approve 待ち"}]})
        out = review.render(self.dec, self.logs, "2026-11-03")
        self.assertIn("epc#1", out)
        self.assertIn("move → 待ち", out)
        self.assertIn("レビュー待ちに見えた \\| 要確認", out)
        self.assertIn("approve 待ち", out)
        self.assertIn("theirs", out)
        self.assertIn("epc#2", out)
        self.assertNotIn("epc#9", out)

    def test_missing_logs_prints_dash(self):
        jl(self.dec, [{"ts": "2026-11-09T10:00:00+09:00", "ref": "epc#1", "kind": "reject_add", "value": "やる", "by": "human"}])
        out = review.render(self.dec, self.logs / "none", "2026-11-03")
        row = [l for l in out.splitlines() if "epc#1" in l][0]
        self.assertEqual(row.count("| - "), 4)

    def test_confirm_question_as_ai_action_and_no_records(self):
        jl(self.dec, [{"ts": "2026-11-09T10:00:00+09:00", "ref": "title:x", "kind": "is_task", "value": "追加", "by": "human"}])
        put(self.logs, "2026-11-09", "changes.json", {"ops": [], "confirm": [
            {"ref": "title:x", "kind": "is_task", "question": "これはタスク？"}]})
        self.assertIn("確認待ち(is_task): これはタスク？", review.render(self.dec, self.logs, "2026-11-03"))
        self.assertIn("訂正なし", review.render(self.dec, self.logs, "2026-12-01"))

    def test_ignores_later_log_than_record(self):
        jl(self.dec, [{"ts": "2026-11-05T10:00:00+09:00", "ref": "epc#1", "kind": "revert_move", "value": "やる", "by": "human"}])
        put(self.logs, "2026-11-08", "changes.json", {"ops": [{"op": "move", "ref": "epc#1", "to": "完了", "reason": "later"}]})
        self.assertNotIn("later", review.render(self.dec, self.logs, "2026-11-03"))

    def test_cli_bad_json_log_does_not_fail(self):
        jl(self.dec, [{"ts": "2026-11-09T10:00:00+09:00", "ref": "epc#1", "kind": "reject_add", "value": "やる", "by": "human"}])
        d = self.logs / "2026-11-08"
        d.mkdir()
        (d / "changes.json").write_text("{broken")
        r = subprocess.run([sys.executable, "-I", REVIEW, "--since", "2026-11-03", "--decisions", str(self.dec),
                            "--logs", str(self.logs)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("epc#1", r.stdout)


if __name__ == "__main__":
    unittest.main()
