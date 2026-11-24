# gitbucket-mcp 一本化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitBucket の操作を自作の gitbucket-mcp だけで済むようにし、ebase-infra:gitbucket-api スキル（`gitbucket_api.py`）を直接使わなくする。

**Architecture:** `scripts/gitbucket-mcp/` を「HTTP とトークン（`gitbucket_client.py`）」「PR 画面からインラインコメントを読む（`inline_comments.py`）」「MCP のツール定義（`server.py`）」の3ファイルに分ける。書き込みは操作ごとの専用ツールに限り、`settings.json` の `ask` で必ず確認を出す。mcp を v2 に上げる。

**Tech Stack:** Python 3.11+、mcp 2.x（`MCPServer`）、標準ライブラリの urllib と html.parser、unittest、uv

**Spec:** agent-memory `work-in-progress/gitbucket-mcp-consolidation.md`（2026-11-24 にユーザーと合意した改修13項目）

## Global Constraints

- 依存は `mcp[cli]>=2,<3` だけ。HTTP は urllib のまま（mcp v2 は httpx を入れない）。
- GitBucket は 4.47.0。既定の URL は `http://192.168.208.80:8080/gitbucket`（環境変数 `GITBUCKET_URL` で上書き）。
- トークンの解決順: 環境変数 `GITBUCKET_TOKEN` → `~/.claude/gitbucket/credentials.json` の `"<scheme>://<host>:<port>"` キー（例 `"http://192.168.208.80:8080"`）。ファイルは ebase-infra スキルと同じ形式で、権限は 600。
- ツール名は `gitbucket_` で始める。ツールの説明・エラー文は日本語。
- ツールはすべて `@mcp.tool(structured_output=False)`。v1 から、`str` の返り値が `content` と `structuredContent` に二重に入っていたため。
- ツール内のエラーは `ToolError` の派生（`GitBucketError`）で投げる。v2 は `RuntimeError` の文を隠し、`Error executing tool <名前>` しか返さない（2026-11-24 に実測）。
- 書き込みツールは `settings.json` の `permissions.ask` に必ず載せる。
- コードコメントは非自明な WHY だけを1行で（`.claude-global/rules/code-comments.md`）。
- コミットは `feat:` / `fix:` / `chore:` / `docs:`。最後に push する。
- 本物の GitBucket への書き込み（リポジトリ作成・PR 作成・コメント・マージ・ブランチ削除）は、テスト用リポジトリ `mori.a/gitbucket-mcp-test` の中だけで行う（2026-11-24 ユーザー許可）。他のリポジトリには書き込まない。

## Review Focus

1. トークンがどこにも無い → サーバは起動し、ツールを呼んだときに「`~/.claude/gitbucket/credentials.json` に設定が無い」と分かるエラーを返す（Task 2 のテスト `test_トークンが無いと設定場所を示すエラー`）。
2. `gitbucket_list_comments` に Issue の番号を渡す → インラインは空のリストで、エラーにしない（Task 3 のテスト `test_Issueの番号ならインラインは空`）。
3. 非公開リポジトリやサインイン画面への転送でインラインが読めない → `inline_comments` は `null` で理由を付け、「0件」と区別する（Task 3 のテスト `test_画面が開けないときはnullと理由`）。
4. DELETE が 204 で本文が空 → 成功として扱い、JSON の解析エラーにしない（Task 2 のテスト `test_空の本文は空の辞書`）。
5. 既定ブランチの削除を頼まれる → API を呼ぶ前に断る（Task 4 のテスト `test_既定ブランチは消さない`）。

---

## File Structure

