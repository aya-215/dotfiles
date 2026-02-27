# Neovim キーマップ一覧

Leader キー: `Space` / Local Leader: `\`

## グループ概要

| プレフィックス | グループ名 | 定義元 |
|---|---|---|
| `<leader>a` | AI/Claude | claudecode.lua |
| `<leader>b` | バッファ | barbar.lua, neo-tree.lua |
| `<leader>c` | コード | conform.lua, mason.lua |
| `<leader>e` | ファイルエクスプローラー | oil.lua |
| `<leader>E` | Neo-tree | neo-tree.lua |
| `<leader>f` | ファイル | telescope.lua |
| `<leader>g` | Git | telescope.lua, lazygit.lua, neo-tree.lua, diffview.lua, octo.lua |
| `<leader>h` | Git hunk | gitsigns.lua（バッファローカル） |
| `<leader>l` | LSP | telescope.lua |
| `<leader>q` | セッション | persistence.lua |
| `<leader>r` | Markdown | markdown.lua |
| `<leader>s` | 検索 | telescope.lua |
| `<leader>u` | UIトグル | keymaps.lua, vim-auto-save.lua |
| `<leader>w` | ウィンドウ | which-key.lua（`<C-w>` にプロキシ） |
| `<leader>x` | 診断/Quickfix | telescope.lua, keymaps.lua |
| `<leader>?` | which-key | which-key.lua |

---

## AI/Claude (`<leader>a`)

定義元: `plugins/claudecode.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>ac` | n | `ClaudeCode` | Claudeの表示切替 |
| `<leader>af` | n | `ClaudeCodeFocus` | Claudeにフォーカス |
| `<leader>ar` | n | `ClaudeCode --resume` | セッション再開 |
| `<leader>aC` | n | `ClaudeCode --continue` | セッション続行 |
| `<leader>am` | n | `ClaudeCodeSelectModel` | モデル選択 |
| `<leader>ab` | n | `ClaudeCodeAdd %` | 現在のバッファを追加 |
| `<leader>as` | v | `ClaudeCodeSend` | 選択範囲をClaudeに送信 |
| `<leader>as` | n (tree系) | `ClaudeCodeTreeAdd` | ファイルを追加 |
| `<leader>aa` | n | `ClaudeCodeDiffAccept` | Diffを承認 |
| `<leader>ad` | n | `ClaudeCodeDiffDeny` | Diffを拒否 |

---

## バッファ (`<leader>b`)

定義元: `plugins/barbar.lua`, `plugins/neo-tree.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>bb` | n | `BufferOrderByBufferNumber` | バッファ番号順に並替 |
| `<leader>bd` | n | `BufferOrderByDirectory` | ディレクトリ順に並替 |
| `<leader>bl` | n | `BufferOrderByLanguage` | 言語順に並替 |
| `<leader>bw` | n | `BufferOrderByWindowNumber` | ウィンドウ番号順に並替 |
| `<leader>be` | n | `Neotree buffers` | バッファエクスプローラー |

---

## コード (`<leader>c`)

定義元: `plugins/conform.lua`, `plugins/mason.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>cf` | n, v | `conform.format(...)` | バッファをフォーマット |
| `<leader>cm` | n | `Mason` | Mason（LSPインストーラー）を開く |

---

## ファイルエクスプローラー (`<leader>e` / `<leader>E`)

| キー | モード | アクション | 説明 | 定義元 |
|------|--------|-----------|------|--------|
| `<leader>e` | n | `Oil` | Oilファイルエクスプローラーを開く | `plugins/oil.lua` |
| `<leader>E` | n | `Neotree toggle` | Neo-treeの表示切替 | `plugins/neo-tree.lua` |

---

## ファイル (`<leader>f`)

定義元: `plugins/telescope.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>ff` | n | `Telescope find_files` | ファイル検索 |
| `<leader>fb` | n | `Telescope buffers` | バッファ一覧 |
| `<leader>fr` | n | `Telescope oldfiles` | 最近使用したファイル |

---

## Git (`<leader>g`)

定義元: `plugins/telescope.lua`, `plugins/lazygit.lua`, `plugins/neo-tree.lua`, `plugins/diffview.lua`, `plugins/octo.lua`

### 基本操作

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>gg` | n | `LazyGit` | LazyGitを起動 |
| `<leader>gf` | n | `LazyGitCurrentFile` | 現在のファイルでLazyGitを起動 |
| `<leader>ge` | n | `Neotree git_status` | Git変更ファイルをNeo-treeで表示 |

### Telescope連携

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>gc` | n | `Telescope git_commits` | コミット履歴を表示 |
| `<leader>gs` | n | `Telescope git_status` | 変更状態を表示 |
| `<leader>gb` | n | `Telescope git_branches` | ブランチ一覧を表示 |

### Diffview

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>gd` | n | `DiffviewOpen` | Diffviewを開く |
| `<leader>gD` | n | `DiffviewClose` | Diffviewを閉じる |
| `<leader>gm` | n | `DiffviewOpen (merge-base)` | マージベースとのdiffを表示 |
| `<leader>gh` | n | `DiffviewFileHistory %` | 現在のファイルの変更履歴 |
| `<leader>gH` | n | `DiffviewFileHistory` | 全ファイルの変更履歴 |

