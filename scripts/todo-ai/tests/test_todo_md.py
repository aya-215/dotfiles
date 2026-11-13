import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

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

    def test_unicode_line_separators_in_title_roundtrip(self):
        for ch in ("\u2028", "\u2029", "\x0c", "\x0b", "\x1c", "\x85"):
            t = mk().replace("## やる\n", f"## やる\n- [ ] a{ch}b [epc#1](https://g/1)\n")
            d = parse(t)
            self.assertEqual([it.title for it in d.sections["やる"]], [f"a{ch}b"], repr(ch))
            self.assertEqual(render(d), t, repr(ch))

    def test_crlf_lines_still_parse(self):
        d = parse(SAMPLE.replace("\n", "\r\n"))
        self.assertEqual(render(d), SAMPLE)

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
                  "rc:abc123", "rc:abc123#2", "mail:CAF+x.y", "wt:feat-foo", "ebpm:No00007400"]:
            self.assertTrue(is_key(k), k)
        for k in ["foo#1", "epc#", "gb:#1", "rc:", "officeのteams資料修正", "epc#1a", "", "ebpm:7400", "ebpm:"]:
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



G = [{"name": "パイロット", "keys": ["gb:WEB#"], "words": ["パイロット"]},
     {"name": "共通", "keys": ["epc#1176"], "words": []},
     {"name": "シフトオン", "keys": ["epc#"], "words": ["車両"]}]


class GroupTest(unittest.TestCase):
    def test_group_of(self):
        g = todo_md.group_of
        self.assertEqual(g(Item("P.11 検索", key="rc:abc", url="u"), G), "その他")
        self.assertEqual(g(Item("パイロット P.11", key="rc:abc", url="u"), G), "パイロット")
        self.assertEqual(g(Item("バナー", key="gb:WEB#3", url="u"), G), "パイロット")
        self.assertEqual(g(Item("商品カード", key="epc#1176", url="u"), G), "共通")
        self.assertEqual(g(Item("x", key="epc#11760", url="u"), G), "シフトオン")
        self.assertEqual(g(Item("車両 [資料](https://x/y)"), G), "シフトオン")
        self.assertEqual(g(Item("a", next="車両を見る"), G), "その他")

    def _doc(self):
        return parse("""## 確認待ち

## やる
- [ ] その他1
- [ ] シフト1 [epc#1](https://g/1)
- [ ] パイロット1
- [ ] シフト2 [epc#2](https://g/2)
- [ ] その他2

## 待ち
- [ ] 待ちその他
- [ ] 待ち車両

## 完了
- [x] 済その他 (done: 2026-11-01)
- [x] 済パイロット (done: 2026-11-01)
""")

    def test_regroup(self):
        doc = self._doc()
        out = todo_md.regroup(doc, G)
        self.assertEqual([i.title for i in out.sections["やる"]], ["パイロット1", "シフト1", "シフト2", "その他1", "その他2"])
        self.assertEqual([i.title for i in out.sections["待ち"]], ["待ち車両", "待ちその他"])
        self.assertEqual([i.title for i in out.sections["完了"]], ["済その他", "済パイロット"])
        self.assertEqual([i.title for i in doc.sections["やる"]], ["その他1", "シフト1", "パイロット1", "シフト2", "その他2"])

    def test_regroup_duplicate_name_uses_first_position(self):
        groups = [{"name": "A", "keys": ["epc#"], "words": []},
                  {"name": "B", "keys": [], "words": ["パイロット"]},
                  {"name": "A", "keys": [], "words": ["阪急"]}]
        doc = parse("## 確認待ち\n\n## やる\n- [ ] パイロット1\n- [ ] 阪急1\n- [ ] s [epc#1](https://g/1)\n\n## 待ち\n\n## 完了\n")
        self.assertEqual([i.title for i in todo_md.regroup(doc, groups).sections["やる"]], ["阪急1", "s", "パイロット1"])

    def test_regroup_without_groups_keeps_order(self):
        doc = self._doc()
        self.assertEqual(render(todo_md.regroup(doc, [])), render(doc))

    def test_load_groups(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "todo-groups.json"
            self.assertEqual(todo_md.load_groups(p), [])
            p.write_text(json.dumps({"groups": G}, ensure_ascii=False), encoding="utf-8")
            self.assertEqual(todo_md.load_groups(p), G)
            for bad in ["{", json.dumps({"groups": [{"name": "a"}]}), json.dumps({"groups": "x"}),
                        json.dumps({"groups": [{"name": "a", "keys": [1176], "words": []}]}),
                        json.dumps({"groups": [{"name": "a", "keys": [], "words": [None]}]})]:
                p.write_text(bad, encoding="utf-8")
                err = io.StringIO()
                with contextlib.redirect_stderr(err):
                    self.assertEqual(todo_md.load_groups(p), [])
                self.assertIn("todo-groups.json を読めない", err.getvalue())

if __name__ == "__main__":
    unittest.main()
