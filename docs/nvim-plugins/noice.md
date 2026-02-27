# noice.nvim

メッセージ・コマンドライン・ポップアップメニューの UI を完全に置き換える実験的プラグイン。

設定ファイル: `config/nvim/lua/plugins/noice.lua`

---

## クイックリファレンス

| キー / コマンド | 説明 |
|---|---|
| `:Noice` | メッセージ履歴を表示 |
| `:Noice last` | 最後のメッセージをポップアップで表示 |
| `:Noice dismiss` | 表示中のメッセージをすべて閉じる |
| `:Noice errors` | エラーメッセージのみ表示 |
| `<C-f>` | LSP ホバードキュメントを下にスクロール（n/i/s） |
| `<C-b>` | LSP ホバードキュメントを上にスクロール（n/i/s） |

---

## 詳細

### コマンド

- `:Noice` / `:Noice history` — メッセージ履歴をスプリットで表示
- `:Noice last` — 最後のメッセージをポップアップで表示
- `:Noice dismiss` — 表示中のすべてのメッセージを閉じる
- `:Noice errors` — エラーメッセージのみスプリットで表示
- `:Noice all` — すべてのメッセージをスプリットで表示
- `:Noice enable` — noice を有効化
- `:Noice disable` — noice を無効化
- `:Noice stats` — デバッグ統計を表示
- `:Noice telescope` — Telescope でメッセージ履歴を開く
- `:Noice fzf` — fzf-lua でメッセージ履歴を開く
- `:Noice pick` — 設定済みピッカー（telescope / fzf-lua）を開く
- `:checkhealth noice` — 環境のヘルスチェックを実行

### LSP ホバースクロール（推奨設定）

```lua
vim.keymap.set({ "n", "i", "s" }, "<c-f>", function()
  if not require("noice.lsp").scroll(4) then
    return "<c-f>"
  end
end, { silent = true, expr = true })

vim.keymap.set({ "n", "i", "s" }, "<c-b>", function()
  if not require("noice.lsp").scroll(-4) then
    return "<c-b>"
  end
end, { silent = true, expr = true })
```

### 現在の設定（noice.lua）

| オプション | 設定値 | 説明 |
|---|---|---|
| `cmdline.view` | `"cmdline_popup"` | コマンドラインをポップアップ表示 |
| `presets.bottom_search` | `false` | 検索を中央に表示 |
| `presets.command_palette` | `true` | コマンドパレットスタイル |
| `presets.long_message_to_split` | `true` | 長いメッセージを分割ウィンドウへ |

---

## 注意事項

- Neovim >= 0.9.0 が必須（nightly 推奨）
- 実験的 API を使用しているため、他プラグインとの競合が起きる可能性あり
- nvim-treesitter の導入推奨（`vim`, `regex`, `lua`, `bash`, `markdown` パーサーが必要）
- 問題発生時は `:checkhealth noice` を実行すること
