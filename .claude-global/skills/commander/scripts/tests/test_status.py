import os
import sys
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from status import changed_handoffs, closed_sessions, probe, read_last_check, wait_ips  # noqa: E402

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


if __name__ == "__main__":
    unittest.main()