| ファイル | 役割 |
|---|---|
| `scripts/gitbucket-mcp/gitbucket_client.py`（新規） | URL・トークンの解決、`call_api`、`get_page`、`GitBucketError` |
| `scripts/gitbucket-mcp/inline_comments.py`（新規） | PR 画面の HTML からインラインコメントを取り出す（ebase-infra の `InlineCommentParser` を移植） |
| `scripts/gitbucket-mcp/server.py` | MCP のツール定義と整形だけ |
| `scripts/gitbucket-mcp/test_client.py` / `test_inline_comments.py` / `test_server.py` | それぞれのテスト |
| `scripts/gitbucket-mcp/smoke.sh`（新規） | stdio で initialize → tools/list を送り、ツール名を1行ずつ出す |
| `.claude-global/settings.json` | `ask` に書き込みツールを足す |
| `.claude-global/CLAUDE.md` / `.claude-global/rules/external-actions.md` | GitBucket は MCP で、の一文と書き込みツールの一覧 |

テストの実行: `uv --directory ~/.dotfiles/scripts/gitbucket-mcp run python -m unittest`

---

### Task 1: mcp v2 に移行し、エラー文が届くようにする

**Files:**
- Modify: `scripts/gitbucket-mcp/pyproject.toml`（`mcp[cli]<2` → `mcp[cli]>=2,<3`）、`uv.lock`
- Create: `scripts/gitbucket-mcp/gitbucket_client.py`（この Task では `GitBucketError` と、server.py から移した `call_api`・`GITBUCKET_URL` だけ）
- Modify: `scripts/gitbucket-mcp/server.py`
- Create: `scripts/gitbucket-mcp/smoke.sh`
- Test: `scripts/gitbucket-mcp/test_server.py`

**Interfaces:**
- Produces: `class GitBucketError(ToolError)`（`from mcp.server.mcpserver.exceptions import ToolError`）、`call_api(method: str, endpoint: str, data: dict | None = None) -> dict | list`、`GITBUCKET_URL: str`。server.py は `from gitbucket_client import GitBucketError, call_api, GITBUCKET_URL` で使う。テストは今までどおり `server.call_api` をモックする。

- [ ] **Step 1: 失敗するテストを書く**（`test_server.py` に追加）

```python
class ErrorTypeTest(unittest.TestCase):
    def test_更新が反映されないとGitBucketErrorを投げる(self):
        with mock.patch.object(server, "call_api", return_value=_pr(body="old")):
            with self.assertRaises(server.GitBucketError):
                server.gitbucket_update_pr("o", "r", 2, body="new")
```

- [ ] **Step 2:** `uv --directory scripts/gitbucket-mcp run python -m unittest` を実行し、`AttributeError: ... GitBucketError` で落ちることを確かめる
- [ ] **Step 3:** pyproject を `mcp[cli]>=2,<3` にして `uv lock --upgrade-package mcp` → `uv sync`。`from mcp.server.mcpserver import MCPServer` に替え、`mcp = MCPServer("GitBucket", version="0.2.0")`、`mcp.run(transport="stdio")`。全ツールを `@mcp.tool(structured_output=False)` にする。`call_api` と `GitBucketError` を `gitbucket_client.py` へ移し、server.py の `raise RuntimeError(...)` をすべて `GitBucketError` にする
- [ ] **Step 4:** テストを実行して全件 PASS（既存の5件を含む）
- [ ] **Step 5:** `smoke.sh` を作る。`(printf initialize・initialized・tools/list; sleep 4) | timeout 30 uv run server.py` の結果から `jq -r '.result.tools[].name'` でツール名を出す（stdin をすぐ閉じると v1 では返事の前に終わったため `sleep` を入れる）。`bash smoke.sh | wc -l` が `11`
- [ ] **Step 6:** コミット `feat: gitbucket-mcp を mcp v2 に移行し、エラーの理由がクライアントに届くようにする`

### Task 2: トークンの置き場所を1つにし、HTTP を堅くする

**Files:**
- Modify: `scripts/gitbucket-mcp/gitbucket_client.py`、`server.py`（`load_env` と `.env.local` の読み込みを消す）、`install.sh`
- Delete: `scripts/gitbucket-mcp/.env.local.example`（追跡されている見本）
- Test: `scripts/gitbucket-mcp/test_client.py`

