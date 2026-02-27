# lazygit.nvim

Neovim のフローティングウィンドウから lazygit を直接呼び出すプラグイン。

設定ファイル: `config/nvim/lua/plugins/lazygit.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<leader>gg` | LazyGit を起動 |
| `<leader>gf` | 現在ファイルのプロジェクトルートで LazyGit を起動 |
| `:LazyGit` | 現在の作業ディレクトリで起動 |
| `:LazyGitCurrentFile` | 現在ファイルのプロジェクトルートで起動 |
| `:LazyGitConfig` | lazygit 設定ファイルを編集 |
| `:LazyGitFilter` | プロジェクト全体のコミット一覧を表示 |
| `:LazyGitFilterCurrentFile` | 現在バッファのコミット一覧を表示 |

---

## 詳細

### キーマップ

- `<leader>gg` — LazyGit を起動（`:LazyGit`）
- `<leader>gf` — 現在ファイルのプロジェクトルートで起動（`:LazyGitCurrentFile`）

### コマンド

- `:LazyGit` — 現在の作業ディレクトリで lazygit を起動
- `:LazyGitCurrentFile` — 現在開いているファイルのプロジェクトルートで起動
- `:LazyGitConfig` — lazygit の設定ファイルを直接編集
- `:LazyGitFilter` — プロジェクト全体のコミットをフィルタ表示
- `:LazyGitFilterCurrentFile` — 現在バッファに関連するコミットのみ表示

---

## 注意事項

- nvim v0.7.2 以上が必要
- コミットエディタ機能を使う場合は `neovim-remote` のインストールを推奨
