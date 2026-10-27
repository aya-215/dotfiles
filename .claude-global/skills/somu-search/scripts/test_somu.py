import contextlib
import io
import json
import os
import re
import shutil
import socket
import tempfile
import unittest
import zipfile

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

    def test_snippet_literal_backslash_n(self):
        # eBASE の MEMO 項目は改行を「\n」という2文字で持っている
        self.assertEqual(somu.snippet("a\\n\\nX\\nb", "X", 10), "a X b")

    def test_detail_url(self):
        self.assertEqual(somu.detail_url("http://example.invalid/v4/", "00204", "t1"),
                         "http://example.invalid/v4/DispDetail.do?volumeName=00204&itemID=t1")


class CliTestBase(CacheTestBase):
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


class CliTest(CliTestBase):
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


MIN_PDF = b"""%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
4 0 obj<</Length 41>>stream
BT /F1 12 Tf 20 100 Td (Hello PDF) Tj ET
endstream endobj
5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
trailer<</Root 1 0 R>>
%%EOF
"""

W_NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
S_NS = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'


class AttachmentTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write_zip(self, name, members):
        path = os.path.join(self.tmp.name, name)
        with zipfile.ZipFile(path, "w") as z:
            for k, v in members.items():
                z.writestr(k, v)
        return path

    def test_file_url(self):
        self.assertEqual(somu.file_url("http://example.invalid/volume/", "00204", "file0222\\t010.pdf"),
                         "http://example.invalid/volume/00204/imag/file0222/t010.pdf")

    def test_is_old(self):
        self.assertTrue(somu.is_old({"link_comment": "OLD 2019"}))
        self.assertFalse(somu.is_old({"link_comment": "2024/9/19更新"}))
        self.assertFalse(somu.is_old({}))

    def test_extract_docx(self):
        p = self.write_zip("a.docx", {"word/document.xml":
            f'<w:document {W_NS}><w:body><w:p><w:r><w:t>第1</w:t></w:r><w:r><w:t>条</w:t></w:r></w:p>'
            f'<w:p><w:r><w:t>在宅勤務</w:t></w:r></w:p></w:body></w:document>'})
        self.assertEqual(somu.extract_text(p, "DOCX"), "第1条\n在宅勤務")

    def test_extract_xlsx(self):
        p = self.write_zip("a.xlsx", {
            "xl/sharedStrings.xml": f'<sst {S_NS}><si><t>IP</t></si><si><t>PC名</t></si></sst>',
            "xl/worksheets/sheet1.xml": f'<worksheet {S_NS}><sheetData><row r="1">'
                                        '<c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
                                        '<row r="2"><c r="A2"><v>42</v></c></row></sheetData></worksheet>'})
        text = somu.extract_text(p, "xlsx")
        self.assertIn("IP\tPC名", text)
        self.assertIn("42", text)

    def test_extract_txt_cp932(self):
        p = os.path.join(self.tmp.name, "a.txt")
        with open(p, "wb") as f:
            f.write("よくある質問".encode("cp932"))
        self.assertEqual(somu.extract_text(p, "TXT"), "よくある質問")

    def test_extract_doc_unsupported(self):
        p = os.path.join(self.tmp.name, "a.doc")
        open(p, "wb").close()
        with self.assertRaises(somu.Unsupported):
            somu.extract_text(p, "DOC")

    def test_extract_pdf(self):
        if not shutil.which("pdftotext"):
            self.skipTest("pdftotext が無い")
        p = os.path.join(self.tmp.name, "a.pdf")
        with open(p, "wb") as f:
            f.write(MIN_PDF)
        self.assertIn("Hello PDF", somu.extract_text(p, "PDF"))


class AttachmentCliTest(CliTestBase):
    IMAGES = resp(
        "<image><file_id>f_old</file_id><filename>file0001\\f_old.txt</filename><format>TXT</format>"
        "<link_title>旧規則</link_title><download_name>old.txt</download_name><link_comment>old</link_comment></image>"
        "<image><file_id>f_doc</file_id><filename>file0002\\f_doc.doc</filename><format>DOC</format>"
        "<link_title>申請書</link_title><download_name>申請書.doc</download_name><link_comment/></image>"
        "<image><file_id>f_txt</file_id><filename>file0003\\f_txt.txt</filename><format>TXT</format>"
        "<link_title>新規則</link_title><download_name>new.txt</download_name><link_comment>2024</link_comment></image>")

    def setUp(self):
        super().setUp()
        self.fetched = []
        orig = somu.fetch_file

        def fake_fetch(url, dest):
            self.fetched.append(url)
            with open(dest, "wb") as f:
                f.write(("本文:" + url.rsplit("/", 1)[1]).encode("utf-8"))
        somu.fetch_file = fake_fetch
        self.addCleanup(setattr, somu, "fetch_file", orig)

    def test_cli_files_old_last(self):
        rc, out, _ = self.run_main(["files", "204", "t1"], {"getItemImage": self.IMAGES})
        self.assertEqual(rc, 0)
        self.assertLess(out.index("新規則"), out.index("旧規則"))
        self.assertIn("http://example.invalid/volume/00204/imag/file0003/f_txt.txt", out)

    def test_cli_text_skips_old_and_unsupported(self):
        rc, out, _ = self.run_main(["text", "204", "t1"], {"getItemImage": self.IMAGES})
        self.assertEqual(rc, 0)
        self.assertIn("本文:f_txt.txt", out)
        self.assertNotIn("本文:f_old.txt", out)
        self.assertIn("テキストにできへん", out)
        self.assertEqual(len(self.fetched), 1)

    def test_cli_text_by_file_id_includes_old(self):
        rc, out, _ = self.run_main(["text", "204", "t1", "f_old"], {"getItemImage": self.IMAGES})
        self.assertIn("本文:f_old.txt", out)

    def test_cli_text_max_chars(self):
        rc, out, _ = self.run_main(["text", "204", "t1", "--max-chars", "4"], {"getItemImage": self.IMAGES})
        self.assertIn("本文:f", out)
        self.assertNotIn("本文:f_txt.txt", out)


if __name__ == "__main__":
    unittest.main()
