"""GitBucket REST API と Web 画面の呼び出し、トークンの解決、ツールに返すエラーの型。"""

import http.client
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
        creds = json.loads(CRED_PATH.read_text(encoding="utf-8"))
        token = creds.get(origin) if isinstance(creds, dict) else None
    except (OSError, ValueError):
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


def _error_message(e: urllib.error.HTTPError) -> str:
    try:
        return json.loads(e.read() or b"{}").get("message") or e.reason
    except (ValueError, AttributeError, OSError):
        return e.reason


NOT_FOUND_HINT = "（オーナー名・リポジトリ名・番号を確認。PR の head に user:branch と書くと 404 になる）"
RETRY_WARNING = "書き込みは成立している可能性があるので、再実行せず GET で作成・変更済みか確かめてください"


def call_api(method: str, endpoint: str, data: dict | None = None) -> dict | list:
    """GitBucket の REST API（/api/v3 以下）を呼び、応答の JSON を返す。DELETE の空の本文は {}。"""
    try:
        req = _request(f"{GITBUCKET_URL}/api/v3{endpoint}", method, data)
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise GitBucketError(
                "認証で拒否されました（401）。トークンが無効か、このリポジトリへの権限がありません。"
                "GitBucket の Account Settings → Applications でトークンを確認してください"
            )
        if e.code == 404:
            raise NotFoundError(f"リポジトリまたはリソースが見つかりません: {endpoint}{NOT_FOUND_HINT}")
        raise GitBucketError(f"APIエラー ({e.code}): {_error_message(e)}")
    except GitBucketError:
        raise
    except (http.client.InvalidURL, ValueError) as e:
        # URL に空白・制御文字・非 ASCII が入ると、送る前に http.client が落とす
        raise GitBucketError(f"URL を組み立てられませんでした（{endpoint}）: {e}")
    except (urllib.error.URLError, OSError, http.client.HTTPException) as e:
        reason = getattr(e, "reason", e)
        if method != "GET":
            raise GitBucketError(f"GitBucket との通信が途中で切れました（{method} {endpoint}: {reason}）。{RETRY_WARNING}")
        raise GitBucketError(f"接続エラー: {reason}。GitBucketサーバー ({GITBUCKET_URL}) に接続できません")

    if not raw.strip():
        # GitBucket は存在しない PR の GET /pulls/N などに 404 ではなく 200 と空の本文を返す
        if method == "GET":
            raise NotFoundError(f"リポジトリまたはリソースが見つかりません: {endpoint}{NOT_FOUND_HINT}")
        if method == "DELETE":
            return {}
        raise GitBucketError(
            f"GitBucket が {method} {endpoint} に空の本文を返しました。作成・変更されていない可能性があります。"
            "対象の番号や送った内容を確かめ、GET で実在を確認してください"
        )
    try:
        parsed = json.loads(raw)
        # PR 作成（POST /pulls）は JSON を文字列として二重にエンコードして返すことがある
        if isinstance(parsed, str):
            parsed = json.loads(parsed)
    except ValueError:
        if method == "GET":
            raise GitBucketError(f"GitBucket の応答を JSON として読めませんでした: {endpoint}")
        raise GitBucketError(f"GitBucket の応答を読めませんでした（{method} {endpoint}）。{RETRY_WARNING}")
    # 不正なボディを送ると、GitBucket は 200 と空の {} を返して何も作らない
    if method in ("POST", "PATCH", "PUT") and parsed == {}:
        raise GitBucketError(
            f"GitBucket が {method} {endpoint} に空の {{}} を返しました。作成・変更されていない可能性があります。"
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
