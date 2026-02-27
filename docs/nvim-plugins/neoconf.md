# neoconf.nvim

グローバル設定とプロジェクトローカル設定を JSON ファイルで管理し、LSP に自動反映するプラグイン

設定ファイル: `config/nvim/lua/plugins/neoconf.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `:Neoconf` | ローカル/グローバル設定ファイルを選択して開く |
| `:Neoconf show` | マージされた設定をフローティングウィンドウで確認 |
| `:Neoconf lsp` | マージされた LSP 設定を確認 |

---

## 詳細

### コマンド

- `:Neoconf` — ローカル・グローバル設定ファイルの選択 UI を表示
- `:Neoconf local` — ローカル設定ファイル（`.neoconf.json`）のみ選択
- `:Neoconf global` — グローバル設定ファイル（`neoconf.json`）のみ選択
- `:Neoconf show` — マージされた全設定をフローティングウィンドウで表示
- `:Neoconf lsp` — マージされた LSP 設定をフローティングウィンドウで表示

### 設定ファイルの場所

| ファイル | パス |
|---|---|
| グローバル設定 | `~/.config/nvim/neoconf.json` |
| プロジェクトローカル設定 | `{project-root}/.neoconf.json` |

---

## 注意事項

- `nvim-lspconfig` より**前に** `require("neoconf").setup({})` を呼ぶこと（priority = 100 で先読み済み）
- 設定ファイルは jsonc 形式（コメント可）
- 適用優先順位：Lua 設定 → グローバル JSON → ローカル JSON（ローカルが最優先）
- JSON ファイルを保存すると `live_reload` により LSP クライアントに自動反映される
