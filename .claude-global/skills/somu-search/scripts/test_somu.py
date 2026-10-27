import contextlib
import io
import json
import os
import re
import socket
import tempfile
import unittest

import somu

API = "http://example.invalid:8080/x/eb-api"


def resp(inner, status=200):
    return f'<?xml version="1.0" encoding="UTF-8"?><response><status>{status}</status><data>{inner}</data></response>'


class FakePost:
    """コマンド名ごとに応答 XML を返し、送られたリクエストを記録する。"""

    def __init__(self, replies):
        self.replies = replies
        self.raw = []
        self.sent = []

    def __call__(self, url, body):
        self.raw.append(body)
        text = body.decode("utf-8")
        self.sent.append(text)
        cmd = text.split('<command name="')[1].split('"')[0]
        reply = self.replies[cmd]
        if callable(reply):
            reply = reply(text)
        if isinstance(reply, Exception):
            raise reply
        return reply.encode("utf-8")

    def count(self, cmd):
        return sum(f'<command name="{cmd}"' in s for s in self.sent)


def spec_xml(title, value):
    return (f"<spec><spec_type>メインスペック</spec_type><spec_title>{title}</spec_title>"
            f"<value>{value}</value></spec>")


class ConfigTest(unittest.TestCase):
    def test_norm_vol(self):
        self.assertEqual(somu.norm_vol("204"), "00204")
        self.assertEqual(somu.norm_vol("204_WK"), "00204_WK")
        self.assertEqual(somu.norm_vol("00204"), "00204")

    def test_load_config_derives_file_base(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"mcpServers": {"eb-api-somu": {"headers": {
                "ebase-api-url": API,
                "ebase-viewer-url": "http://example.invalid/somu_v4"}}}}, f)
        self.addCleanup(os.unlink, f.name)
        cfg = somu.load_config(f.name)
        self.assertEqual(cfg.api_url, API)
        self.assertEqual(cfg.viewer_url, "http://example.invalid/somu_v4")
        self.assertEqual(cfg.file_base, "http://example.invalid/volume/")

    def test_load_config_missing_raises(self):
        with self.assertRaises(somu.SomuError):
            somu.load_config("/nonexistent.json")


class ApiTest(unittest.TestCase):
    def api(self, replies):
        fake = FakePost(replies)
        return somu.Api(API, post=fake), fake

    def test_volumes_parses(self):
        api, _ = self.api({"getVolume": resp(
            "<volume><voldbname>00001</voldbname><volname>テスト</volname></volume>")})
        self.assertEqual(api.volumes(), [("00001", "テスト")])

    def test_spec_info_parses(self):
        api, fake = self.api({"getSpecInfo": resp(
            "<spec><spec_type>メインスペック</spec_type><spec_title>IPアドレス</spec_title>"
            "<data_type>TEXT</data_type></spec>")})
        self.assertEqual(api.spec_info("00095"),
                         [{"spec_type": "メインスペック", "spec_title": "IPアドレス", "data_type": "TEXT"}])
        self.assertIn('<spec all="true" invisible="false"/>', fake.sent[-1])

    def test_item_ids_sends_empty_search(self):
        api, fake = self.api({"getItems": resp(
            "<item><item_id>t1</item_id></item><item><item_id>t2</item_id></item>")})
        self.assertEqual(api.item_ids("00204"), ["t1", "t2"])
        self.assertIn('<search target="SPEC"></search>', fake.sent[-1])

    def test_spec_values_drops_inv_and_empty(self):
        item = ("<item><spec><target>item_id</target><value>t1</value></spec>"
                + spec_xml("invデータ登録日", "2021/01/01") + spec_xml("IPアドレス", "10.0.0.1")
                + "<spec><spec_type>メインスペック</spec_type><spec_title>OS</spec_title><value/></spec></item>")
        api, _ = self.api({"getSpecDataLite": resp(item)})
        self.assertEqual(api.spec_values("00095", ["t1"], "メインスペック"), {"t1": {"IPアドレス": "10.0.0.1"}})

    def test_spec_values_404_raises(self):
        api, _ = self.api({"getSpecDataLite": resp("", status=404)})
        with self.assertRaises(somu.SomuError):
            api.spec_values("00095", ["t1"], "X")

    def test_item_files_parses(self):
        api, _ = self.api({"getItemImage": resp(
            "<image><file_id>f1</file_id><filename>file0001\\f1.pdf</filename><format>PDF</format></image>")})
        self.assertEqual(api.item_files("00204", "t1"),
                         [{"file_id": "f1", "filename": "file0001\\f1.pdf", "format": "PDF"}])

    def test_post_failure_is_somu_error(self):
        # 固定ポートは WSL で接続待ちのまま固まることがあるので、確実に閉じているポートを拾う
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        api = somu.Api(f"http://127.0.0.1:{port}/eb-api")
        with self.assertRaises(somu.SomuError) as cm:
            api.volumes()
        self.assertIn("接続できへん", str(cm.exception))

    def test_request_is_utf8_bytes(self):
        api, fake = self.api({"getSpecInfo": resp("")})
        api.spec_info("00204")
        self.assertIsInstance(fake.raw[-1], bytes)


