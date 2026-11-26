# Git 操作

## ツール選択

**必ず `git remote -v` でリモートURLを確認してからツールを選ぶこと。**

| リモートURL | 使うツール |
|---|---|
| `github.com` | `gh` コマンド（GitHub CLI） |
| 社内GitBucket URL | `mcp__gitbucket__*` ツール。`gitbucket_api.py`（ebase-infra:gitbucket-api）は Bash で直接実行しない。MCP に無い読み取りは `gitbucket_api_get`、無い書き込みはツールを足すか相談する |

## ワークフロー

- ブランチ: `main`（本番）/ `feat/*`（機能開発）/ `fix/*`（バグ修正）
- コミット後は必ず push する。複数の変更をまとめてコミットする場合は、すべてのコミットが終わった最後に push する
- force push は原則禁止

※ コミットメッセージのプレフィックスはリポジトリごとに異なるため、各プロジェクトの CLAUDE.md に従うこと。
