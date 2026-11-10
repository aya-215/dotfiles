import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import todo_md
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
    return {l for l in text.splitlines() if l.startswith("- [")}


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
        once = migrate(OLD)
        self.assertEqual(migrate(once), once)

    def test_unexpected_line_raises(self):
        with self.assertRaises(todo_md.ParseError):
            migrate("# TODO\n- [ ] a\nfree text\n\n## 待ち\n\n## 完了\n")


if __name__ == "__main__":
    unittest.main()
