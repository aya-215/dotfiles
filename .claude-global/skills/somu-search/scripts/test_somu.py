import json
import os
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


if __name__ == "__main__":
    unittest.main()
