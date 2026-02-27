# mason.nvim

Neovim 上で LSP サーバー・DAP サーバー・リンター・フォーマッターをポータブルに管理するパッケージマネージャー。

設定ファイル: `config/nvim/lua/plugins/mason.lua`

---

## クイックリファレンス

| キー / コマンド | 説明 |
|---|---|
| `<leader>cm` | Mason UI を開く |
| `:Mason` | Mason UI を開く |
| `:MasonInstall <package>` | パッケージをインストール |
| `:MasonUninstall <package>` | パッケージをアンインストール |
| `:MasonUpdate` | レジストリを更新 |
| `:MasonToolsInstall` | tool-installer の対象をインストール |
| `:MasonToolsUpdate` | tool-installer の対象を更新 |

---

## 詳細

### Mason UI 内キーマップ

| キー | 説明 |
|---|---|
| `<CR>` | パッケージの詳細を展開 / インストールログを表示 |
| `i` | パッケージをインストール |
| `u` | パッケージを更新 |
| `c` | パッケージのバージョンを確認 |
| `U` | 全パッケージを更新 |
| `C` | 古いパッケージを確認 |
| `X` | パッケージをアンインストール |
| `<C-c>` | インストールをキャンセル |
| `<C-f>` | 言語フィルターを適用 |
| `g?` | ヘルプを表示 / 非表示 |

### コマンド（mason-tool-installer）

- `:MasonToolsInstall` — `ensure_installed` リストのツールをインストール
- `:MasonToolsUpdate` — `ensure_installed` リストのツールを更新
- `:MasonToolsClean` — リストにないツールを削除

### 自動管理ツール

**mason.nvim** (`ensure_installed`):
- `stylua`, `shfmt`, `flake8`

**mason-lspconfig.nvim** (`ensure_installed`):
- `lua_ls`, `jsonls`, `yamlls`, `html`, `cssls`, `ts_ls`, `eslint`, `pyright`, `bashls`, `marksman`, `jdtls`

**mason-tool-installer.nvim** (`ensure_installed`):
- `prettier`, `prettierd`, `stylua`, `isort`, `black`, `pylint`, `eslint_d`, `shellcheck`, `shfmt`, `hadolint`, `markdownlint`, `yamllint`, `jsonlint`, `fixjson`

---

## 使い方

1. `:Mason` または `<leader>cm` で UI を開く
2. `<C-f>` で言語フィルターを絞り込む
3. カーソルを当てて `i` でインストール
4. インストール済みパッケージは `U` でまとめて更新可能

---

## 注意事項

- Neovim >= 0.10.0 が必須
- `git`, `curl`, `unzip` 等の外部ツールが必要。`:checkhealth mason` で確認可能
- mason-lspconfig の `automatic_installation` は `false`（nvim-lspconfig.lua 側で統一管理）
- mason-tool-installer は `run_on_start = false`（起動時に自動実行しない）
