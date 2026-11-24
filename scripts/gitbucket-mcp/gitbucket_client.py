"""GitBucket REST API の呼び出しと、ツールに返すエラーの型。"""

import json
import os
import urllib.error
import urllib.request
from pathlib import Path

from mcp.server.mcpserver.exceptions import ToolError


class GitBucketError(ToolError):
    """ツールの失敗としてクライアントに理由を返すエラー。"""


def load_env() -> None:
    """スクリプトと同じディレクトリの .env.local を読み込む"""
    env_file = Path(__file__).parent / ".env.local"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


load_env()

GITBUCKET_URL = os.environ.get("GITBUCKET_URL", "http://192.168.208.80:8080/gitbucket")
GITBUCKET_TOKEN = os.environ.get("GITBUCKET_TOKEN", "")


def call_api(method: str, endpoint: str, data: dict | None = None) -> dict | list:
    """GitBucket APIを呼び出す共通関数"""
    url = f"{GITBUCKET_URL}/api/v3{endpoint}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"token {GITBUCKET_TOKEN}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            parsed = json.loads(resp.read())
            # GitBucketのPR作成(POST /pulls)は、JSON文字列を二重にエンコードして
            # 返すことがある（結果がdict/listでなくstrになる）。その場合はもう一度
            # パースして本来のオブジェクトに戻す。
            if isinstance(parsed, str):
                parsed = json.loads(parsed)
            return parsed
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise GitBucketError(
                "トークンが無効です。GitBucketのAccount Settings → Applicationsでトークンを確認してください"
            )
        if e.code == 404:
            raise GitBucketError(f"リポジトリまたはリソースが見つかりません: {endpoint}")
        raise GitBucketError(f"APIエラー ({e.code}): {e.reason}")
    except urllib.error.URLError as e:
        raise GitBucketError(f"接続エラー: {e.reason}。GitBucketサーバー ({GITBUCKET_URL}) に接続できません")
