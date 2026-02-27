# persistence.nvim

自動セッション管理のためのシンプルな Lua プラグイン。

設定ファイル: `config/nvim/lua/plugins/persistence.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<leader>qs` | 現在のディレクトリのセッションを復元 |
| `<leader>ql` | 最後のセッションを復元 |
| `<leader>qd` | セッション保存を停止 |

---

## 詳細

### セッション操作

- `<leader>qs` — 現在のディレクトリに対応するセッションを読み込む
- `<leader>ql` — 最後に保存されたセッションを読み込む
- `<leader>qd` — Persistence を停止（現在のセッションを保存しない）

### Lua API

- `require("persistence").load()` — 現在ディレクトリのセッションを読み込む
- `require("persistence").load({ last = true })` — 最後のセッションを読み込む
- `require("persistence").select()` — セッション選択メニューを表示
- `require("persistence").stop()` — セッション保存を停止

### イベント

- `PersistenceLoadPre` / `PersistenceLoadPost` — セッション読み込み前後
- `PersistenceSavePre` / `PersistenceSavePost` — セッション保存前後

---

## 注意事項

- 自動復元は行わず、手動で API を呼び出す必要がある
- `branch` オプションで Git ブランチごとのセッション管理が可能（デフォルト: `true`）
