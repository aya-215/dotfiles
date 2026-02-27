# which-key.nvim

キーを押した途中でポップアップを表示し、利用可能なキーバインドを一覧表示するプラグイン。

設定ファイル: `config/nvim/lua/plugins/which-key.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<leader>` | グループ一覧がポップアップ表示される |
| `<leader>?` | バッファローカルのキーマップを表示 |
| `<esc>` | ポップアップを閉じる |
| `<bs>` | 一段階上に戻る |
| `<c-d>` | ポップアップ内を下にスクロール |
| `<c-u>` | ポップアップ内を上にスクロール |

---

## 詳細

### リーダーキーグループ一覧

| プレフィックス | グループ |
|---|---|
| `<leader>a` | AI/Claude |
| `<leader>b` | バッファ |
| `<leader>c` | コード |
| `<leader>f` | ファイル |
| `<leader>g` | Git |
| `<leader>go` | Octo |
| `<leader>h` | Git hunk |
| `<leader>l` | LSP |
| `<leader>q` | セッション |
| `<leader>r` | Markdown |
| `<leader>s` | 検索 |
| `<leader>u` | UIトグル |
| `<leader>w` | ウィンドウ（`<c-w>` のプロキシ） |
| `<leader>x` | 診断/Quickfix |
| `[` | prev |
| `]` | next |
| `g` | goto |
| `gs` | surround |
| `z` | fold |

### ポップアップ内操作

- `<esc>` — キャンセルしてポップアップを閉じる
- `<bs>` — 一段階上に戻る
- `<c-d>` — 下にスクロール
- `<c-u>` — 上にスクロール

### Lua API

- `require("which-key").show({ global = false })` — バッファローカルのキーマップを表示
- `require("which-key").show({ keys = "<c-w>", loop = true })` — Hydraモード（`<esc>` まで開いたまま）
- `require("which-key").add({ ... })` — キーマップを動的に追加

---

## 注意事項

- 現在の設定は `preset = "helix"` を使用
- `:checkhealth which-key` で動作確認できる
