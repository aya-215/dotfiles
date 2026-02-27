# vim-auto-save

`:w` なしで変更を自動的にディスクに保存するプラグイン。

設定ファイル: `config/nvim/lua/plugins/vim-auto-save.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<leader>ua` | 自動保存の切替 |
| `:AutoSaveToggle` | 自動保存の有効/無効を切り替え |

---

## 詳細

### コマンド

- `:AutoSaveToggle` — 自動保存の有効/無効をトグル

### 設定オプション

- `g:auto_save` — 起動時に自動保存を有効化（`1` で有効）
- `g:auto_save_silent` — 保存時の通知を非表示（`1` で非表示）
- `g:auto_save_in_insert_mode` — 挿入モード中の保存（`0` で無効）
- `g:auto_save_no_updatetime` — updatetime の自動変更を防ぐ（`1` で防ぐ）
- `g:auto_save_postsave_hook` — 保存後に実行するコマンドを指定

---

## 注意事項

- ClaudeCode の diff バッファ（`(proposed)` バッファ）では自動保存が自動的に無効化される
- diff タブ内の元ファイルも含めて自動保存が無効になる
