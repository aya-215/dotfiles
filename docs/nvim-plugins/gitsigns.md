# gitsigns.nvim

Git の変更をバッファ内に直接表示・操作するプラグイン（サインカラム、blame、diff など）

設定ファイル: `config/nvim/lua/plugins/gitsigns.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `]h` | 次のハンクへ移動 |
| `[h` | 前のハンクへ移動 |
| `<leader>hs` | ハンクをステージ（v: 範囲指定可） |
| `<leader>hr` | ハンクをリセット（v: 範囲指定可） |
| `<leader>hu` | ステージを取り消し |
| `<leader>hp` | ハンクをインラインプレビュー |
| `<leader>hb` | 現在行の blame 表示（full） |
| `<leader>hd` | 現在ファイルを diff |

---

## 詳細

### ナビゲーション

- `]h` — 次のハンクへ移動（diff モード時は `]c` と同等）
- `[h` — 前のハンクへ移動（diff モード時は `[c` と同等）

### ハンク操作

- `<leader>hs` (n/v) — ハンクをステージ（v モードで範囲指定可）
- `<leader>hr` (n/v) — ハンクをリセット（v モードで範囲指定可）
- `<leader>hu` — 直前のステージを取り消し
- `<leader>hp` — ハンクをインラインプレビュー

### バッファ全体の操作

- `<leader>hS` — バッファ全体をステージ
- `<leader>hR` — バッファ全体をリセット

### Blame

- `<leader>hb` — 現在行の blame を詳細表示（full=true）
- `<leader>hB` — バッファ全体の blame を表示（スクロール同期スプリット）

### Diff

- `<leader>hd` — インデックスと diff を開く
- `<leader>hD` — 直前のコミット（`~`）と diff を開く

### テキストオブジェクト

- `ih` (o/x) — ハンクをテキストオブジェクトとして選択（`vih`, `dih`, `cih` など）

### コマンド（Gitsigns 全般）

- `:Gitsigns stage_hunk` — ハンクをステージ
- `:Gitsigns reset_hunk` — ハンクをリセット
- `:Gitsigns preview_hunk` — フローティングウィンドウでプレビュー
- `:Gitsigns blame_line` — 現在行の blame 表示
- `:Gitsigns diffthis` — vimdiff を開く
- `:Gitsigns toggle_current_line_blame` — 現在行 blame のオン/オフ
- `:Gitsigns toggle_signs` — サインカラムのオン/オフ
- `:Gitsigns toggle_word_diff` — 単語レベル diff のオン/オフ
- `:Gitsigns setqflist` — 変更ハンクを quickfix リストに追加
- `:Gitsigns change_base {rev}` — 比較基準リビジョンを変更（例: `HEAD`, `main~1`）
- `:Gitsigns reset_base` — 比較基準をインデックスに戻す

---

## 使い方

### 部分ステージ（行範囲を指定してステージ）

1. `V` でビジュアルライン選択して対象行を選ぶ
2. `<leader>hs` でその範囲だけステージ

### 特定コミットとの diff

1. `:Gitsigns change_base HEAD~3` で比較基準を変更
2. `<leader>hd` で diff を表示
3. 終わったら `:Gitsigns reset_base` で戻す
