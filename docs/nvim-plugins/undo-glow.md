# undo-glow.nvim

undo・redo・yank・paste・search・comment などのテキスト操作に美しいビジュアルフィードバックを追加する。

設定ファイル: `config/nvim/lua/plugins/undo-glow.lua`

---

## クイックリファレンス

| キー | モード | 説明 |
|---|---|---|
| `u` | n | Undo（グロウ付き） |
| `U` | n | Redo（グロウ付き） |
| `n` | n | 次の検索結果へ（グロウ付き） |
| `N` | n | 前の検索結果へ（グロウ付き） |
| `*` | n | カーソル下の単語を前方検索（グロウ付き） |
| `#` | n | カーソル下の単語を後方検索（グロウ付き） |
| `gc` | n/x | コメントトグル（グロウ付き） |
| `gcc` | n | 行コメントトグル（グロウ付き） |
| `<C-r>` | i | レジスタからペースト（グロウ付き） |

---

## 詳細

### テキスト操作

- `u` — Undo with glow
- `U` — Redo with glow
- `<C-r>`（insert モード）— レジスタからペースト with glow

### 検索

- `n` — 次の検索結果にジャンプ with glow
- `N` — 前の検索結果にジャンプ with glow
- `*` — カーソル下の単語を前方検索 with glow
- `#` — カーソル下の単語を後方検索 with glow

### コメント

- `gc` — コメントトグル（normal/visual モード）with glow
- `gcc` — 行コメントトグル with glow

### Yank（autocmd 連携）

Yank は `TextYankPost` autocmd で自動的にハイライト。キーマップ設定は不要。

---

## ハイライトカラー設定

| 操作 | 背景色 |
|---|---|
| Undo | `#693232`（赤系）|
| Redo | `#2F4640`（緑系）|
| Yank | `#7A683A`（黄系）|
| Paste | `#325B5B`（シアン系）|
| Search | `#5C475C`（紫系）|
| Comment | `#4A4A5A`（グレー系）|

---

## 注意事項

- キーマップは**自動設定されない**ので、`keys` テーブルで明示的に設定が必要
- アニメーション設定: duration=400ms、fade アニメーション、fps=60、ウィンドウスコープ
