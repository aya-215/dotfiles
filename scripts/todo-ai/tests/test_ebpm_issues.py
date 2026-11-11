import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
import ebpm_issues as E

ME = "森彪人"


def spec(title, value, typ="X"):
    return f"<spec><spec_type>{typ}</spec_type><spec_title>{title}</spec_title><value>{value}</value></spec>"


def basic(item_id, date):
    return (f"<spec><target>item_id</target><value>{item_id}</value></spec>"
            f"<spec><target>registered_date</target><value>{date}</value></spec>")


def comment(item_id, date, no="No00007435", title="HKY：件名", by=ME, to="", text="本文", deleted="0", ts=""):
    return ("<item>" + basic(item_id, date) + spec("課題No", no) + spec("課題名", title)
            + spec("属性", "コメント") + spec("コメント", text) + spec("コメント登録者", by)
            + spec("お知らせ先担当者", to) + spec("削除済みフラグ", deleted) + spec("登録時刻", ts) + "</item>")


def issue(item_id, no, status, who=ME, title="課題"):
    return ("<item>" + basic(item_id, "2026/10/01") + spec("課題No", no) + spec("課題名", title)
            + spec("属性", "課題") + spec("状況", status) + spec("担当者名", who) + "</item>")


def resp(body, status=200):
    return f'<?xml version="1.0"?><response><status>{status}</status><data>{body}</data></response>'


def ids_resp(*ids):
    return resp("".join(f"<item><item_id>{i}</item_id></item>" for i in ids))


class ParseTest(unittest.TestCase):
    def test_parse_ids_with_crlf(self):
        self.assertEqual(E.parse_item_ids(ids_resp("a1", "a2").replace("\n", "\r\n")), ["a1", "a2"])

    def test_no_data_is_empty(self):
        x = '<response><status>404</status><data><error message="no data"/></data></response>'
        self.assertEqual(E.parse_item_ids(x), [])
        self.assertEqual(E.parse_records(x), [])

    def test_other_error_raises(self):
        with self.assertRaises(E.EbpmError):
            E.parse_item_ids("<response><status>500</status></response>")

    def test_records_literal_backslash_n_and_basic(self):
        r = E.parse_records(resp(comment("c1", "2026/11/10", text="a\\nb")))[0]
        self.assertEqual(r["item_id"], "c1")
        self.assertEqual(r["registered_date"], "2026/11/10")
        self.assertEqual(r["コメント"], "a\nb")

    def test_norm_and_date(self):
        self.assertEqual(E.norm("森 彪人"), "森彪人")
        self.assertEqual(E.norm("森　彪人"), "森彪人")
        self.assertEqual(E.to_date("2026/11/9 10:00:00"), "2026-11-09")
        self.assertIsNone(E.to_date(""))


class FakeApi:
    def __init__(self, handler):
        self.handler = handler
        self.calls = []

    def __call__(self, xml):
        self.calls.append(xml)
        return self.handler(xml)


def run(handler, since="2026-11-01", max_calls=40):
    api = FakeApi(handler)
    with mock.patch.object(E.time, "sleep"):
        out = E.collect(since, ME, post=api, max_calls=max_calls)
    return out, api


