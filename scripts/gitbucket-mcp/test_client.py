"""gitbucket_client.py のテスト。実行: uv --directory scripts/gitbucket-mcp run python -m unittest"""

import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import gitbucket_client as client


class _Resp:
    def __init__(self, raw: bytes, url: str = ""):
        self._raw, self._url, self.status = raw, url, 200

    def read(self):
        return self._raw

    def geturl(self):
        return self._url

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class TokenTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cred = Path(self.tmp.name) / "credentials.json"
        patcher = mock.patch.object(client, "CRED_PATH", self.cred)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)
        env = mock.patch.dict(os.environ, {}, clear=False)
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("GITBUCKET_TOKEN", None)

    def test_環境変数のトークンが優先される(self):
        self.cred.write_text(json.dumps({"http://192.168.208.80:8080": "from-file"}))
        os.environ["GITBUCKET_TOKEN"] = "from-env"
        self.assertEqual(client.resolve_token(), "from-env")

    def test_credentialsからoriginのトークンを読む(self):
        self.cred.write_text(json.dumps({"http://192.168.208.80:8080": "t1"}))
        self.assertEqual(client.resolve_token(), "t1")

    def test_credentialsが辞書でなければ設定場所を示すエラー(self):
        self.cred.write_text('["x"]')
        with self.assertRaisesRegex(client.GitBucketError, "credentials.json"):
            client.resolve_token()

    def test_トークンが無いと設定場所を示すエラー(self):
        with self.assertRaisesRegex(client.GitBucketError, "credentials.json"):
            client.resolve_token()


class CallApiTest(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(client, "resolve_token", return_value="t")
        patcher.start()
        self.addCleanup(patcher.stop)

    def _call(self, raw: bytes, method: str = "GET"):
        with mock.patch.object(client.urllib.request, "urlopen", return_value=_Resp(raw)) as m:
            return client.call_api(method, "/x", {"a": 1} if method != "GET" else None), m

    def test_urlopenにtimeoutを渡す(self):
        _, m = self._call(b"[]")
        self.assertEqual(m.call_args.kwargs.get("timeout"), 30)

    def test_DELETEの空の本文は空の辞書(self):
        result, _ = self._call(b"", "DELETE")
        self.assertEqual(result, {})

    def test_GETの空の本文は見つからない扱い(self):
        # GitBucket は存在しない PR の GET /pulls/N に 404 ではなく 200 と空の本文を返す（2026-11-24 実測）
        with self.assertRaises(client.NotFoundError):
            self._call(b"", "GET")

    def test_書き込みの空の本文は静かな失敗としてエラー(self):
        for method in ("POST", "PATCH", "PUT"):
            with self.assertRaisesRegex(client.GitBucketError, "作成・変更されていない可能性"):
                self._call(b"", method)

    def test_書き込み中のタイムアウトは再実行しないよう伝える(self):
        with mock.patch.object(client.urllib.request, "urlopen", side_effect=TimeoutError("timed out")):
            with self.assertRaisesRegex(client.GitBucketError, "再実行せず"):
                client.call_api("POST", "/x", {"a": 1})

    def test_HTTPエラーはGitBucketのメッセージを含める(self):
        err = client.urllib.error.HTTPError("u", 422, "Unprocessable", {}, io.BytesIO(b'{"message":"Ref does not exist."}'))
        with mock.patch.object(client.urllib.request, "urlopen", side_effect=err):
            with self.assertRaisesRegex(client.GitBucketError, "Ref does not exist"):
                client.call_api("DELETE", "/x")

    def test_URLに使えない文字はGitBucketErrorにする(self):
        with self.assertRaises(client.GitBucketError):
            client.call_api("GET", "/repos/o r/x")

    def test_作成系で空の辞書が返ると静かな失敗としてエラー(self):
        with self.assertRaisesRegex(client.GitBucketError, "作成・変更されていない可能性"):
            self._call(b"{}", "POST")

    def test_書き込みの応答を読めないときは再実行しないよう伝える(self):
        with self.assertRaisesRegex(client.GitBucketError, "再実行せず"):
            self._call(b"<html>", "POST")

    def test_PR作成の二重エンコードを戻す(self):
        result, _ = self._call(b'"{\\"number\\": 3}"', "POST")
        self.assertEqual(result, {"number": 3})


if __name__ == "__main__":
    unittest.main()
