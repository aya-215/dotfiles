import os
import sys
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from status import build, changed_handoffs, ended_sessions, rc_digest, rc_rooms, closed_sessions, github_facts, probe, read_last_check, wait_ips  # noqa: E402

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
            got = changed_handoffs(Path(d), datetime.fromisoformat("2026-11-24T12:00:00+09:00"), [])
        self.assertEqual([(h["status"], h["summary"]) for h in got], [("resolved", "本番配置")])
        self.assertEqual(got[0]["last_heading"], "2026-11-24 本番 eBASE 側の作業（完了）")

    def test_unreadable_memo_is_skipped(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "handoff-20261124-1000-gone.md").symlink_to(Path(d) / "nothing.md")
            (Path(d) / "handoff-20261124-1001-sjis.md").write_bytes("status: 待ち\n".encode("cp932"))
            ok = Path(d) / "handoff-20261124-1002-ok.md"
            ok.write_text("---\nstatus: blocked\n---\n", encoding="utf-8")
            w = []
            got = changed_handoffs(Path(d), MIDNIGHT, w)
        self.assertEqual([Path(h["path"]).name for h in got], ["handoff-20261124-1002-ok.md"])
        self.assertEqual(len(w), 2)

    def test_last_heading_skips_boilerplate(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "handoff-20261124-1042-x.md"
            p.write_text("---\nstatus: blocked\n---\n## 待っているもの\n## 今の状態\n## 次にやること\n## 関連\n## 元のセッション\n- id\n", encoding="utf-8")
            got = changed_handoffs(Path(d), MIDNIGHT, [])
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

    def test_comment_does_not_hide_approve(self):
        pr = {"state": "open", "author": "x", "reviewers": [], "events": [
            {"user": "a", "ts": "2026-11-24T05:00:00Z", "kind": "review", "state": "APPROVED"},
            {"user": "a", "ts": "2026-11-24T05:10:00Z", "kind": "review", "state": "COMMENTED"},
            {"user": "b", "ts": "2026-11-24T05:20:00Z", "kind": "review", "state": "COMMENTED"}]}
        got = github_facts("epc#1", lambda r, n: pr, lambda r, n: NO_EXTRA, ME, LAST, None)
        self.assertEqual(got["reviews"], {"a": "APPROVED", "b": "COMMENTED"})

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



RC_TEXT = """（表示名: matsumoto.h=松本久方）
===== AI開発 [発言3] 7/13件 ===== {rid:R t:p link:L}
  01:58 matsumoto.h: 古い {id:a}
  06:10 matsumoto.h [↳01:58 mori.a]: 新しい {id:b}
===== DM:kawai [発言0] 1/1件 ===== {rid:D t:d link:L2}
  02:00 kawai: 古いDM {id:c}
===== mori.a-times [発言1] 1/1件 =====
  07:00 mori.a: 自分だけ {id:d}
===== 夜 [発言0] 1/1件 =====
  15:30 kawai: 日付が変わってすぐ {id:e}
"""


class RcDigestTest(unittest.TestCase):
    def test_keeps_new_messages_from_others_in_jst(self):
        got = rc_digest(RC_TEXT, datetime.fromisoformat("2026-11-24T12:00:00+09:00"), TODAY, "mori.a")
        self.assertEqual(got.splitlines(), [
            "（表示名: matsumoto.h=松本久方）",
            "===== AI開発 [発言3] 7/13件 ===== {rid:R t:p link:L}",
            "  15:10 matsumoto.h [↳10:58 mori.a]: 新しい {id:b}",
        ])

    def test_previous_day_last_check_keeps_all_but_converts(self):
        got = rc_digest(RC_TEXT, datetime.fromisoformat("2026-11-23T18:00:00+09:00"), TODAY, "mori.a")
        self.assertIn("  10:58 matsumoto.h: 古い {id:a}", got)
        self.assertIn("  00:30 kawai: 日付が変わってすぐ {id:e}", got)
        self.assertNotIn("自分だけ", got)

    def test_empty(self):
        self.assertEqual(rc_digest("", MIDNIGHT, TODAY, "mori.a"), "")


LC = datetime.fromisoformat("2026-11-25T10:00:00+09:00")
SID = "3a140506-0ad4-4073-9e6a-d421b10d8415"
SID2 = "862adf99-0000-4000-8000-000000000000"
PORTAL = "/home/aya/src/github.com/ebase-dev/ebase-portal-chat"


def _row(*cols):
    return "\t".join(cols)


def _summary(root, day, name, sid, end, conclusion="本番 00002 は0件。\n\n残りはリリースのみ。", cwd=PORTAL,
             mtime=None, with_end=True):
    p = Path(root) / day / name
    p.parent.mkdir(parents=True, exist_ok=True)
    front = [f"project: {Path(cwd).name}", f"session_id: {sid}", "start: 2026-11-25T01:33:37.982Z"]
    if with_end:
        front.append(f"end: {end}")
    front.append(f"cwd: {cwd}")
    body = "## 意図\n確認する。\n\n"
    if conclusion is not None:
        body += f"## 結論\n{conclusion}\n\n"
    body += "## 編集/作成ファイル\n- なし\n"
    p.write_text("---\n" + "\n".join(front) + "\n---\n\n" + body, encoding="utf-8")
    if mtime is not None:
        os.utime(p, (mtime.timestamp(), mtime.timestamp()))
    return p


class EndedSessionsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = self.tmp.name
        self.w = []

    def tearDown(self):
        self.tmp.cleanup()

    def test_picks_summary_written_after_last_check(self):
        p = _summary(self.d, "2026-11-25", "ebase-portal-chat-1047-3a140506.md", SID, "2026-11-25T01:47:14.527Z")
        pane_map = "\n".join([_row("shifton-00002-check", "1", "2", PORTAL, SID),
                              _row("END", "shifton-00002-check", "1", "2", PORTAL, SID)]) + "\n"
        out = ended_sessions(Path(self.d), pane_map, LC, [{"name": "shifton-00002-check", "self": False}], self.w)
        self.assertEqual(out, [{"tmux": "shifton-00002-check", "project": "ebase-portal-chat",
                                "end": "2026-11-25T10:47:14.527000+09:00", "alive": True,
                                "conclusion": "本番 00002 は0件。\n残りはリリースのみ。", "path": str(p)}])
        self.assertEqual(self.w, [])

    def test_late_summary_is_picked_next_time(self):
        _summary(self.d, "2026-11-25", "a-0955-3a140506.md", SID, "2026-11-25T00:55:00Z")
        out = ended_sessions(Path(self.d), None, LC, [], self.w)
        self.assertEqual(len(out), 1)

    def test_old_mtime_is_skipped(self):
        _summary(self.d, "2026-11-25", "a-0955-3a140506.md", SID, "2026-11-25T00:55:00Z",
                 mtime=LC - timedelta(minutes=1))
        self.assertEqual(ended_sessions(Path(self.d), None, LC, [], self.w), [])

    def test_picks_session_closed_days_after_last_message(self):
        # 金曜に最後の発言、月曜に閉じた会話は end の日付のフォルダに今日書かれる
        _summary(self.d, "2026-11-21", "a-1500-3a140506.md", SID, "2026-11-21T06:00:00Z")
        out = ended_sessions(Path(self.d), None, LC, [], self.w)
        self.assertEqual(len(out), 1)

    def test_end_guard_skips_regenerated_old_summary(self):
        # フォルダは窓の中でも end が下限より古ければはじく（一括再生成で更新時刻だけ新しくなる）
        _summary(self.d, "2026-11-24", "a-1200-3a140506.md", SID, "2026-11-01T03:00:00Z")
        self.assertEqual(ended_sessions(Path(self.d), None, LC, [], self.w), [])

    def test_folder_window_skips_old_folders(self):
        _summary(self.d, "2026-11-01", "a-1200-3a140506.md", SID, "2026-11-24T03:00:00Z")
        self.assertEqual(ended_sessions(Path(self.d), None, LC, [], self.w), [])

    def test_scans_previous_day_folder(self):
        lc = datetime.fromisoformat("2026-11-25T09:00:00+09:00")
        _summary(self.d, "2026-11-24", "a-2358-3a140506.md", SID, "2026-11-24T14:58:00Z")
        out = ended_sessions(Path(self.d), None, lc, [], self.w)
        self.assertEqual([x["end"] for x in out], ["2026-11-24T23:58:00+09:00"])

    def test_uses_last_live_row_for_tmux_name(self):
        _summary(self.d, "2026-11-25", "a-1100-3a140506.md", SID, "2026-11-25T02:00:00Z")
        pane_map = "\n".join([_row("_dotfiles", "1", "1", PORTAL, SID), _row("hankyu-102", "1", "2", PORTAL, SID),
                              _row("END", "hankyu-102", "1", "2", PORTAL, SID)]) + "\n"
        out = ended_sessions(Path(self.d), pane_map, LC, [], self.w)
        self.assertEqual(out[0]["tmux"], "hankyu-102")

    def test_falls_back_to_cwd_name(self):
        _summary(self.d, "2026-11-25", "a-1100-3a140506.md", SID, "2026-11-25T02:00:00Z")
        out = ended_sessions(Path(self.d), None, LC, [], self.w)
        self.assertEqual(out[0]["tmux"], "ebase-portal-chat")

    def test_excludes_commander_self(self):
        _summary(self.d, "2026-11-25", "memo-1100-3a140506.md", SID, "2026-11-25T02:00:00Z")
        pane_map = _row("commander", "1", "1", "/home/aya/memo", SID) + "\n"
        out = ended_sessions(Path(self.d), pane_map, LC, [{"name": "commander", "self": True}], self.w)
        self.assertEqual(out, [])

    def test_sessions_unknown(self):
        _summary(self.d, "2026-11-25", "a-1100-3a140506.md", SID, "2026-11-25T02:00:00Z")
        out = ended_sessions(Path(self.d), None, LC, None, self.w)
        self.assertIsNone(out[0]["alive"])

    def test_no_conclusion_heading(self):
        _summary(self.d, "2026-11-25", "a-1100-3a140506.md", SID, "2026-11-25T02:00:00Z", conclusion=None)
        out = ended_sessions(Path(self.d), None, LC, [], self.w)
        self.assertEqual(out[0]["conclusion"], "")

    def test_bad_end_is_warned_and_skipped(self):
        _summary(self.d, "2026-11-25", "a-1100-3a140506.md", SID, "", with_end=False)
        _summary(self.d, "2026-11-25", "b-1100-862adf99.md", SID2, "2026-11-25T02:00:00Z")
        out = ended_sessions(Path(self.d), None, LC, [], self.w)
        self.assertEqual(len(out), 1)
        self.assertEqual(len(self.w), 1)
        self.assertIn("終わった会話の要約を読めない", self.w[0])

    def test_sorted_by_end(self):
        _summary(self.d, "2026-11-25", "a-1100-3a140506.md", SID, "2026-11-25T02:00:00Z")
        _summary(self.d, "2026-11-25", "b-1030-862adf99.md", SID2, "2026-11-25T01:30:00Z")
        out = ended_sessions(Path(self.d), None, LC, [], self.w)
        self.assertEqual([x["end"][11:16] for x in out], ["10:30", "11:00"])


if __name__ == "__main__":
    unittest.main()
