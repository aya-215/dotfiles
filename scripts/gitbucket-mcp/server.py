#!/usr/bin/env python3
"""GitBucket MCP Server - GitBucket APIをClaudeから操作するMCPサーバー"""

import json

from mcp.server.mcpserver import MCPServer

from gitbucket_client import GITBUCKET_URL, GitBucketError, NotFoundError, call_api, get_page
from inline_comments import parse_inline_comments

mcp = MCPServer("GitBucket", version="0.2.0")


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

@mcp.tool(structured_output=False)
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


@mcp.tool(structured_output=False)
def gitbucket_get_pr(owner: str, repo: str, number: int) -> str:
    """GitBucketの特定のPull Requestの詳細を取得する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        number: PRの番号
    """
    pr = call_api("GET", f"/repos/{owner}/{repo}/pulls/{number}")
    return json.dumps(fmt_pr(pr), ensure_ascii=False, indent=2)


@mcp.tool(structured_output=False)
def gitbucket_update_pr(
    owner: str,
    repo: str,
    number: int,
    title: str | None = None,
    body: str | None = None,
    state: str | None = None,
) -> str:
    """GitBucketの既存Pull Requestを更新する

    title / body / state のうち、指定された項目だけを更新する。

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        number: PRの番号
        title: 新しいタイトル（変更する場合のみ指定）
        body: 新しい説明文（変更する場合のみ指定）
        state: 新しい状態 open / closed（変更する場合のみ指定）
    """
    data = {
        k: v
        for k, v in {"title": title, "body": body, "state": state}.items()
        if v is not None
    }
    if not data:
        return "更新する項目が指定されていません（title / body / state のいずれかを指定してください）"
    # GitBucket は title を送ったときだけ title と body をまとめて書き込む（updatePullRequestsByApi が title.foreach の中で updateIssue する）。片方だけだと body が無視されるか空になる
    if ("title" in data) != ("body" in data):
        current = call_api("GET", f"/repos/{owner}/{repo}/pulls/{number}")
        data = {"title": current.get("title"), "body": current.get("body") or "", **data}
    pr = call_api("PATCH", f"/repos/{owner}/{repo}/pulls/{number}", data)
    # GitBucket は PATCH で body を受け取っても 200 で無視し、旧本文を返すことがある
    def norm(k: str, s: str | None) -> str:
        s = (s or "").replace("\r\n", "\n").strip()
        return s.lower() if k == "state" else s

    ignored = [k for k, v in data.items() if norm(k, pr.get(k)) != norm(k, v)] if isinstance(pr, dict) else list(data)
    if ignored:
        raise GitBucketError(
            f"GitBucket が {', '.join(ignored)} の変更を反映しませんでした。"
            "PR 本文は Web 画面（本文枠右上の鉛筆アイコン）で編集してください"
        )
    return "PRを更新しました\n" + json.dumps(fmt_pr(pr), ensure_ascii=False, indent=2)


@mcp.tool(structured_output=False)
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


@mcp.tool(structured_output=False)
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


@mcp.tool(structured_output=False)
def gitbucket_get_issue(owner: str, repo: str, number: int) -> str:
    """GitBucketの特定のIssueの詳細を取得する

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        number: Issueの番号
    """
    issue = call_api("GET", f"/repos/{owner}/{repo}/issues/{number}")
    return json.dumps(fmt_issue(issue), ensure_ascii=False, indent=2)


@mcp.tool(structured_output=False)
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


@mcp.tool(structured_output=False)
def gitbucket_list_comments(owner: str, repo: str, number: int) -> str:
    """GitBucketのIssueまたはPRのコメント一覧を取得する。PRならインラインのコードコメントも含める

    戻り値は {"comments": 通常コメント, "inline_comments": インラインコメント, "inline_error": 理由} の JSON。
    指摘の件数は comments と inline_comments を足して数える。
    inline_comments が null のときはインラインを読めていない（0件ではない）。inline_error に理由がある。
    インラインコメントへ返信する API は無い。返信は gitbucket_add_comment で、本文に path:line を書いて示す。

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        number: IssueまたはPRの番号
    """
    comments = [fmt_comment(c) for c in call_api("GET", f"/repos/{owner}/{repo}/issues/{number}/comments") or []]
    inline, inline_error = fetch_inline_comments(owner, repo, number)
    return json.dumps(
        {"comments": comments, "inline_comments": inline, "inline_error": inline_error},
        ensure_ascii=False,
        indent=2,
    )


def fetch_inline_comments(owner: str, repo: str, number: int) -> tuple[list[dict] | None, str | None]:
    """PR 画面からインラインコメントを読む。Issue なら ([], None)、読めなければ (None, 理由)。"""
    try:
        call_api("GET", f"/repos/{owner}/{repo}/pulls/{number}")
    except NotFoundError:
        return [], None
    status, html = get_page(f"{GITBUCKET_URL}/{owner}/{repo}/pull/{number}")
    if status == 200:
        return parse_inline_comments(html), None
    # 非公開リポジトリの画面はトークンでは開けない（token・Basic・Bearer すべて 401）
    return None, (
        f"PR 画面を開けなかったため、インラインコメントを読めていません（0件ではない。HTTP {status}）。"
        "ログイン済みのブラウザで PR 画面を開いて確認してください"
    )


@mcp.tool(structured_output=False)
def gitbucket_add_comment(
    owner: str,
    repo: str,
    number: int,
    body: str,
) -> str:
    """GitBucketのIssueまたはPRにコメントを追加する

    IssueとPRはコメントエンドポイントが共通なので、PRの番号を渡してもよい。

    Args:
        owner: リポジトリのオーナー名
        repo: リポジトリ名
        number: IssueまたはPRの番号
        body: コメント本文
    """
    data = {"body": body}
    comment = call_api("POST", f"/repos/{owner}/{repo}/issues/{number}/comments", data)
    result = fmt_comment(comment)
    return f"コメントを追加しました\n" + json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool(structured_output=False)
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


@mcp.tool(structured_output=False)
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
