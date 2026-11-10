import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import todo_md
import migrate as migrate_mod
from migrate import migrate

OLD = """# TODO
- [ ] インターン資料修正
- [ ] SQLのdbt保存

- [ ] [officeのteams資料修正](https://example.com/a?x=1)
- [ ] rocketchatMCPの更新


## 待ち
- [ ] 坂西さんの対応


## 完了
- [x] 玉木君レビュー
- [x] issue 751(松本さんレビュー) 
"""


def task_lines(text):
    return {re.sub(r" \(done: \d{4}-\d{2}-\d{2}\)\Z", "", l) for l in text.split("\n") if l.startswith("- [")}


class MigrateTest(unittest.TestCase):
    def test_migrate_current_shape(self):
        out = migrate(OLD)
        self.assertEqual(task_lines(out), task_lines(OLD))
        doc = todo_md.parse(out)
        self.assertEqual(todo_md.render(doc), out)
        self.assertEqual(doc.preamble, ["# TODO"])
        self.assertEqual(doc.confirm, [])
        self.assertEqual(len(doc.sections["やる"]), 4)
        self.assertEqual(len(doc.sections["待ち"]), 1)
        self.assertEqual(len(doc.sections["完了"]), 2)

    def test_migrate_idempotent(self):
        once = migrate(OLD, today="2026-11-10")
        self.assertEqual(migrate(once, today="2026-12-01"), once)

    def test_done_lines_without_date_get_migration_date(self):
        doc = todo_md.parse(migrate(OLD, today="2026-11-10"))
        self.assertEqual([(it.title, it.done_date) for it in doc.sections["完了"]],
                         [("玉木君レビュー", "2026-11-10"), ("issue 751(松本さんレビュー) ", "2026-11-10")])
        self.assertEqual([it.done_date for it in doc.sections["やる"]], [None] * 4)

    def test_existing_done_date_kept(self):
        old = OLD.replace("- [x] 玉木君レビュー", "- [x] 玉木君レビュー (done: 2026-10-01)")
        doc = todo_md.parse(migrate(old, today="2026-11-10"))
        self.assertEqual([it.done_date for it in doc.sections["完了"]], ["2026-10-01", "2026-11-10"])

    def test_new_format_undated_done_is_stamped(self):
        new = "## 確認待ち\n\n## やる\n\n## 待ち\n\n## 完了\n- [x] 手で足した\n"
        self.assertIn("- [x] 手で足した (done: 2026-11-10)", migrate(new, today="2026-11-10"))

    def test_cli_date_option(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "todo.md"
            p.write_text(OLD, encoding="utf-8")
            self.assertEqual(migrate_mod.main(["migrate.py", str(p), "--date", "2026-11-10"]), 0)
            self.assertIn("- [x] 玉木君レビュー (done: 2026-11-10)", p.read_text(encoding="utf-8"))
            self.assertEqual(migrate_mod.main(["migrate.py", str(p), "--date", "bad"]), 2)

    def test_unexpected_line_raises(self):
        with self.assertRaises(todo_md.ParseError):
            migrate("# TODO\n- [ ] a\nfree text\n\n## 待ち\n\n## 完了\n")


if __name__ == "__main__":
    unittest.main()
