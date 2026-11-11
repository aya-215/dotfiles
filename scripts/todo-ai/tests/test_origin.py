import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from origin import origin_of, title_written_by


def git(repo, *args):
    subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args],
        check=True, capture_output=True,
    )


class OriginTest(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.repo = Path(self._td.name)
        git(self.repo, "init", "-q")
        self.f = self.repo / "todo.md"

    def tearDown(self):
        self._td.cleanup()

    def commit(self, text, msg):
        self.f.write_text(text)
        git(self.repo, "add", "todo.md")
        git(self.repo, "commit", "-q", "-m", msg)

    def test_origin_ai(self):
        self.commit("- [ ] human one\n", "todo: 2026-01-01 10:00")
        self.commit("- [ ] human one\n- [ ] ai one\n", "todo(ai): add")
        self.commit("- [ ] ai one\n\n- [ ] human one\n", "todo: 2026-01-02 10:00")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "ai")

    def test_origin_human(self):
        self.commit("- [ ] human one\n", "todo: 2026-01-01 10:00")
        self.commit("- [ ] human one\n- [ ] ai one\n", "todo(ai): add")
        self.assertEqual(origin_of(self.repo, "todo.md", "human one"), "human")

    def test_origin_duplicate_title_is_human(self):
        self.commit("- [ ] same\n", "todo(ai): add")
        self.commit("- [ ] same\n- [ ] same\n", "todo: 2026-01-02 10:00")
        self.assertEqual(origin_of(self.repo, "todo.md", "same"), "human")

    def test_uncommitted_duplicate_is_human(self):
        self.commit("- [ ] ai one\n", "todo(ai): add")
        self.f.write_text("- [ ] ai one\n- [ ] ai one\n")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "human")

    def test_removed_and_retyped_is_human(self):
        self.commit("- [ ] x\n- [ ] ai one\n", "todo(ai): add")
        self.commit("- [ ] x\n", "todo: 2026-01-02 10:00")
        self.commit("- [ ] x\n- [ ] ai one\n", "todo: 2026-01-03 10:00")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "human")

    def test_invalid_utf8_worktree_falls_back_to_head(self):
        self.commit("- [ ] ai one\n", "todo(ai): add")
        self.f.write_bytes("- [ ] ai one\n- [ ] 日本語\n".encode("shift_jis"))
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "ai")

    def test_invalid_utf8_in_head_too_is_human(self):
        self.f.write_bytes("- [ ] ai one 日本語\n".encode("shift_jis"))
        git(self.repo, "add", "todo.md")
        git(self.repo, "commit", "-q", "-m", "todo(ai): add")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "human")

    def test_unknown_title_is_human(self):
        self.commit("- [ ] a\n", "todo(ai): add")
        self.assertEqual(origin_of(self.repo, "todo.md", "zzz"), "human")


    def test_asked_in_confirm_then_added_is_ai(self):
        self.commit("## 確認待ち\n1. 『見積もり送付』を足す？ [is_task title:見積もり送付]\n   回答:\n\n## やる\n", "todo(ai): 確認待ち1")
        self.commit("## 確認待ち\n1. 『見積もり送付』を足す？ [is_task title:見積もり送付]\n   回答: A\n\n## やる\n",
                    "todo: 2026-01-02 10:00")
        self.commit("## 確認待ち\n\n## やる\n- [ ] 見積もり送付\n", "todo(ai): 追加1 確認待ち0")
        self.assertEqual(origin_of(self.repo, "todo.md", "見積もり送付"), "ai")

    def test_ai_and_sync_hits_only_are_ai(self):
        self.commit("- [ ] ai one\n", "todo(ai): add")
        self.commit("", "todo(sync): archive")
        self.commit("- [ ] ai one\n", "todo(ai): add again")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "ai")

    def test_user_commit_hit_is_human(self):
        self.commit("- [ ] ai one\n", "todo(ai): add")
        self.commit("- [ ] ai one\n- [ ] x\n", "todo(user): 足す")
        self.commit("- [ ] x\n", "todo(user): 消す")
        self.commit("- [ ] x\n- [ ] ai one\n", "todo(ai): add")
        self.assertEqual(origin_of(self.repo, "todo.md", "ai one"), "human")

    def doc(self, todo="", wait=""):
        return f"## 確認待ち\n\n## やる\n{todo}\n## 待ち\n{wait}\n## 完了\n"

    def test_title_written_by_follows_who_introduced_the_exact_title(self):
        long = "- [ ] PR #1 車両候補の選択肢バブル（彌永さん）の再レビュー [epc#1](https://g/1)\n"
        self.commit(self.doc(long), "todo(ai): 追加1")
        self.assertEqual(title_written_by(self.repo, "todo.md", "PR #1 車両候補の選択肢バブル（彌永さん）の再レビュー"), "ai")
        self.commit(self.doc(wait=long), "todo: 2026-01-02 10:00")
        self.assertEqual(title_written_by(self.repo, "todo.md", "PR #1 車両候補の選択肢バブル（彌永さん）の再レビュー"), "ai")
        self.commit(self.doc("- [ ] PR #1 車両候補の選択肢バブル [epc#1](https://g/1)\n"), "todo: 2026-01-03 10:00")
        self.assertEqual(title_written_by(self.repo, "todo.md", "PR #1 車両候補の選択肢バブル"), "human")

    def test_title_written_by_ignores_ai_attach_to_human_line(self):
        self.commit(self.doc("- [ ] 資料の件\n"), "todo: 2026-01-01 10:00")
        self.commit(self.doc("- [ ] 資料の件 [epc#2](https://g/2)\n"), "todo(ai): 紐付け1")
        self.assertEqual(title_written_by(self.repo, "todo.md", "資料の件"), "human")

    def test_title_written_by_unknown_or_unparsable_is_human(self):
        self.commit(self.doc("- [ ] a\n"), "todo(ai): 追加1")
        self.assertEqual(title_written_by(self.repo, "todo.md", "zzz"), "human")
        self.commit("- [ ] b\n", "todo(ai): 壊れた")
        self.assertEqual(title_written_by(self.repo, "todo.md", "b"), "human")

if __name__ == "__main__":
    unittest.main()