**Interfaces:**
- Consumes: Task 1 の `GitBucketError`、`call_api`
- Produces: `CRED_PATH: Path`、`resolve_token() -> str`（無ければ `GitBucketError`）、`get_page(url: str) -> tuple[int, str]`（転送されたら `(302, ...)`、接続失敗は `(0, 理由)`）。`call_api` のシグネチャは変えない。

- [ ] **Step 1: 失敗するテストを書く**（`test_client.py`。`CRED_PATH` は一時ファイルに、`urlopen` はモックに差し替える）
  - `test_環境変数のトークンが優先される`: env と credentials の両方があるとき env を使う
  - `test_credentialsからoriginのトークンを読む`: `{"http://192.168.208.80:8080": "t1"}` から `t1`
  - `test_トークンが無いと設定場所を示すエラー`: どちらも無い → `GitBucketError`、文に `credentials.json` を含む
  - `test_urlopenにtimeoutを渡す`: `urlopen` が `timeout=30` で呼ばれる
  - `test_空の本文は空の辞書`: 204・本文 `b""` → `{}`
  - `test_作成系で空の辞書が返ると静かな失敗としてエラー`: `POST` で `b"{}"` → `GitBucketError`、文に「作成されていない可能性」を含む
  - `test_書き込みの応答を読めないときは再実行しないよう伝える`: `POST` で `b"<html>"` → `GitBucketError`、文に「再実行せず」を含む
  - `test_PR作成の二重エンコードを戻す`: `b'"{\\"number\\": 3}"'` → `{"number": 3}`（今ある挙動を残す）
- [ ] **Step 2:** テストを実行して FAIL を確かめる
- [ ] **Step 3:** `gitbucket_client.py` を実装する。トークンはサーバ起動時ではなく `call_api` / `get_page` を呼んだときに解決する（Review Focus 1）。`urlopen(req, timeout=30)`。静かな失敗の判定は `POST` と `PATCH` で応答が `{}` のときだけ（DELETE は 204、マージの PUT は中身を返すため対象外）。404 の文には「オーナー名・リポジトリ名・番号を確認。PR の head に `user:branch` と書くと 404 になる」を足す
- [ ] **Step 4:** テストを実行して全件 PASS
- [ ] **Step 5:** `install.sh` を、トークンを `.env.local` ではなく `CRED_PATH` に（権限 600、既存のキーを残して）書く形に替える。トークンは `read -rs` で受け取り、引数に載せない
- [ ] **Step 6:** 本物の GitBucket で読み取りだけ確かめる: `uv run python -c "import gitbucket_client as c; print(c.call_api('GET','/user')['login'])"` が `mori.a`
- [ ] **Step 7:** コミット `feat: gitbucket-mcp のトークンを credentials.json に寄せ、timeout と静かな失敗の検出を足す`
- [ ] **Step 8: ユーザーに確認を取ってから** `scripts/gitbucket-mcp/.env.local`（トークンの古い置き場所。gitignore 済み）を消す。消す前に Step 6 が通っていること

### Task 3: コメント一覧にインラインコメントを含める

**Files:**
- Create: `scripts/gitbucket-mcp/inline_comments.py`
- Modify: `scripts/gitbucket-mcp/server.py`（`gitbucket_list_comments`）
- Test: `scripts/gitbucket-mcp/test_inline_comments.py`、`test_server.py`

**Interfaces:**
- Consumes: Task 2 の `get_page`、`call_api`
- Produces: `parse_inline_comments(html: str) -> list[dict]`。各要素は `{"id": int, "path": str, "line": int | None, "side": "new" | "old" | None, "user": str | None, "created_at": str | None, "body": str}`。`gitbucket_list_comments(owner, repo, number) -> str` は JSON `{"comments": [...], "inline_comments": [...] | null, "inline_error": str | null}` を返す。

