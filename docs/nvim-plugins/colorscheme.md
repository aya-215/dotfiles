# catppuccin/nvim

Neovim 向けの高度にカスタマイズ可能なカラースキームプラグイン（4種類のフレーバー提供）

設定ファイル: `config/nvim/lua/plugins/colorscheme.lua`

---

## クイックリファレンス

| コマンド | 説明 |
|---|---|
| `:colorscheme catppuccin` | catppuccin テーマを適用 |
| `:colorscheme catppuccin-latte` | ライト系フレーバーを適用 |
| `:colorscheme catppuccin-frappe` | フレーバー frappe を適用 |
| `:colorscheme catppuccin-macchiato` | フレーバー macchiato を適用 |
| `:colorscheme catppuccin-mocha` | ダーク系フレーバーを適用（現在の設定） |

---

## 詳細

### フレーバー一覧

| フレーバー名 | 特徴 |
|---|---|
| `catppuccin-latte` | ライト系 |
| `catppuccin-frappe` | ミディアムダーク |
| `catppuccin-macchiato` | ダーク |
| `catppuccin-mocha` | 最もダーク（現在の設定） |

### 設定オプション

- `transparent_background` — 背景を透明にする（現在: `true`）
- `flavour` — デフォルトのフレーバー（`"latte"` / `"frappe"` / `"macchiato"` / `"mocha"` / `"auto"`）
- `background` — `flavour = "auto"` 時のライト・ダーク切り替え設定
- `dim_inactive` — 非アクティブウィンドウを暗くする
- `styles` — コメント・条件分岐などの表示スタイル制御
- `integrations` — 各プラグインとの統合有効/無効設定
- `compile_path` — コンパイル済みキャッシュのパス

### Lua API

- `require("catppuccin.palettes").get_palette("mocha")` — カラーパレットを取得（ハイライト設定などに活用）

---

## 注意事項

- 現在の設定は `catppuccin-mocha`（ダーク）＋ `transparent_background = true`
- フレーバーを変えたい場合は `config` 関数内の `vim.cmd.colorscheme("catppuccin-mocha")` を変更する
- `flavour = "auto"` を使うと OS のライト/ダーク設定に自動追従できる
