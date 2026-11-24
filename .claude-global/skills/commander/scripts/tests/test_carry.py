import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from carry import Carry, extract, prune, render  # noqa: E402

SCRIPT = Path(__file__).resolve().parent.parent / "carry.py"
RDP = "- 2026-11-24 RDP 作業 [ref:title:AI参考情報 指示2項目の本番登録・配置]"
MERGED = "- 2026-11-24 マージ済み [ref:epc#1300]"
SAMPLE = f"""# 司令塔 2026-11-24（火）
## 祝日と期限
- ここは写さない
## 引き継ぐ欄
### 期限
- 2026-11-25 修正版の期限
### 済んだこと
{RDP}
{MERGED}
### 作業中の tmux セッション
- pilot-p11: P.11
- hankyu-102: PR #102
### メモ
- 1は後回し
## 一覧
- ここも写さない
"""


class ExtractTest(unittest.TestCase):
    def test_extract(self):
        c = extract(SAMPLE)
        self.assertEqual(c.deadlines, ["- 2026-11-25 修正版の期限"])
        self.assertEqual(c.done, [RDP, MERGED])
        self.assertEqual(c.tmux, ["- pilot-p11: P.11", "- hankyu-102: PR #102"])
        self.assertEqual(c.memo, ["- 1は後回し"])

    def test_no_section(self):
        self.assertEqual(extract("# 古い形式\n本文だけ\n"), Carry([], [], [], []))

    def test_stray_lines_go_to_memo(self):
        c = extract("## 引き継ぐ欄\n- 見出しの外の行\n### 知らない見出し\n- b\n### メモ\n- a\n")
        self.assertEqual(c.memo, ["- 見出しの外の行", "- b", "- a"])

    def test_render_roundtrip(self):
        c = extract(SAMPLE)
        self.assertEqual(extract(render(c)), c)
        self.assertTrue(render(Carry([], [], [], [])).startswith("## 引き継ぐ欄\n### 期限\n"))


class PruneTest(unittest.TestCase):
    def test_prune_tmux_and_done(self):
        c, info = prune(extract(SAMPLE), ["pilot-p11"], {"title:AI参考情報 指示2項目の本番登録・配置"})
        self.assertEqual(c.tmux, ["- pilot-p11: P.11"])
        self.assertEqual(info["removed_tmux"], ["- hankyu-102: PR #102"])
        self.assertEqual(c.done, [RDP])
        self.assertEqual(info["removed_done"], [MERGED])
        self.assertEqual(info["done_still_in_todo"], [RDP])

    def test_tmux_unknown_keeps_all(self):
        c, info = prune(extract(SAMPLE), None, set())
        self.assertEqual(len(c.tmux), 2)
        self.assertEqual(info["removed_tmux"], [])

    def test_todo_unknown_keeps_done(self):
        c, info = prune(extract(SAMPLE), [], None)
        self.assertEqual(c.done, [RDP, MERGED])
        self.assertEqual(info["removed_done"], [])

    def test_done_without_ref_kept(self):
        c, info = prune(extract("## 引き継ぐ欄\n### 済んだこと\n- 2026-11-24 ref なし\n"), [], set())
        self.assertEqual(c.done, ["- 2026-11-24 ref なし"])
        self.assertEqual(info["unparsed_done"], ["- 2026-11-24 ref なし"])


class CliTest(unittest.TestCase):
    def run_cli(self, *args):
        out = subprocess.run([sys.executable, "-I", str(SCRIPT), *args], capture_output=True, text=True, check=True)
        return json.loads(out.stdout)

    def test_missing_prev(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = self.run_cli("--prev", str(Path(tmp) / "none.md"), "--todo", str(Path(tmp) / "none.md"))
            self.assertEqual(res["section"], render(Carry([], [], [], [])))

    def test_open_refs_from_todo(self):
        with tempfile.TemporaryDirectory() as tmp:
            prev = Path(tmp) / "prev.md"
            prev.write_text(SAMPLE, encoding="utf-8")
            todo = Path(tmp) / "todo.md"
            todo.write_text(
                "# TODO\n\n## 確認待ち\n\n## やる\n- [ ] AI参考情報 指示2項目の本番登録・配置\n\n## 待ち\n\n## 完了\n"
                "- [x] 注釈のレビュー [epc#1300](https://example.com) (done: 2026-11-24)\n",
                encoding="utf-8",
            )
            res = self.run_cli("--prev", str(prev), "--todo", str(todo))
            self.assertEqual(res["removed_done"], [MERGED])
            self.assertEqual(res["done_still_in_todo"], [RDP])


if __name__ == "__main__":
    unittest.main()
