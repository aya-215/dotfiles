# conform.nvim

ファイルタイプごとに複数のフォーマッターを設定・実行できる、軽量で強力なフォーマットプラグイン。

設定ファイル: `config/nvim/lua/plugins/conform.lua`

---

## クイックリファレンス

| キー / コマンド | 説明 |
|---|---|
| `<leader>cf` | バッファをフォーマット（ノーマル・ビジュアルモード） |
| `:ConformInfo` | 利用可能なフォーマッター・ログファイルを確認 |

---

## 詳細

### キーマップ

- `<leader>cf` (n/v) — 現在のバッファ（または選択範囲）を非同期フォーマット。フォーマッターが未設定の場合は LSP にフォールバック

### コマンド

- `:ConformInfo` — 現在のバッファで有効なフォーマッター一覧、インストール状況、ログファイルのパスを表示

### API 関数

- `require("conform").format({opts})` — バッファをフォーマット
- `require("conform").list_formatters({bufnr})` — 現在のバッファで利用可能なフォーマッター一覧
- `require("conform").list_formatters_to_run({bufnr})` — 実際に実行されるフォーマッターを取得
- `require("conform").list_all_formatters()` — 全フォーマッター情報
- `require("conform").get_formatter_info({formatter})` — 指定フォーマッターの詳細情報

#### `format()` の主要オプション

| オプション | 説明 |
|---|---|
| `async` | 非同期実行（`true` / `false`） |
| `timeout_ms` | タイムアウト時間（デフォルト 1000ms） |
| `lsp_format` | LSP 使用方法（`"never"` / `"fallback"` / `"prefer"` / `"first"` / `"last"`） |
| `formatters` | 実行するフォーマッターを明示指定 |
| `range` | フォーマット範囲指定（ビジュアル選択時に自動設定） |

### 設定済みフォーマッター

| ファイルタイプ | フォーマッター | オプション |
|---|---|---|
| js / jsx / ts / tsx | prettier | `--single-quote`, `--trailing-comma es5` |
| css / scss / html | prettier | 同上 |
| jsonc / markdown | prettier | 同上 |
| lua | stylua | — |
| python | black | — |
| sh / bash / zsh | shfmt | `-i 2`（インデント2スペース） |

---

## 注意事項

- **保存時自動フォーマット** が有効になっている（タイムアウト 1000ms、LSP フォールバックあり）。無効にしたい場合は `format_on_save = false` を設定する
- フォーマッターが見つからない場合のデバッグには `:ConformInfo` が便利
