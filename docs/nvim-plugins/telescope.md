# telescope.nvim

リストに対する高度に拡張可能なファジーファインダー。ファイル・grep・LSP・Git など多彩な検索をTUI上で提供する。

設定ファイル: `config/nvim/lua/plugins/telescope.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<leader>ff` | ファイル検索 |
| `<leader>sg` | 文字列検索 (Grep) |
| `<leader>fb` | バッファ一覧 |
| `<leader>fr` | 最近使用したファイル |
| `<leader>sw` | カーソル下の単語を検索 |
| `<leader>sr` | 前回の検索を再開 |
| `<leader>gs` | Git変更状態 |
| `<leader>xd` | 全診断情報 |

---

## 詳細

### ファイル操作

- `<leader>ff` — ファイル検索（hidden ファイルも対象、.gitignore 考慮）
- `<leader>fb` — バッファ一覧（最近使用順）
- `<leader>fr` — 最近使用したファイル

### 検索

- `<leader>sg` — 文字列検索 (live_grep、hidden・no-ignore 対応)
- `<leader>sw` — カーソル下の単語を検索
- `<leader>sh` — ヘルプタグ検索
- `<leader>sc` — コマンド一覧
- `<leader>sk` — キーマップ一覧
- `<leader>sr` — 前回の検索を再開

### Git

- `<leader>gc` — Gitコミット履歴
- `<leader>gs` — Git変更状態
- `<leader>gb` — Gitブランチ

### LSP

- `<leader>lr` — LSP参照
- `<leader>ls` — ドキュメントシンボル

### 診断

- `<leader>xd` — 全診断情報
- `<leader>xD` — バッファ内の診断

---

### ピッカー内操作（インサートモード）

| キー | 説明 |
|---|---|
| `<C-j>` / `<C-k>` | 次/前の項目へ移動（カスタム） |
| `<C-n>` / `<C-p>` | 次/前の項目へ移動（デフォルト） |
| `<CR>` | 選択実行（現在ウィンドウ） |
| `<C-x>` | 水平分割で開く |
| `<C-v>` | 垂直分割で開く |
| `<C-t>` | 新しいタブで開く |
| `<Tab>` | 複数選択切り替え + 次へ |
| `<S-Tab>` | 複数選択切り替え + 前へ |
| `<C-q>` | Quickfixリストに送って開く |
| `<M-q>` | 選択項目をQuickfixに送る |
| `<C-u>` / `<C-d>` | プレビューを上下スクロール |
| `<Esc>` | 閉じる（カスタム） |

### ピッカー内操作（ノーマルモード）

| キー | 説明 |
|---|---|
| `j` / `k` | 次/前の項目 |
| `gg` / `G` | 最初/最後の項目へ |
| `<C-q>` | Quickfixリストに送って開く |
| `q` | 閉じる（カスタム） |

### ピッカー固有操作

**バッファ一覧 (`<leader>fb`):**
- `<C-d>` (insert) / `dd` (normal) — バッファを削除

**Git commits (`<leader>gc`):**
- `<CR>` — コミットをチェックアウト
- `<C-r>m` / `<C-r>s` / `<C-r>h` — mixed/soft/hard リセット

**Git branches (`<leader>gb`):**
- `<CR>` — ブランチをチェックアウト
- `<C-t>` — ブランチを追跡
- `<C-r>` — リベース
- `<C-a>` — 新規ブランチ作成
- `<C-d>` — ブランチ削除
- `<C-y>` — マージ

**Git status (`<leader>gs`):**
- `<Tab>` — ファイルをステージ/アンステージ

---

## 注意事項

- Neovim v0.10.4以上、LuaJIT対応が必須
- インストール後は `:checkhealth telescope` で動作確認推奨
- `telescope-fzf-native.nvim` は cmake でビルドが必要。cmake 未インストール環境では fzf 拡張はコメントアウト済み
