import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from collect import collect  # noqa: E402

TODO = """# TODO

## 確認待ち

## やる
- [ ] メンサポリンクの一致行を全件返す（BE） [epc#1296](https://github.com/ebase-dev/ebase-portal-chat/issues/1296) — next: 実装（11/25）
- [ ] インターン資料修正

## 待ち
- [ ] 車名の候補バブル [epc#1302](https://github.com/ebase-dev/ebase-portal-chat/issues/1302) — next: 辻本さん待ち

## 完了
- [x] 後片付け — next: 済 (done: 2026-11-20)
"""

MEMO = """---
summary: "メンサポリンク。PR #1316 のレビュー待ち"
created: 2026-11-20
status: blocked
tags: [handoff, ebase-portal-chat]
---

## 関連
- PR: https://github.com/ebase-dev/ebase-portal-chat/pull/1316
- issue: https://github.com/ebase-dev/ebase-portal-chat/issues/1296

## 元のセッション
- 作業場所: /x/epc-feat-1296（ブランチ feat/1296）
"""


class CollectTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.todo = self.tmp / "todo.md"
        self.todo.write_text(TODO, encoding="utf-8")
        self.cdir = self.tmp / "commander"
        self.cdir.mkdir()
        self.memo = self.tmp / "handoff-20261120-1742-mensapo.md"
        self.memo.write_text(MEMO, encoding="utf-8")
        self.hit = {"path": str(self.memo), "summary": "メンサポリンク", "created": "2026-11-20", "status": "blocked"}

    def tearDown(self):
        self._tmp.cleanup()

    def test_matches_todo_and_handoff_by_ref(self):
        out = collect(self.todo, [self.hit], self.cdir, date(2026, 11, 24), ["pilot-p11"])
        row = next(r for r in out["todo"] if r["ref"] == "epc#1296")
        self.assertEqual(row["handoffs"], [str(self.memo)])
        h = out["handoffs"][0]
        self.assertEqual(h["todo_refs"], ["epc#1296"])
        self.assertEqual(h["refs"], ["epc#1296", "epc#1316"])
        self.assertEqual(h["location"], "/x/epc-feat-1296")
        self.assertEqual(h["since"], "2026-11-20T17:42:00+09:00")
        self.assertEqual(out["tmux_sessions"], ["pilot-p11"])

    def test_todo_rows(self):
        out = collect(self.todo, [], self.cdir, date(2026, 11, 24), [])
        self.assertEqual([r["section"] for r in out["todo"]], ["やる", "やる", "待ち"])
        bare = next(r for r in out["todo"] if r["title"] == "インターン資料修正")
        self.assertEqual(bare["ref"], "title:インターン資料修正")
        self.assertIsNone(bare["location"])
        self.assertTrue(out["todo"][0]["location"].endswith("ebase-dev/ebase-portal-chat"))

    def test_completed_items_excluded(self):
        out = collect(self.todo, [], self.cdir, date(2026, 11, 24), [])
        self.assertNotIn("後片付け", [r["title"] for r in out["todo"]])

    def test_range_and_holidays(self):
        out = collect(self.todo, [], self.cdir, date(2026, 11, 20), None)
        self.assertEqual(out["range_end"], "2026-12-04")
        self.assertIn({"date": "2026-11-23", "name": "勤労感謝の日"}, out["holidays"])
        self.assertIsNone(out["tmux_sessions"])

    def test_previous_file(self):
        for name in ["2026-11-20.md", "2026-11-21.md", "2026-11-24.md", "memo.md"]:
            (self.cdir / name).write_text("x", encoding="utf-8")
        out = collect(self.todo, [], self.cdir, date(2026, 11, 24), [])
        self.assertTrue(out["files"]["today_exists"])
        self.assertEqual(out["files"]["today"], str(self.cdir / "2026-11-24.md"))
        self.assertEqual(out["files"]["previous"], str(self.cdir / "2026-11-21.md"))

    def test_no_previous_file(self):
        out = collect(self.todo, [], self.cdir, date(2026, 11, 24), [])
        self.assertFalse(out["files"]["today_exists"])
        self.assertIsNone(out["files"]["previous"])

    def test_missing_todo_still_returns_handoffs(self):
        out = collect(self.tmp / "none.md", [self.hit], self.cdir, date(2026, 11, 24), [])
        self.assertEqual(out["todo"], [])
        self.assertEqual(len(out["handoffs"]), 1)
        self.assertTrue(any("todo" in w for w in out["warnings"]))

    def test_memo_without_refs_kept(self):
        bare = self.tmp / "note.md"
        bare.write_text("---\nsummary: \"x\"\ncreated: 2026-11-18\nstatus: blocked\n---\n本文だけ\n", encoding="utf-8")
        out = collect(self.todo, [{"path": str(bare), "summary": "x", "created": "2026-11-18", "status": "blocked"}],
                      self.cdir, date(2026, 11, 24), [])
        h = out["handoffs"][0]
        self.assertIsNone(h["location"])
        self.assertEqual(h["refs"], [])
        self.assertEqual(h["since"], "2026-11-18T00:00:00+09:00")


if __name__ == "__main__":
    unittest.main()
