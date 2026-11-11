import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from find_handoff import matches, search  # noqa: E402

SCRIPT = Path(__file__).resolve().parent / "find_handoff.py"


def note(root: Path, rel: str, summary: str, created: str, status: str, tags: str, body: str) -> Path:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f'---\nsummary: "{summary}"\ncreated: {created}\nstatus: {status}\ntags: [{tags}]\n---\n\n{body}\n',
        encoding="utf-8",
    )
    return path


class MatchesTest(unittest.TestCase):
    def test_pr_number_forms(self):
        text = "PR: https://github.com/aya/ebase-portal-chat/pull/1210 を待っている"
        for term in ["1210", "#1210", "PR1210", "pr1210"]:
            self.assertTrue(matches(text, [term]), term)

    def test_issue_number_with_leading_zeros(self):
        self.assertTrue(matches("課題 No00007400 の確認待ち", ["7400"]))
        self.assertTrue(matches("課題 No00007400 の確認待ち", ["No7400"]))

    def test_number_is_not_a_partial_match(self):
        self.assertFalse(matches("https://github.com/aya/x/pull/1210", ["12"]))
        self.assertFalse(matches("#12 の件", ["1210"]))

    def test_words_must_all_appear_ignoring_case(self):
        self.assertTrue(matches("阪急 アイコン 修正 Icon", ["阪急", "アイコン"]))
        self.assertTrue(matches("阪急 アイコン 修正 Icon", ["icon"]))
        self.assertFalse(matches("阪急 アイコン 修正", ["阪急", "ロゴ"]))


class SearchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_open_handoff_first(self):
        open_ = note(self.root, "work-in-progress/handoff-a.md", "PR1210 待ち", "2026-11-10", "blocked", "handoff, epc", "pull/1210")
        note(self.root, "work-in-progress/handoff-b.md", "PR1210 済み", "2026-11-01", "resolved", "handoff, epc", "pull/1210")
        result = search(self.root, ["1210"])
        self.assertEqual(result["stage"], "handoff-open")
        self.assertEqual([h["path"] for h in result["hits"]], [str(open_)])

    def test_falls_back_to_resolved_handoffs(self):
        done = note(self.root, "work-in-progress/handoff-b.md", "PR1210 済み", "2026-11-01", "resolved", "handoff, epc", "pull/1210")
        result = search(self.root, ["1210"])
        self.assertEqual(result["stage"], "handoff-all")
        self.assertEqual(result["hits"][0]["path"], str(done))
        self.assertEqual(result["hits"][0]["status"], "resolved")

    def test_falls_back_to_work_in_progress(self):
        wip = note(self.root, "work-in-progress/issue-978.md", "issue 978", "2026-10-27", "in-progress", "epc", "#978 の作業")
        self.assertEqual(search(self.root, ["978"]), {"stage": "work-in-progress", "hits": [
            {"path": str(wip), "summary": "issue 978", "created": "2026-10-27", "status": "in-progress"}]})

    def test_falls_back_to_all_memories(self):
        other = note(self.root, "ebase-web/hankyu.md", "阪急 リリース", "2026-11-09", "resolved", "hankyu", "No00007400")
        result = search(self.root, ["7400"])
        self.assertEqual(result["stage"], "all")
        self.assertEqual(result["hits"][0]["path"], str(other))

    def test_nothing_found(self):
        note(self.root, "work-in-progress/handoff-a.md", "PR1210 待ち", "2026-11-10", "blocked", "handoff", "pull/1210")
        self.assertEqual(search(self.root, ["9999"]), {"stage": "none", "hits": []})

    def test_no_terms_lists_open_handoffs_newest_first(self):
        old = note(self.root, "work-in-progress/handoff-old.md", "古い", "2026-11-01", "blocked", "handoff", "x")
        new = note(self.root, "work-in-progress/handoff-new.md", "新しい", "2026-11-10", "blocked", "handoff", "y")
        note(self.root, "work-in-progress/handoff-done.md", "済み", "2026-11-11", "resolved", "handoff", "z")
        note(self.root, "work-in-progress/other.md", "別件", "2026-11-11", "blocked", "herdr", "w")
        result = search(self.root, [])
        self.assertEqual(result["stage"], "handoff-open")
        self.assertEqual([h["path"] for h in result["hits"]], [str(new), str(old)])

    def test_cli_prints_json(self):
        open_ = note(self.root, "work-in-progress/handoff-a.md", "PR1210 待ち", "2026-11-10", "blocked", "handoff", "pull/1210")
        out = subprocess.run([sys.executable, "-I", str(SCRIPT), "--root", str(self.root), "#1210"],
                             capture_output=True, text=True, check=True).stdout
        self.assertEqual(json.loads(out)["hits"][0]["path"], str(open_))


if __name__ == "__main__":
    unittest.main()
