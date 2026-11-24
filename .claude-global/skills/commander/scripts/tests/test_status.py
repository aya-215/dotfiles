import os
import sys
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from status import build, changed_handoffs, rc_rooms, closed_sessions, github_facts, probe, read_last_check, wait_ips  # noqa: E402

TODAY = date(2026, 11, 24)
MIDNIGHT = datetime.fromisoformat("2026-11-24T00:00:00+09:00")


class ReadLastCheckTest(unittest.TestCase):
    def test_reads_line(self):
        w = []
        got = read_last_check("# 司令塔\n最終確認: 2026-11-24T15:40:00+09:00\n", TODAY, w)
        self.assertEqual(got, datetime.fromisoformat("2026-11-24T15:40:00+09:00"))
        self.assertEqual(w, [])

    def test_no_file(self):
        w = []
        self.assertEqual(read_last_check(None, TODAY, w), MIDNIGHT)
        self.assertEqual(w, [])

    def test_broken_line(self):
        w = []
        self.assertEqual(read_last_check("最終確認: きのう\n", TODAY, w), MIDNIGHT)
        self.assertEqual(len(w), 1)


class ChangedHandoffsTest(unittest.TestCase):
    def test_only_newer(self):
        with tempfile.TemporaryDirectory() as d:
            old = Path(d) / "handoff-20261120-1000-old.md"
            new = Path(d) / "handoff-20261120-1743-new.md"
            old.write_text("---\nsummary: \"古い\"\nstatus: blocked\n---\n## 待っているもの\n", encoding="utf-8")
            new.write_text("---\nsummary: \"本番配置\"\nstatus: resolved\n---\n## 今の状態\n\n"
                           "## 2026-11-24 本番 eBASE 側の作業（完了）\n- 済み\n", encoding="utf-8")
            (Path(d) / "other.md").write_text("status: resolved\n", encoding="utf-8")
            t_old = datetime.fromisoformat("2026-11-24T09:00:00+09:00").timestamp()
            t_new = datetime.fromisoformat("2026-11-24T15:10:00+09:00").timestamp()
            os.utime(old, (t_old, t_old))
            os.utime(new, (t_new, t_new))
            got = changed_handoffs(Path(d), datetime.fromisoformat("2026-11-24T12:00:00+09:00"))
        self.assertEqual([(h["status"], h["summary"]) for h in got], [("resolved", "本番配置")])
        self.assertEqual(got[0]["last_heading"], "2026-11-24 本番 eBASE 側の作業（完了）")

    def test_last_heading_skips_boilerplate(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "handoff-20261124-1042-x.md"
            p.write_text("---\nstatus: blocked\n---\n## 待っているもの\n## 今の状態\n## 次にやること\n## 関連\n## 元のセッション\n- id\n", encoding="utf-8")
            got = changed_handoffs(Path(d), MIDNIGHT)
        self.assertEqual(got[0]["last_heading"], "")


class WaitIpsTest(unittest.TestCase):
    def test_only_wait_section(self):
        t = "## 待っているもの\n- 192.168.160.92 の起動。GitBucket 192.168.208.80 には届く\n- 192.168.160.92\n## 今の状態\n- 10.0.0.1\n"
        self.assertEqual(wait_ips(t), ["192.168.160.92", "192.168.208.80"])

    def test_no_section(self):
        self.assertEqual(wait_ips("## 今の状態\n- 10.0.0.1\n"), [])


class ProbeTest(unittest.TestCase):
    def test_open_ports(self):
        tried = []

        def connect(ip, port, timeout):
            tried.append((port, timeout))
            return port in (80, 3389)

        self.assertEqual(probe("1.2.3.4", connect), [80, 3389])
        self.assertEqual(tried, [(22, 2), (80, 2), (445, 2), (3389, 2)])


class ClosedSessionsTest(unittest.TestCase):
    T = "## 引き継ぐ欄\n### 作業中の tmux セッション\n- epc-1316: マージ\n- epc-1308: 確認\n### メモ\n- x\n## 一覧\n"

    def test_closed(self):
        self.assertEqual(closed_sessions(self.T, ["epc-1308"]), ["- epc-1316: マージ"])

    def test_unknown_live(self):
        self.assertEqual(closed_sessions(self.T, None), [])
        self.assertEqual(closed_sessions(None, ["a"]), [])


LAST = datetime.fromisoformat("2026-11-24T12:00:00+09:00")
ME = {"eBASE-Mori"}
NO_EXTRA = {"last_commit": None, "checks": None, "closed_at": None}


class GithubFactsTest(unittest.TestCase):
    def test_pr(self):
        pr = {"state": "open", "author": "nakatani0324", "reviewers": [], "events": [
            {"user": "ebase-iyanaga", "ts": "2026-11-24T01:00:00Z", "kind": "review", "state": "COMMENTED"},
            {"user": "ebase-iyanaga", "ts": "2026-11-24T05:32:24Z", "kind": "review", "state": "APPROVED"},
            {"user": "eBASE-Mori", "ts": "2026-11-24T05:40:00Z", "kind": "comment", "state": None}]}
        extra = {"last_commit": "2026-11-24T05:26:00Z", "checks": {"pass": 5, "fail": 0, "pending": 0}, "closed_at": None}
        got = github_facts("epc#1313", lambda r, n: pr, lambda r, n: extra, ME, LAST, None)
        self.assertEqual(got["state"], "open")
        self.assertEqual(got["reviews"], {"ebase-iyanaga": "APPROVED"})
        self.assertEqual(got["last_commit"], "2026-11-24T05:26:00Z")
        self.assertEqual(got["checks"], {"pass": 5, "fail": 0, "pending": 0})
        self.assertEqual([e["ts"] for e in got["activity"]], ["2026-11-24T05:32:24Z"])
        self.assertIsNone(got["returned"])

    def test_returned_with_since(self):
        pr = {"state": "merged", "author": "x", "reviewers": [], "events": []}
        got = github_facts("epc#1312", lambda r, n: pr, lambda r, n: NO_EXTRA, ME, LAST,
                           datetime.fromisoformat("2026-11-20T13:42:00+09:00"))
        self.assertTrue(got["returned"])

    def test_bots_are_not_activity(self):
        pr = {"state": "merged", "author": "x", "reviewers": [], "events": [
            {"user": "github-actions[bot]", "ts": "2026-11-24T05:00:00Z", "kind": "comment", "state": None},
            {"user": "claude", "ts": "2026-11-24T05:01:00Z", "kind": "comment", "state": None}]}
        got = github_facts("epc#1300", lambda r, n: pr, lambda r, n: NO_EXTRA, ME, LAST, None)
        self.assertEqual([e["user"] for e in got["activity"]], ["claude"])

    def test_issue_skips_extra(self):
        issue = {"state": "open", "events": [], "is_issue": True, "closed_at": None}

        def extra(r, n):
            raise AssertionError("issue では呼ばない")

        got = github_facts("epc#1222", lambda r, n: issue, extra, ME, LAST, None)
        self.assertIsNone(got["checks"])

    def test_fetch_error_is_reported(self):
        def boom(r, n):
            raise RuntimeError("gh 失敗")

        got = github_facts("epc#1", boom, boom, ME, LAST, None)
        self.assertIsNone(got["state"])
        self.assertIn("gh 失敗", got["error"])


class BuildTest(unittest.TestCase):
    def test_dedups_refs_and_splits_gitbucket(self):
        collected = {
            "today": "2026-11-24",
            "todo": [{"ref": "epc#1316"}, {"ref": "gb:ebase-web#102"}, {"ref": "title:何か"}, {"ref": "rc:abc", "url": "https://team.ebase-jp.com/direct/zz?msg=a"}],
            "handoffs": [{"path": "/m/h1.md", "refs": ["epc#1316", "gb:ebase-web#102"], "wait_refs": ["epc#1316"],
                          "since": "2026-11-20T17:42:00+09:00", "summary": "s"}],
            "warnings": [],
        }
        seen = []

        def facts(ref, since, last_check):
            seen.append((ref, since, last_check.isoformat()))
            return {"ref": ref}

        with tempfile.TemporaryDirectory() as d:
            out = build(collected, commander_text=None, sessions=[], memo_dir=Path(d), facts=facts,
                        memo_text=lambda p: "## 待っているもの\n- 192.168.160.92 の起動\n",
                        connect=lambda ip, port, t: port == 80, now=LAST)
        self.assertEqual(seen, [("epc#1316", "2026-11-20T17:42:00+09:00", "2026-11-24T00:00:00+09:00")])
        self.assertEqual(out["gitbucket_refs"], ["gb:ebase-web#102"])
        self.assertEqual(out["reachability"], [{"ip": "192.168.160.92", "open": [80], "memo": "/m/h1.md"}])
        self.assertEqual(out["last_check"], "2026-11-24T00:00:00+09:00")
        self.assertEqual(out["rocketchat_rooms"], [{"kind": "direct", "room": "zz"}])

    def test_includes_refs_in_commander_file(self):
        collected = {"today": "2026-11-24", "todo": [{"ref": "epc#1302"}], "handoffs": [], "warnings": []}
        text = "# 司令塔\n## 引き継ぐ欄\n### メモ\n- epc#1308 はマージ判断待ち。epc#1302 と組\n"
        with tempfile.TemporaryDirectory() as d:
            out = build(collected, commander_text=text, sessions=None, memo_dir=Path(d),
                        facts=lambda ref, since, lc: {"ref": ref}, memo_text=lambda p: "",
                        connect=lambda ip, port, t: False, now=LAST)
        self.assertEqual([g["ref"] for g in out["github"]], ["epc#1302", "epc#1308"])



class RcRoomsTest(unittest.TestCase):
    def test_rooms_from_links(self):
        texts = ["https://team.ebase-jp.com/direct/i9o3NbG?msg=pN9", "x https://team.ebase-jp.com/direct/i9o3NbG?msg=krY",
                 "https://team.ebase-jp.com/group/%E3%83%91%E3%82%A4%E3%83%AD%E3%83%83%E3%83%88?msg=vzn",
                 "https://team.ebase-jp.com/channel/general", None]
        self.assertEqual(rc_rooms(texts), [{"kind": "direct", "room": "i9o3NbG"},
                                           {"kind": "group", "room": "パイロット"},
                                           {"kind": "channel", "room": "general"}])


if __name__ == "__main__":
    unittest.main()
