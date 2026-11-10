import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import todo_md
from todo_md import Doc, Item, ParseError, is_key, parse, render

SAMPLE = """# TODO

## 確認待ち
1. [epc#1202] 方針を決める
   回答: A、ただし来週

## やる
- [ ] PR#1163 対応 [epc#1163](https://g/1163) — next: N1 残
- [ ] [officeのteams資料修正](https://somu/x)
- [ ] メモだけ

## 待ち
- [ ] 返信待ち [rc:abc#1](https://rc/x) — next: 待つ

## 完了
- [x] a [gb:repo#3](https://gb/3) (done: 2026-11-10)
"""


def mk(**kw):
    return "# TODO\n\n## 確認待ち\n\n## やる\n\n## 待ち\n\n## 完了\n" if not kw else kw


class TestTodoMd(unittest.TestCase):
    def test_roundtrip(self):
        self.assertEqual(render(parse(SAMPLE)), SAMPLE)

    def test_item_fields(self):
        d = parse(SAMPLE)
        it = d.sections["やる"][0]
        self.assertEqual(
            (it.title, it.key, it.url, it.next, it.done),
            ("PR#1163 対応", "epc#1163", "https://g/1163", "N1 残", False),
        )
        self.assertEqual(it.ref, "epc#1163")

    def test_title_only_link(self):
        it = parse(SAMPLE).sections["やる"][1]
        self.assertEqual(it.title, "[officeのteams資料修正](https://somu/x)")
        self.assertIsNone(it.key)
        self.assertEqual(it.ref, "title:" + it.title)

    def test_title_with_next_marker(self):
        t = mk().replace("## やる\n", "## やる\n\n- [ ] a — next: b — next: c\n")
        it = parse(t).sections["やる"][0]
        self.assertEqual((it.title, it.next), ("a — next: b", "c"))

    def test_done_date(self):
        it = parse(SAMPLE).sections["完了"][0]
        self.assertTrue(it.done)
        self.assertEqual(it.done_date, "2026-11-10")
        t = mk().replace("## 完了\n", "## 完了\n\n- [x] a (done: 2026-11-10)\n")
        it = parse(t).sections["完了"][0]
        self.assertEqual((it.title, it.done, it.done_date), ("a", True, "2026-11-10"))

    def test_missing_heading_raises(self):
        with self.assertRaises(ParseError):
            parse(mk().replace("## 待ち\n\n", ""))

    def test_unknown_heading_raises(self):
        with self.assertRaises(ParseError):
            parse(mk() + "\n## その他\n")

    def test_free_text_in_section_raises(self):
        with self.assertRaises(ParseError):
            parse(mk().replace("## やる\n", "## やる\n\nメモ\n"))

    def test_confirm_kept_verbatim(self):
        d = parse(SAMPLE)
        self.assertEqual(
            d.confirm,
            ["", "1. [epc#1202] 方針を決める", "   回答: A、ただし来週"][1:],
        )

    def test_is_key(self):
        for k in ["epc#1", "emm#22", "eae#3", "eas#4", "gb:repo-x#5",
                  "rc:abc123", "rc:abc123#2", "mail:CAF+x.y", "wt:feat-foo"]:
            self.assertTrue(is_key(k), k)
        for k in ["foo#1", "epc#", "gb:#1", "rc:", "officeのteams資料修正", "epc#1a", ""]:
            self.assertFalse(is_key(k), k)

    def test_render_rejects_key_without_url(self):
        d = parse(SAMPLE)
        d.sections["やる"].append(Item("x", key="wt:foo"))
        with self.assertRaises(ValueError):
            render(d)

    def test_render_rejects_newline(self):
        for kw in ({"title": "a\nb"}, {"title": "a", "next": "b\nc"}):
            d = parse(SAMPLE)
            d.sections["やる"].append(Item(**kw))
            with self.assertRaises(ValueError):
                render(d)

    def test_edit_then_render(self):
        d = parse(SAMPLE)
        d.sections["やる"][0].next = "新"
        self.assertIn("— next: 新\n", render(d))


if __name__ == "__main__":
    unittest.main()
