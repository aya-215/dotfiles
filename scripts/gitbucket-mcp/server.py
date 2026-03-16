#!/usr/bin/env python3
"""GitBucket MCP Server - GitBucket APIをClaudeから操作するMCPサーバー"""

import json
import os
import urllib.error
import urllib.request
from pathlib import Path

from mcp.server.fastmcp import FastMCP


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

mcp = FastMCP("GitBucket")


# ---------------------------------------------------------------------------
# API共通関数
# ---------------------------------------------------------------------------

def call_api(method: str, endpoint: str, data: dict | None = None) -> dict | list:
    """GitBucket APIを呼び出す共通関数"""
    url = f"{GITBUCKET_URL}/api/v3{endpoint}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"token {GITBUCKET_TOKEN}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise RuntimeError(
                "トークンが無効です。GitBucketのAccount Settings → Applicationsでトークンを確認してください"
            )
        if e.code == 404:
            raise RuntimeError(f"リポジトリまたはリソースが見つかりません: {endpoint}")
        raise RuntimeError(f"APIエラー ({e.code}): {e.reason}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"接続エラー: {e.reason}。GitBucketサーバー ({GITBUCKET_URL}) に接続できません")


# ---------------------------------------------------------------------------
# レスポンス整形関数（主要フィールドのみ）
# ---------------------------------------------------------------------------

def fmt_pr(pr: dict) -> dict:
    return {
        "number": pr.get("number"),
        "title": pr.get("title"),
        "state": pr.get("state"),
        "url": pr.get("html_url"),
        "author": pr.get("user", {}).get("login"),
        "body": pr.get("body"),
        "head": pr.get("head", {}).get("label"),
        "base": pr.get("base", {}).get("label"),
        "created_at": pr.get("created_at"),
        "updated_at": pr.get("updated_at"),
    }


def fmt_issue(issue: dict) -> dict:
    return {
        "number": issue.get("number"),
        "title": issue.get("title"),
        "state": issue.get("state"),
        "url": issue.get("html_url"),
        "author": issue.get("user", {}).get("login"),
        "body": issue.get("body"),
        "labels": [lb.get("name") for lb in issue.get("labels", [])],
        "created_at": issue.get("created_at"),
        "updated_at": issue.get("updated_at"),
    }


def fmt_comment(comment: dict) -> dict:
    return {
        "id": comment.get("id"),
        "author": comment.get("user", {}).get("login"),
        "body": comment.get("body"),
        "created_at": comment.get("created_at"),
    }


def fmt_branch(branch: dict) -> dict:
    return {
        "name": branch.get("name"),
        "sha": branch.get("commit", {}).get("sha"),
    }


def fmt_repo(repo: dict) -> dict:
    return {
        "full_name": repo.get("full_name"),
        "description": repo.get("description"),
        "url": repo.get("html_url"),
        "default_branch": repo.get("default_branch"),
        "private": repo.get("private"),
        "open_issues_count": repo.get("open_issues_count"),
    }


# ---------------------------------------------------------------------------
# ツール定義
# ---------------------------------------------------------------------------

@mcp.tool()
def gitbucket_list_prs(owner: str, repo: str, state: str = "open") -> str:
    """GitBucketのPull Request一覧を取得する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        state: PRの状態 (open / closed / all)
    """
    result = call_api("GET", f"/repos/{owner}/{repo}/pulls?state={state}")
    if not result:
        return f"{owner}/{repo} に {state} なPRはありません"
    prs = [fmt_pr(pr) for pr in result]
    return json.dumps(prs, ensure_ascii=False, indent=2)


@mcp.tool()
def gitbucket_get_pr(owner: str, repo: str, number: int) -> str:
    """GitBucketの特定のPull Requestの詳細を取得する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        number: PRの番号
    """
    pr = call_api("GET", f"/repos/{owner}/{repo}/pulls/{number}")
    return json.dumps(fmt_pr(pr), ensure_ascii=False, indent=2)


@mcp.tool()
def gitbucket_create_pr(
    owner: str,
    repo: str,
    title: str,
    head: str,
    base: str,
    body: str = "",
) -> str:
    """GitBucketにPull Requestを作成する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        title: PRのタイトル
        head: マージ元ブランチ名
        base: マージ先ブランチ名
        body: PRの説明文
    """
    data = {"title": title, "head": head, "base": base, "body": body}
    pr = call_api("POST", f"/repos/{owner}/{repo}/pulls", data)
    result = fmt_pr(pr)
    return f"PRを作成しました\n" + json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
def gitbucket_list_issues(owner: str, repo: str, state: str = "open") -> str:
    """GitBucketのIssue一覧を取得する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        state: Issueの状態 (open / closed / all)
    """
    result = call_api("GET", f"/repos/{owner}/{repo}/issues?state={state}")
    if not result:
        return f"{owner}/{repo} に {state} なIssueはありません"
    # PRもissuesエンドポイントに含まれるため除外
    issues = [fmt_issue(i) for i in result if "pull_request" not in i]
    if not issues:
        return f"{owner}/{repo} に {state} なIssueはありません"
    return json.dumps(issues, ensure_ascii=False, indent=2)


@mcp.tool()
def gitbucket_get_issue(owner: str, repo: str, number: int) -> str:
    """GitBucketの特定のIssueの詳細を取得する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        number: Issueの番号
    """
    issue = call_api("GET", f"/repos/{owner}/{repo}/issues/{number}")
    return json.dumps(fmt_issue(issue), ensure_ascii=False, indent=2)


@mcp.tool()
def gitbucket_create_issue(
    owner: str,
    repo: str,
    title: str,
    body: str = "",
) -> str:
    """GitBucketにIssueを作成する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        title: Issueのタイトル
        body: Issueの説明文
    """
    data = {"title": title, "body": body}
    issue = call_api("POST", f"/repos/{owner}/{repo}/issues", data)
    result = fmt_issue(issue)
    return f"Issueを作成しました\n" + json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
def gitbucket_add_comment(
    owner: str,
    repo: str,
    number: int,
    body: str,
    target_type: str = "issue",
) -> str:
    """GitBucketのIssueまたはPRにコメントを追加する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        number: IssueまたはPRの番号
        body: コメント本文
        target_type: コメント対象の種別 (issue / pr)
    """
    # IssueとPRのコメントエンドポイントは共通
    data = {"body": body}
    comment = call_api("POST", f"/repos/{owner}/{repo}/issues/{number}/comments", data)
    result = fmt_comment(comment)
    return f"コメントを追加しました\n" + json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
def gitbucket_list_branches(owner: str, repo: str) -> str:
    """GitBucketのブランチ一覧を取得する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
    """
    result = call_api("GET", f"/repos/{owner}/{repo}/branches")
    if not result:
        return f"{owner}/{repo} にブランチがありません"
    branches = [fmt_branch(b) for b in result]
    return json.dumps(branches, ensure_ascii=False, indent=2)


@mcp.tool()
def gitbucket_get_repo(owner: str, repo: str) -> str:
    """GitBucketのリポジトリ情報を取得する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
    """
    repo_data = call_api("GET", f"/repos/{owner}/{repo}")
    return json.dumps(fmt_repo(repo_data), ensure_ascii=False, indent=2)


# ---------------------------------------------------------------------------
# エントリーポイント
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run(transport="stdio")
