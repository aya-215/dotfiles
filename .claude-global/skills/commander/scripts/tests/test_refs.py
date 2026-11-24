import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from refs import location_for, refs_in_text, workdir_in_memo  # noqa: E402


class RefsInTextTest(unittest.TestCase):
    def test_github_pull_and_issue(self):
        t = "PR: https://github.com/ebase-dev/ebase-portal-chat/pull/1316 / issue は https://github.com/ebase-dev/ebase-portal-chat/issues/1296"
        self.assertEqual(refs_in_text(t), {"epc#1316", "epc#1296"})

    def test_unknown_github_repo_ignored(self):
        self.assertEqual(refs_in_text("https://github.com/other/x/pull/1"), set())

    def test_gitbucket(self):
        t = "http://192.168.208.80:8080/gitbucket/hankyu_kitchenyell/ebase-web/pull/102"
        self.assertEqual(refs_in_text(t), {"gb:ebase-web#102"})

    def test_ebpm_number(self):
        self.assertEqual(refs_in_text("課題No00007456 と No00000005"), {"ebpm:No00007456", "ebpm:No00000005"})

    def test_todo_key_as_is(self):
        self.assertEqual(refs_in_text("epc#1312・eae#141・emm#325"), {"epc#1312", "eae#141", "emm#325"})


class WorkdirTest(unittest.TestCase):
    def test_from_memo(self):
        self.assertEqual(
            workdir_in_memo("- 作業場所: /mnt/d/tomcat/webapps/hankyu（ブランチ feat/x）"),
            "/mnt/d/tomcat/webapps/hankyu",
        )

    def test_missing(self):
        self.assertIsNone(workdir_in_memo("本文だけ"))


class LocationTest(unittest.TestCase):
    def test_github_abbr(self):
        self.assertEqual(location_for("epc#1"), str(Path.home() / "src/github.com/ebase-dev/ebase-portal-chat"))

    def test_gitbucket_glob(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "eBASE/ebase-claude-marketplace").mkdir(parents=True)
            self.assertEqual(
                location_for("gb:ebase-claude-marketplace#99", [Path(tmp)]),
                str(Path(tmp) / "eBASE/ebase-claude-marketplace"),
            )

    def test_no_location(self):
        self.assertIsNone(location_for("rc:abc"))
        self.assertIsNone(location_for("title:インターン資料修正"))
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(location_for("gb:nowhere#1", [Path(tmp)]))


if __name__ == "__main__":
    unittest.main()