- [ ] **Step 1: 失敗するテストを書く**
  - `test_inline_comments.py`: ebase-infra の `test_gitbucket_api.py` から、HTML を入れて結果を見る3件（`test_インラインコメントだけを位置と本文付きで取り出す` / `test_インラインコメントが無い画面では空のリストになる` / `test_同じ行への返信は投稿者と時刻ごとに別の1件になる`）を入力 HTML ごと移す。元: `~/.claude/plugins/cache/ebase-claude-marketplace/ebase-infra/1.3.4/skills/gitbucket-api/scripts/test_gitbucket_api.py`
  - `test_server.py`:
    - `test_PRなら通常とインラインの両方を返す`
    - `test_Issueの番号ならインラインは空`: `GET /pulls/{n}` が 404 → `inline_comments == []`、`inline_error is None`
    - `test_画面が開けないときはnullと理由`: `get_page` が `(401, "")` または `(302, ...)` → `inline_comments is None`、`inline_error` に「0件ではない」と「ブラウザ」を含む
- [ ] **Step 2:** テストを実行して FAIL を確かめる
- [ ] **Step 3:** `inline_comments.py` に ebase-infra の `InlineCommentParser` と `parse_inline_comments` を移す（作り直さない。元: 同じディレクトリの `gitbucket_api.py` の `InlineCommentParser`）。`gitbucket_list_comments` は、先に `GET /repos/{o}/{r}/pulls/{n}` で PR かどうかを見る（404 なら Issue）。PR 画面の URL は `f"{GITBUCKET_URL}/{owner}/{repo}/pull/{number}"`。ツールの説明に「インラインへの返信 API は無い。返信は通常コメントで `path:line` を書いて示す」を書く
- [ ] **Step 4:** テストを実行して全件 PASS
- [ ] **Step 5:** 本物の GitBucket で読み取りだけ確かめる: インラインコメントのある PR を1件、ユーザーに教えてもらって `gitbucket_list_comments` を呼び、PR 画面の指摘の数と `inline_comments` の件数が合うことを見せる
- [ ] **Step 6:** コミット `feat: gitbucket_list_comments が PR のインラインコメントも返すようにする`

### Task 4: スクリプトでしかできなかった操作をツールにする

**Files:**
- Modify: `scripts/gitbucket-mcp/server.py`
- Test: `scripts/gitbucket-mcp/test_server.py`

**Interfaces:**
- Consumes: Task 2 の `call_api`
- Produces（すべて `-> str` で JSON 文字列を返す）:
  - `gitbucket_merge_pr(owner: str, repo: str, number: int, commit_message: str | None = None)` → `PUT /repos/{o}/{r}/pulls/{n}/merge`（`commit_message` があるときだけボディに入れる）
  - `gitbucket_delete_branch(owner: str, repo: str, branch: str)` → `DELETE /repos/{o}/{r}/git/refs/heads/{branch}`（ブランチ名は `urllib.parse.quote(branch, safe="")`）
  - `gitbucket_get_user()` → `GET /user` を `{"login", "name", "site_admin"}` に整形
  - `gitbucket_list_user_orgs(user: str | None = None)` → `user` が無ければ `GET /user/orgs`、あれば `GET /users/{user}/orgs`。`login` の一覧を返す
  - `gitbucket_api_get(path: str)` → 読み取り専用の汎用 GET。応答の JSON をそのまま返す

- [ ] **Step 1: 失敗するテストを書く**
  - `test_マージはPUTで既定のメッセージに任せる`: `commit_message` 無し → `("PUT", "/repos/o/r/pulls/2/merge", None)`
  - `test_マージにメッセージを渡せる`
  - `test_既定ブランチは消さない`: `GET /repos/o/r` が `default_branch: "main"` → `branch="main"` で `GitBucketError`、DELETE を呼ばない
  - `test_日本語のブランチ名をURLエンコードして消す`: `branch="【No00000005】x"` → エンドポイントがエンコード済み
  - `test_汎用GETはhttpやドット2つのパスを断る`: `"http://x"`、`"../admin"`、`"repos/o/r"`（`/` で始まらない）→ `GitBucketError`
  - `test_ユーザー指定の有無で組織一覧のエンドポイントが変わる`
