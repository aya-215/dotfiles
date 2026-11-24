"""GitBucket REST API と Web 画面の呼び出し、トークンの解決、ツールに返すエラーの型。"""

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from mcp.server.mcpserver.exceptions import ToolError

GITBUCKET_URL = os.environ.get("GITBUCKET_URL", "http://192.168.208.80:8080/gitbucket")
# ebase-infra の gitbucket-api スキルと同じファイル・同じ形式（origin ごとのキー）
CRED_PATH = Path.home() / ".claude" / "gitbucket" / "credentials.json"
TIMEOUT = 30


class GitBucketError(ToolError):
    """ツールの失敗としてクライアントに理由を返すエラー。"""


class NotFoundError(GitBucketError):
    """API が 404 を返した。"""


def _origin(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    return f"{parts.scheme}://{parts.netloc}"


def resolve_token() -> str:
    """環境変数 GITBUCKET_TOKEN、なければ credentials.json の GITBUCKET_URL の origin のトークンを返す。"""
    env = os.environ.get("GITBUCKET_TOKEN")
    if env:
        return env
    origin = _origin(GITBUCKET_URL)
    try:
        token = json.loads(CRED_PATH.read_text(encoding="utf-8")).get(origin)
    except (OSError, json.JSONDecodeError):
        token = None
    if not token:
        raise GitBucketError(
            f"GitBucket のトークンがありません。{CRED_PATH} に \"{origin}\" のキーで保存してください"
            "（scripts/gitbucket-mcp/install.sh で設定できます）"
        )
    return token


def _request(url: str, method: str = "GET", data: dict | None = None) -> urllib.request.Request:
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"token {resolve_token()}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    return req


def call_api(method: str, endpoint: str, data: dict | None = None) -> dict | list:
    """GitBucket の REST API（/api/v3 以下）を呼び、応答の JSON を返す。本文が空なら {}。"""
    req = _request(f"{GITBUCKET_URL}/api/v3{endpoint}", method, data)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise GitBucketError(
                "トークンが無効です。GitBucketのAccount Settings → Applicationsでトークンを確認してください"
            )
        if e.code == 404:
            raise NotFoundError(
                f"リポジトリまたはリソースが見つかりません: {endpoint}"
                "（オーナー名・リポジトリ名・番号を確認。PR の head に user:branch と書くと 404 になる）"
            )
        raise GitBucketError(f"APIエラー ({e.code}): {e.reason}")
    except (urllib.error.URLError, TimeoutError) as e:
        raise GitBucketError(
            f"接続エラー: {getattr(e, 'reason', e)}。GitBucketサーバー ({GITBUCKET_URL}) に接続できません"
        )

    if not raw.strip():
        return {}
    try:
        parsed = json.loads(raw)
        # PR 作成（POST /pulls）は JSON を文字列として二重にエンコードして返すことがある
        if isinstance(parsed, str):
            parsed = json.loads(parsed)
    except ValueError:
        if method == "GET":
            raise GitBucketError(f"GitBucket の応答を JSON として読めませんでした: {endpoint}")
        raise GitBucketError(
            f"GitBucket の応答を読めませんでした（{method} {endpoint}）。書き込みは成立している可能性があるので、"
            "再実行せず GET で作成・変更済みか確かめてください"
        )
    # 不正なボディを送ると、GitBucket は 200 と空の {} を返して何も作らない
    if method in ("POST", "PATCH") and parsed == {}:
        raise GitBucketError(
            f"GitBucket が {method} {endpoint} に空の {{}} を返しました。作成されていない可能性があります。"
            "送った内容を確かめ、GET で実在を確認してください"
        )
    return parsed


def get_page(url: str) -> tuple[int, str]:
    """Web 画面を取得して (HTTP ステータス, 本文) を返す。サインイン画面などへ転送されたら 302、接続できなければ 0。"""
    req = _request(url)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            if resp.geturl() != url:
                return 302, f"Redirected to {resp.geturl()}"
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode() if e.fp else ""
    except (urllib.error.URLError, TimeoutError) as e:
        return 0, f"Connection Error: {getattr(e, 'reason', e)}"
