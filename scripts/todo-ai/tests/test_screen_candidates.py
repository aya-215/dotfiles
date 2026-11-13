import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import screen_candidates  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "my-tasks-sample.json"
SCRIPT = Path(__file__).resolve().parent.parent / "screen_candidates.py"


def load():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def cand(key=None, sources=("daily",)):
    return {"key": key, "url": None, "title": "t", "ball": "mine", "next": "n", "evidence": "e",
            "deadline": None, "waiting_person": None, "blocks": [], "sources": list(sources)}


class SelfNoteOnlyTest(unittest.TestCase):
    def test_daily_and_sessions_without_key(self):
        for src in (["daily"], ["sessions"], ["daily", "sessions"]):
            self.assertTrue(screen_candidates.self_note_only(cand(sources=src)), src)

    def test_other_source_keeps_candidate(self):
        for src in (["mail"], ["daily", "rocketchat"], ["sessions", "github"], ["worktree"]):
            self.assertFalse(screen_candidates.self_note_only(cand(sources=src)), src)

    def test_key_keeps_candidate(self):
        self.assertFalse(screen_candidates.self_note_only(cand(key="wt:hankyu", sources=["daily"])))


class ScreenTest(unittest.TestCase):
    def test_marks_each_candidate_and_keeps_order(self):
        data = load()
        out = screen_candidates.screen(copy.deepcopy(data))
        self.assertEqual([c["title"] for c in out["candidates"]], [c["title"] for c in data["candidates"]])
        flags = {c["title"]: c["self_note_only"] for c in out["candidates"]}
        self.assertTrue(flags["検証スクリプトのコミット先決め"])
        self.assertFalse(flags["検証環境の利用申請"])
        self.assertFalse(flags["PR#1163 レビュー指摘対応"])


class CliTest(unittest.TestCase):
    def run_cli(self, path):
        return subprocess.run([sys.executable, "-I", str(SCRIPT), str(path)], capture_output=True, text=True)

    def test_writes_marked_json_and_lists_self_notes_on_stderr(self):
        res = self.run_cli(FIXTURE)
        self.assertEqual(res.returncode, 0, res.stderr)
        out = json.loads(res.stdout)
        self.assertEqual(sum(c["self_note_only"] for c in out["candidates"]), 1)
        self.assertIn("検証スクリプトのコミット先決め", res.stderr)

    def test_invalid_input_exits_1(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "x.json"
            d = load()
            del d["candidates"][0]["sources"]
            p.write_text(json.dumps(d), encoding="utf-8")
            res = self.run_cli(p)
        self.assertEqual((res.returncode, res.stdout), (1, ""))
        self.assertIn("sources", res.stderr)


if __name__ == "__main__":
    unittest.main()