def ids_xml(n):
    return resp("".join(f"<item><item_id>t{i:05d}</item_id></item>" for i in range(n)))


def values_reply(bad_type=None):
    """リクエストされた item ごとに IPアドレス を返す。bad_type の型だけ 404。"""
    def reply(text):
        if bad_type and f'spec_type="{bad_type}"' in text:
            return resp("", status=404)
        ids = re.findall(r"<item_id>([^<]+)</item_id>", text)
        return resp("".join(
            f"<item><spec><target>item_id</target><value>{i}</value></spec>{spec_xml('IPアドレス', '10.0.0.' + i[-2:])}</item>"
            for i in ids))
    return reply


def info_xml(*types):
    return resp("".join(
        f"<spec><spec_type>{t}</spec_type><spec_title>IPアドレス</spec_title><data_type>TEXT</data_type></spec>"
        for t in types))


class CacheTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        os.environ["SOMU_SEARCH_CACHE"] = self.tmp.name
        self.addCleanup(os.environ.pop, "SOMU_SEARCH_CACHE", None)


class DumpTest(CacheTestBase):
    def test_dump_batches_by_200_and_saves(self):
        fake = FakePost({"getItems": ids_xml(450), "getSpecInfo": info_xml("メインスペック", "別"),
                         "getSpecDataLite": values_reply()})
        data = somu.dump_volume(somu.Api(API, post=fake), "00095")
        self.assertEqual(len(data["items"]), 450)
        self.assertEqual(fake.count("getSpecDataLite"), 3 * 2)
        self.assertTrue(os.path.exists(somu.cache_path("00095")))
        self.assertEqual(somu.load_cache("00095")["items"][0]["メインスペック:IPアドレス"], "10.0.0.00")

    def test_dump_large_needs_confirm(self):
        fake = FakePost({"getItems": ids_xml(10001), "getSpecInfo": info_xml("メインスペック"),
                         "getSpecDataLite": values_reply()})
        with self.assertRaises(somu.NeedsConfirm) as cm:
            somu.dump_volume(somu.Api(API, post=fake), "00001")
        self.assertEqual(cm.exception.count, 10001)
        self.assertEqual(fake.count("getSpecDataLite"), 0)

    def test_dump_large_confirmed_proceeds(self):
        fake = FakePost({"getItems": ids_xml(10001), "getSpecInfo": info_xml("メインスペック"),
                         "getSpecDataLite": values_reply()})
        data = somu.dump_volume(somu.Api(API, post=fake), "00001", confirmed=True)
        self.assertEqual(len(data["items"]), 10001)

    def test_dump_skips_failing_spec_type(self):
        fake = FakePost({"getItems": ids_xml(2), "getSpecInfo": info_xml("メインスペック", "壊れ"),
                         "getSpecDataLite": values_reply(bad_type="壊れ")})
        data = somu.dump_volume(somu.Api(API, post=fake), "00095")
        self.assertIn("メインスペック:IPアドレス", data["items"][0])

    def test_connection_loss_mid_dump_aborts(self):
        def flaky(text):
            if 'spec_type="壊れ"' in text:
                return somu.ConnectError("eB-API に接続できへん: timed out")
            return values_reply()(text)
        fake = FakePost({"getItems": ids_xml(2), "getSpecInfo": info_xml("メインスペック", "壊れ"),
                         "getSpecDataLite": flaky})
        with self.assertRaises(somu.ConnectError):
            somu.dump_volume(somu.Api(API, post=fake), "00095")
        self.assertIsNone(somu.load_cache("00095"))

    def test_failed_dump_keeps_old_cache(self):
        ok = FakePost({"getItems": ids_xml(1), "getSpecInfo": info_xml("メインスペック"),
                       "getSpecDataLite": values_reply()})
        old = somu.dump_volume(somu.Api(API, post=ok), "00095")
        broken = FakePost({"getItems": resp("", status=500)})
        with self.assertRaises(somu.SomuError):
            somu.dump_volume(somu.Api(API, post=broken), "00095")
        self.assertEqual(somu.load_cache("00095")["fetched_at"], old["fetched_at"])

    def test_get_or_dump_uses_cache(self):
        fake = FakePost({"getItems": ids_xml(1), "getSpecInfo": info_xml("メインスペック"),
                         "getSpecDataLite": values_reply()})
        api = somu.Api(API, post=fake)
        somu.get_or_dump(api, "00095")
        somu.get_or_dump(api, "00095")
        self.assertEqual(fake.count("getItems"), 1)
        somu.get_or_dump(api, "00095", refresh=True)
        self.assertEqual(fake.count("getItems"), 2)