- [ ] **Step 2:** テストを実行して FAIL を確かめる
- [ ] **Step 3:** 5つのツールを実装する。既存の `gitbucket_create_pr` と `gitbucket_create_issue` の説明に、ebase-infra スキルにしか無かった癖を足す:
  - create_pr: 「本文に `closes #12` と書くと、既定ブランチへマージしたときに Issue #12 が閉じる（Issue を閉じる API は無い）。head は同じリポジトリならブランチ名だけ」
  - create_issue: 「作成後に本文・タイトルを API で直せない。相互参照する Issue は本文に番号を書かず、全部作ってからコメントでつなぐ」
  - 書き込み系の説明: 「応答を読めなかったときは再実行せず、GET で作成・変更済みか確かめる」
- [ ] **Step 4:** テストを実行して全件 PASS。`bash smoke.sh | wc -l` が `16`
- [ ] **Step 5:** 本物の GitBucket で読み取りだけ確かめる: `gitbucket_get_user`（`mori.a`）、`gitbucket_list_user_orgs`、`gitbucket_api_get("/repos/AI_dev/tamaki-ai-training/collaborators")`
- [ ] **Step 6:** コミット `feat: gitbucket-mcp に PR マージ・ブランチ削除・ユーザーと組織・読み取り専用の汎用 GET を足す`

### Task 5: 設定と指示を MCP 一本に揃える

**Files:**
- Modify: `.claude-global/settings.json`（`permissions.ask` に `mcp__gitbucket__gitbucket_merge_pr` と `mcp__gitbucket__gitbucket_delete_branch`）
- Modify: `.claude-global/CLAUDE.md`（「Git操作のツール選択」の GitBucket 行）
- Modify: `.claude-global/rules/external-actions.md`（外部アクションの例に PR マージ・ブランチ削除）
- Modify: `.claude-global/skills/update-all/SKILL.md`（python 行の `<2` 固定と「11個」を、v2 と「16個」に。MCP のテストを `bash scripts/gitbucket-mcp/smoke.sh | wc -l` に）
- Modify: `.claude-global/skills/review-pr/SKILL.md`、`write-review-comment/SKILL.md`、`review-training-submission/SKILL.md`（`gitbucket_list_comments` の戻りが `{"comments", "inline_comments", "inline_error"}` になったこと。指摘を数えるときは両方を足す、`inline_comments` が `null` なら読めていない）

- [ ] **Step 1:** CLAUDE.md の GitBucket 行を次にする: 「社内GitBucket URL | `mcp__gitbucket__*` ツール。`gitbucket_api.py`（ebase-infra:gitbucket-api）は Bash で直接実行しない。MCP に無い読み取りは `gitbucket_api_get`、無い書き込みはツールを足すか相談する」
- [ ] **Step 2:** settings.json・external-actions.md・3つのスキル・update-all を書き換え、`jq empty .claude-global/settings.json` が通ることを確かめる
- [ ] **Step 3:** 新しい Claude を無人で1回立ち上げ、`claude -p "GitBucket の AI_dev/tamaki-ai-training の open な PR を一覧して"` が `mcp__gitbucket__gitbucket_list_prs` を使い、`gitbucket_api.py` を実行しないことを確かめる
- [ ] **Step 4:** コミット `docs: GitBucket の操作を gitbucket-mcp に揃え、マージとブランチ削除に確認を出す` → push
- [ ] **Step 5:** agent-memory の `work-in-progress/gitbucket-mcp-consolidation.md` を完了に更新し、Claude Code の再起動（MCP の読み直し）をユーザーに頼む
