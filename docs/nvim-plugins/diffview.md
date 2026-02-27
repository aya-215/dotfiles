# diffview.nvim

git の差分を単一タブページで全変更ファイルを一覧表示・サイクル閲覧できるインターフェース。ファイル履歴の閲覧や merge-base との比較にも対応。

設定ファイル: `config/nvim/lua/plugins/diffview.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<leader>gd` | 差分ビューを開く（インデックスとの差分） |
| `<leader>gD` | 差分ビューを閉じる |
| `<leader>gm` | origin/main の merge-base との差分を表示 |
| `<leader>gh` | 現在のファイルの履歴を表示 |
| `<leader>gH` | 全ファイルの履歴を表示 |
| `<Tab>` / `<S-Tab>` | 次/前のファイルへ移動 |
| `-` | ファイルをステージ/アンステージ |
| `q` | 差分ビューを閉じる |

---

## 詳細

### leaderキーマップ（グローバル）

- `<leader>gd` — `:DiffviewOpen` — インデックスとの差分を表示
- `<leader>gD` — `:DiffviewClose` — 差分ビューを閉じる
- `<leader>gm` — `DiffviewOpen {merge-base}` — origin/main との merge-base 比較
- `<leader>gh` — `:DiffviewFileHistory %` — 現在ファイルの変更履歴
- `<leader>gH` — `:DiffviewFileHistory` — 全ファイルの変更履歴

### diffビュー内

- `<Tab>` / `<S-Tab>` — 次/前のファイルへ移動
- `<tab>` — ファイルパネルの表示切り替え（カスタム設定）
- `q` — 差分ビューを閉じる
- `<leader>ci` — コミット情報を表示
- `gf` — ファイルの現在バージョンを別タブで開く
- `<C-w><C-f>` — ファイルを新しい split で開く
- `<leader>b` — ファイルパネルを切り替え
- `<leader>e` — ファイルパネルにフォーカス
- `y` — commit ハッシュをコピー

### ファイルパネル

- `j` / `k` — 次/前のエントリに移動
- `<CR>` — エントリを選択して差分表示
- `<tab>` — ファイルパネルの表示切り替え
- `q` — 差分ビューを閉じる
- `<leader>ci` — コミット情報を表示
- `-` — ファイルをステージ/アンステージ
- `S` — 全エントリをステージ
- `U` — 全エントリをアンステージ
- `X` — ファイルを HEAD 側に戻す
- `R` — ファイルリストを更新

### ファイル履歴パネル

- `j` / `k` — 次/前のエントリに移動
- `<CR>` — エントリを選択して差分表示
- `q` — 差分ビューを閉じる
- `g!` — オプションパネルを開く
- `<C-d>` — commit を差分ビューで開く
- `zR` / `zM` — 全 fold を展開/閉じる

### コマンド

- `:DiffviewOpen [git-rev]` — 差分ビューを開く（rev 指定可、省略時はインデックスとの差分）
- `:DiffviewFileHistory [paths]` — ファイル履歴を表示（パス省略時は全ファイル）
- `:DiffviewClose` — アクティブな差分ビューを閉じる
- `:DiffviewToggleFiles` — ファイルパネルの表示/非表示を切り替え
- `:DiffviewFocusFiles` — ファイルパネルにフォーカスを移動
- `:DiffviewRefresh` — ファイルリストを更新

---

## 使い方

### 差分確認フロー

1. `<leader>gd` で差分ビューを開く
2. `<Tab>` / `<S-Tab>` でファイル間を移動
3. ファイルパネルで `-` を使ってステージ操作
4. `<leader>gD` で閉じる

### ファイル履歴確認フロー

1. 確認したいファイルを開く
2. `<leader>gh` でそのファイルの変更履歴を表示
3. `j` / `k` でコミット間を移動、`<CR>` で差分を確認
4. `<C-d>` でそのコミットを差分ビューで開く

### merge-base との差分確認フロー

1. `<leader>gm` で origin/main との merge-base 比較を開く
2. このブランチで変更したファイル一覧が表示される
3. `<Tab>` でファイル間を移動しながら変更を確認

---

## 注意事項

- **前提条件**: Git ≥ 2.31.0, Neovim ≥ 0.7.0
- Neovim 組み込みの diff 機能（`:h diff-mode`）を事前に習得しておくと操作しやすい