class CollectTest(unittest.TestCase):
    def handler(self, xml):
        if "getItems" in xml:
            if "コメント登録者" in xml:
                return ids_resp("c1", "c2")
            if "お知らせ先担当者" in xml:
                return ids_resp("c2", "c3")
            if "担当者名" in xml:
                return ids_resp("i1", "i2", "i3")
            if "課題No" in xml:
                return ids_resp("ISSUE-No8", "ISSUE-No9")
        if "getSpecDataLite" in xml:
            if "<item_id>ISSUE-" in xml:
                return resp(issue("ISSUE-No8", "No8", "対応中") + issue("ISSUE-No9", "No9", "対応中"))
            if "<item_id>i1" in xml:
                return resp(issue("i1", "No1", "対応中") + issue("i2", "No2", "完了") + issue("i3", "No3", "クローズ"))
            return resp(
                comment("c3", "2026/11/09", no="No9", by="吉田哲也", to="吉田 森彪人", text="お願い")
                + comment("c2", "2026/11/05", no="No8", by=ME, to="森彪人")
                + comment("c1", "2026/10/20", no="No7", by=ME)
            )
        raise AssertionError(xml)

    def test_filters_and_classifies(self):
        out, _ = run(self.handler)
        self.assertIsNone(out["failed"])
        self.assertEqual(out["me"], ME)
        self.assertEqual([c["issue_no"] for c in out["comments"]], ["No8"])
        self.assertEqual([n["issue_no"] for n in out["notices"]], ["No9"])
        self.assertEqual(out["notices"][0]["by"], "吉田哲也")
        self.assertEqual([a["issue_no"] for a in out["assigned"]], ["No1"])
        self.assertEqual(out["comments"][0]["issue_item_id"], "ISSUE-No8")
        self.assertIn("itemID=ISSUE-No8", out["comments"][0]["url"])
        json.dumps(out, ensure_ascii=False)

    def test_deleted_comment_skipped(self):
        def h(xml):
            if "getItems" in xml:
                return ids_resp("c1") if "コメント登録者" in xml else ids_resp()
            return resp(comment("c1", "2026/11/09", deleted="1"))
        out, _ = run(h)
        self.assertEqual(out["comments"], [])

    def test_stops_after_old_chunk(self):
        ids = [f"t{n:012d}" for n in range(100)]

        def h(xml):
            if "getItems" in xml:
                return ids_resp(*ids) if "コメント登録者" in xml else ids_resp()
            return resp("".join(comment(i, "2026/09/01") for i in ids[:30]))
        out, api = run(h)
        fetches = [c for c in api.calls if "getSpecDataLite" in c]
        self.assertEqual(len(fetches), 1)
        self.assertIn("<item_id>t000000000099</item_id>", fetches[0])
        self.assertIn("stopped early at t000000000099", out["notes"][0])
        self.assertLessEqual(fetches[0].count("<item_id>"), 30)

    def test_no_early_stop_when_id_format_unexpected(self):
        ids = [f"c{n:03d}" for n in range(60)]
        n = [0]

        def h(xml):
            if "getItems" in xml:
                return ids_resp(*ids) if "コメント登録者" in xml else ids_resp()
            n[0] += 1
            return resp("".join(comment(i, "2026/09/01") for i in range(1)))
        out, _ = run(h)
        self.assertEqual(n[0], 2)
        self.assertEqual(out["notes"], [])

    def test_assigned_beyond_30_not_dropped(self):
        ids = [f"t{n:012d}" for n in range(45)]

        def h(xml):
            if "getItems" in xml:
                return ids_resp(*ids) if "担当者名" in xml else ids_resp()
            got = [i for i in ids if f"<item_id>{i}<" in xml]
            return resp("".join(issue(i, "No" + i, "進行中") for i in got))
        out, _ = run(h)
        self.assertEqual(len(out["assigned"]), 45)

    def test_issue_lookup_batched_and_partial_on_cap(self):
        nos = [f"No{n:08d}" for n in range(30)]
        recs = "".join(comment(f"t{n:012d}", "2026/11/09", no=nos[n]) for n in range(30))

        def h(xml):
            if "getItems" in xml:
                return ids_resp(*[f"t{n:012d}" for n in range(30)]) if "コメント登録者" in xml else ids_resp()
            return resp(recs)
        out, api = run(h)
        self.assertEqual(len(out["comments"]), 30)
        lookups = [c for c in api.calls if "課題No" in c and "getItems" in c]
        self.assertEqual(len(lookups), 2)  # 25件ずつ
        out, _ = run(h, max_calls=5)
        self.assertEqual(len(out["comments"]), 30)
        self.assertIn("call cap", out["failed"])
        self.assertTrue(out["truncated"])

    def test_xml_attribute_escaped(self):
        def h(xml):
            ET = __import__("xml.etree.ElementTree", fromlist=["x"])
            ET.fromstring(xml.split("?>", 1)[1].encode())
            return ids_resp()
        api = FakeApi(h)
        with mock.patch.object(E.time, "sleep"):
            out = E.collect("2026-11-01", 'a"<&b', post=api)
        self.assertIsNone(out["failed"])

    def test_max_calls_floor(self):
        out, api = run(self.handler, max_calls=0)
        self.assertEqual(len(api.calls), 1)

    def test_connection_error_sets_failed(self):
        def h(xml):
            raise E.EbpmError("timeout")
        out, _ = run(h)
        self.assertIn("timeout", out["failed"])
        self.assertEqual(out["comments"], [])

    def test_call_cap_reports_failed(self):
        out, api = run(self.handler, max_calls=2)
        self.assertIn("call cap", out["failed"])
        self.assertLessEqual(len(api.calls), 2)

    def test_sleeps_between_calls(self):
        api = FakeApi(self.handler)
        with mock.patch.object(E.time, "sleep") as sl:
            E.collect("2026-11-01", ME, post=api, max_calls=40)
        self.assertEqual(sl.call_count, len(api.calls) - 1)


class CliTest(unittest.TestCase):
    def test_main_exit0_on_failure(self):
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        with mock.patch.object(E, "curl_post", side_effect=E.EbpmError("down")), \
                mock.patch.object(E.time, "sleep"), redirect_stdout(buf):
            rc = E.main(["--since", "2026-11-01"])
        self.assertEqual(rc, 0)
        self.assertIn("down", json.loads(buf.getvalue())["failed"])


if __name__ == "__main__":
    unittest.main()
