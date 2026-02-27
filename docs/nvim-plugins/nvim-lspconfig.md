# nvim-lspconfig

Neovim の組み込み LSP クライアント向け言語サーバー設定集

設定ファイル: `config/nvim/lua/plugins/nvim-lspconfig.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `gd` | 定義へジャンプ |
| `gr` | 参照一覧 |
| `K` | ホバードキュメント表示 |
| `<leader>cr` | シンボルのリネーム |
| `<leader>ca` | コードアクション |
| `<leader>cl` | LSP 情報を表示 |
| `]]` / `[[` | 次/前の参照へ移動 |
| `<leader>xx` | 診断を Location リストに送る |

---

## 詳細

### ナビゲーション

| キー | 説明 | モード |
|---|---|---|
| `gd` | 定義へジャンプ | Normal |
| `gD` | 宣言へジャンプ | Normal |
| `gI` | 実装へジャンプ | Normal |
| `gy` | 型定義へジャンプ | Normal |
| `gr` | 参照一覧を開く | Normal |
| `]]` | 次の参照へ移動 | Normal |
| `[[` | 前の参照へ移動 | Normal |
| `<a-n>` | 次の参照へ移動 | Normal |
| `<a-p>` | 前の参照へ移動 | Normal |

### 情報表示

| キー | 説明 | モード |
|---|---|---|
| `K` | ホバードキュメント | Normal |
| `gK` | シグネチャヘルプ | Normal |
| `<C-k>` | シグネチャヘルプ | Insert |

### コード編集

| キー | 説明 | モード |
|---|---|---|
| `<leader>ca` | コードアクション | Normal / Visual |
| `<leader>cA` | ソースアクション | Normal |
| `<leader>cr` | リネーム | Normal |
| `<leader>cR` | ファイルリネーム | Normal |
| `<leader>cc` | CodeLens 実行 | Normal / Visual |
| `<leader>cC` | CodeLens 更新・表示 | Normal |

### 診断

| キー | 説明 |
|---|---|
| `<leader>xx` | 診断を Location リストに送る |
| `<leader>xq` | Quickfix リストを開く |
| `<leader>xl` | Location リストを開く |

### コマンド

| コマンド | 説明 |
|---|---|
| `:LspInfo` | アクティブな LSP クライアントの状態表示 |
| `:LspStart [name]` | LSP サーバーを起動 |
| `:LspStop [name]` | LSP サーバーを停止 |
| `:LspRestart [name]` | LSP サーバーを再起動 |
| `:checkhealth vim.lsp` | LSP の診断情報（Nvim 0.12+ 推奨） |

---

## 使い方

### LSP が動作しているか確認する

1. ファイルを開く
2. `:LspInfo` または `:checkhealth vim.lsp` を実行
3. 「attached clients」にサーバー名が表示されれば OK

### 新しい言語サーバーを追加する

1. Mason で言語サーバーをインストール（`:Mason`）
2. `nvim-lspconfig.lua` の `servers` テーブルにサーバー名を追加
3. Neovim を再起動

---

## 注意事項

- `require('lspconfig')` による設定は非推奨。Nvim 0.11+ では `vim.lsp.config()` と `vim.lsp.enable()` を使用すること（この設定では対応済み）
- nvim-lspconfig は言語サーバー本体をインストールしない。Mason 等で別途インストールが必要
- `document_highlight`（カーソル下のシンボルをハイライト）と `inlay_hints` は設定で有効化可能（現在は両方無効）
- Nvim 0.11.3 以上が必要