### Octo（GitHub連携）

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>gop` | n | `Octo pr list` | PR一覧 |
| `<leader>goi` | n | `Octo issue list` | Issue一覧 |
| `<leader>goc` | n | `Octo pr create` | PR作成 |
| `<leader>gor` | n | `Octo review start` | レビュー開始 |

---

## Git hunk (`<leader>h`)

定義元: `plugins/gitsigns.lua`（`on_attach`でバッファローカルに設定。Gitファイルを開いている時のみ有効）

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>hs` | n | `stage_hunk` | ハンクをステージ |
| `<leader>hr` | n | `reset_hunk` | ハンクをリセット |
| `<leader>hs` | v | `stage_hunk` (選択範囲) | 選択範囲をステージ |
| `<leader>hr` | v | `reset_hunk` (選択範囲) | 選択範囲をリセット |
| `<leader>hS` | n | `stage_buffer` | バッファ全体をステージ |
| `<leader>hR` | n | `reset_buffer` | バッファ全体をリセット |
| `<leader>hu` | n | `undo_stage_hunk` | ステージを取消 |
| `<leader>hp` | n | `preview_hunk_inline` | ハンクをインラインプレビュー |
| `<leader>hb` | n | `blame_line({ full = true })` | 行のblame情報を表示 |
| `<leader>hB` | n | `blame()` | バッファ全体のblame |
| `<leader>hd` | n | `diffthis` | 現在のファイルのdiff |
| `<leader>hD` | n | `diffthis("~")` | HEADの親とのdiff |

---

## LSP (`<leader>l`)

定義元: `plugins/telescope.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>lr` | n | `Telescope lsp_references` | シンボルの参照先一覧 |
| `<leader>ls` | n | `Telescope lsp_document_symbols` | ドキュメント内のシンボル一覧 |

---

## セッション (`<leader>q`)

定義元: `plugins/persistence.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>qs` | n | `persistence.load()` | セッションを復元 |
| `<leader>ql` | n | `persistence.load({ last = true })` | 最後のセッションを復元 |
| `<leader>qd` | n | `persistence.stop()` | 現在のセッションを保存しない |

---

## Markdown (`<leader>r`)

定義元: `plugins/markdown.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>rm` | n | `RenderMarkdown toggle` | Markdownレンダリングの切替 |
| `<leader>rp` | n | `RenderMarkdown preview` | Markdownプレビュー |

---

## 検索 (`<leader>s`)

定義元: `plugins/telescope.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>sg` | n | `Telescope live_grep` | 文字列検索 (Grep) |
| `<leader>sh` | n | `Telescope help_tags` | ヘルプタグ検索 |
| `<leader>sc` | n | `Telescope commands` | コマンド一覧 |
| `<leader>sk` | n | `Telescope keymaps` | キーマップ一覧 |
| `<leader>sw` | n | `Telescope grep_string` | カーソル下の単語を検索 |
| `<leader>sr` | n | `Telescope resume` | 前回の検索を再開 |

---

## UIトグル (`<leader>u`)

定義元: `config/keymaps.lua`, `plugins/vim-auto-save.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>ua` | n | `AutoSaveToggle` | 自動保存の切替 |
| `<leader>uw` | n | `:set wrap!` | 折り返し表示の切替 |
| `<leader>un` | n | `:set number!` | 行番号の切替 |
| `<leader>ur` | n | `:set relativenumber!` | 相対行番号の切替 |
| `<leader>us` | n | `:set spell!` | スペルチェックの切替 |
| `<leader>ul` | n | `:set list!` | 不可視文字の切替 |
| `<leader>uc` | n | `:set cursorline!` | カーソル行ハイライトの切替 |

---

## 診断/Quickfix (`<leader>x`)

定義元: `plugins/telescope.lua`, `config/keymaps.lua`

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>xd` | n | `Telescope diagnostics` | 全診断情報 |
| `<leader>xD` | n | `Telescope diagnostics bufnr=0` | バッファ内の診断 |
| `<leader>xq` | n | `:copen` | Quickfixリストを開く |
| `<leader>xl` | n | `:lopen` | Locationリストを開く |
| `<leader>xx` | n | `vim.diagnostic.setloclist` | 診断をLocationリストに送る |

---

## which-key (`<leader>?`)

| キー | モード | アクション | 説明 |
|------|--------|-----------|------|
| `<leader>?` | n | `which-key.show({ global = false })` | バッファローカルのキーマップ表示 |

---

## 備考

- `<leader>h` はgitsignsの`on_attach`で設定されるため、Git管理下のファイルを開いている時のみ有効
- which-keyのpresetは `helix` を使用