class SearchTest(unittest.TestCase):
    def ids(self, items, words):
        return [r[0]["item_id"] for r in somu.search(items, words)]

    def test_search_and_width_case(self):
        items = [{"item_id": "t1", "a:b": "ＴＥＬＥワーク規則"}, {"item_id": "t2", "a:b": "出張"}]
        self.assertEqual(self.ids(items, ["teleワーク"]), ["t1"])

    def test_search_and_of_words(self):
        items = [{"item_id": "t1", "a:x": "テレワーク", "a:y": "開発"}, {"item_id": "t2", "a:x": "テレワーク"}]
        self.assertEqual(self.ids(items, ["テレワーク", "開発"]), ["t1"])

    def test_search_returns_hit_keys(self):
        items = [{"item_id": "t1", "a:x": "テレワーク", "a:y": "開発"}]
        self.assertEqual(somu.search(items, ["開発"])[0][1], ["a:y"])

    def test_search_exact_value_first(self):
        items = [{"item_id": "t1", "m:IP": "10.0.1.190"}, {"item_id": "t2", "m:IP": "10.0.1.19"}]
        self.assertEqual(self.ids(items, ["10.0.1.19"]), ["t2", "t1"])

    def test_snippet_ellipsis(self):
        self.assertEqual(somu.snippet("あ" * 100 + "X" + "い" * 100, "X", 3), "…あああXいいい…")

    def test_snippet_newlines_to_space(self):
        self.assertEqual(somu.snippet("a\nX\nb", "X", 5), "a X b")

    def test_detail_url(self):
        self.assertEqual(somu.detail_url("http://example.invalid/v4/", "00204", "t1"),
                         "http://example.invalid/v4/DispDetail.do?volumeName=00204&itemID=t1")


class CliTest(CacheTestBase):
    def run_main(self, argv, replies):
        fake = FakePost(replies)
        cfg = somu.Config(API, "http://example.invalid/v4", "http://example.invalid/volume/")
        orig = somu.load_config, somu.make_api
        somu.load_config = lambda *a: cfg
        somu.make_api = lambda c: somu.Api(c.api_url, post=fake)
        self.addCleanup(lambda: (setattr(somu, "load_config", orig[0]), setattr(somu, "make_api", orig[1])))
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = somu.main(argv)
        return rc, out.getvalue(), err.getvalue()

    def test_cli_large_exit_3(self):
        rc, _, err = self.run_main(["search", "1", "x"], {"getItems": ids_xml(10001)})
        self.assertEqual(rc, 3)
        self.assertIn("10001", err)

    def test_cli_search_prints_hits(self):
        rc, out, _ = self.run_main(["search", "95", "10.0.0.01"], {
            "getItems": ids_xml(3), "getSpecInfo": info_xml("メインスペック"),
            "getSpecDataLite": values_reply(), "getVolume": resp(
                "<volume><voldbname>00095</voldbname><volname>IP管理</volname></volume>")})
        self.assertEqual(rc, 0)
        self.assertIn("3件中 1件ヒット", out)
        self.assertIn("t00001", out)
        self.assertIn("DispDetail.do?volumeName=00095&itemID=t00001", out)

    def test_cli_volumes_hides_work(self):
        rc, out, _ = self.run_main(["volumes", "規定"], {"getVolume": resp(
            "<volume><voldbname>00204</voldbname><volname>■社内規定</volname></volume>"
            "<volume><voldbname>00204_WK</voldbname><volname>■社内規定</volname></volume>")})
        self.assertEqual(rc, 0)
        self.assertIn("00204", out)
        self.assertNotIn("00204_WK", out)

    def test_cli_connection_error_exit_2(self):
        rc, _, err = self.run_main(["volumes"], {"getVolume": somu.SomuError("eB-API に接続できへん: x")})
        self.assertEqual(rc, 2)
        self.assertIn("ERROR: eB-API に接続できへん", err)


if __name__ == "__main__":
    unittest.main()
