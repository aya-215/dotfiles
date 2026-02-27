# nvim-web-devicons

Neovimプラグイン向けにNerd Fontアイコン（グリフ）を提供するライブラリ。

設定ファイル: `config/nvim/lua/plugins/nvim-web-devicons.lua`

---

## クイックリファレンス

| コマンド / API | 説明 |
|---|---|
| `:NvimWebDeviconsHiTest` | 全アイコンと色分けを一覧表示 |
| `get_icon(name, ext)` | ファイル名・拡張子からアイコン取得 |
| `get_icon_color(name, ext)` | アイコンと色コードを取得 |
| `get_icons()` | 登録済みアイコンをすべて取得 |
| `refresh()` | カラースキーム変更後にアイコン色を再適用 |

---

## 詳細

### コマンド

- `:NvimWebDeviconsHiTest` — 全アイコンとハイライト色を確認できるデバッグビュー

### API メソッド

- `require('nvim-web-devicons').get_icon(name, ext, opts)` — ファイル名と拡張子からアイコン文字列を返す
- `require('nvim-web-devicons').get_icon_color(name, ext, opts)` — アイコン文字列と色コード（hex）を返す
- `require('nvim-web-devicons').get_icon_by_filetype(ft, opts)` — ファイルタイプからアイコンを返す
- `require('nvim-web-devicons').get_icons()` — 登録済み全アイコン情報をテーブルで返す
- `require('nvim-web-devicons').set_icon(icons)` — アイコンを追加・上書き設定する
- `require('nvim-web-devicons').set_default_icon(icon, color, cterm_color)` — デフォルトアイコンを設定する
- `require('nvim-web-devicons').refresh()` — カラースキーム変更後に色を再適用する

### 設定オプション

- `override` — 個別アイコンのカスタマイズ定義
- `override_by_filename` — ファイル名別のアイコン上書き
- `override_by_extension` — 拡張子別のアイコン上書き
- `color_icons` — アイコンごとに異なる色を使用（デフォルト: `true`）
- `default` — 未登録ファイルにデフォルトアイコンを表示（デフォルト: `false`）
- `strict` — ファイル名マッチを拡張子より優先する厳格モード
- `variant` — カラーテーマを手動指定（`"light"` / `"dark"`）

---

## 注意事項

- キーマップは持たない。他プラグイン（neo-tree, lualine, telescope 等）から呼び出されるライブラリ
- アイコンを正しく表示するには **Nerd Font** 対応フォントが必要
- カラースキームを変更した場合は `refresh()` を呼んで色を同期させること
