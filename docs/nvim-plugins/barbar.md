# barbar.nvim

再配置・クリック可能なタブラインプラグイン。バッファをタブとして視覚的に管理できる。

設定ファイル: `config/nvim/lua/plugins/barbar.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<A-,>` | 前のバッファへ移動 |
| `<A-.>` | 次のバッファへ移動 |
| `<A-1>` 〜 `<A-9>` | バッファ1〜9へ直接ジャンプ |
| `<A-0>` | 最後のバッファへ移動 |
| `<C-p>` | バッファ選択モード（文字で選択） |
| `<A-p>` | バッファをピン留め／解除 |
| `<A-c>` | バッファを閉じる |
| `<A-s-c>` | 現在以外のバッファを全て閉じる |

---

## 詳細

### バッファ移動

- `<A-,>` — 前のバッファへ移動
- `<A-.>` — 次のバッファへ移動
- `<A-1>` 〜 `<A-9>` — バッファ1〜9へ直接ジャンプ
- `<A-0>` — 最後のバッファへ移動

### バッファ並び替え

- `<A-<>` — バッファを左へ移動
- `<A->>` — バッファを右へ移動

### バッファ選択・操作

- `<C-p>` — バッファ選択モード（セマンティック文字で素早く選択）
- `<A-p>` — バッファをピン留め／解除
- `<A-c>` — バッファを閉じる（ウィンドウレイアウト保持）
- `<A-s-c>` — 現在以外のバッファを全て閉じる

### ソート

- `<leader>bb` — バッファ番号順にソート
- `<leader>bd` — ディレクトリ順にソート
- `<leader>bl` — 言語順にソート
- `<leader>bw` — ウィンドウ番号順にソート

### コマンド

**クローズ**
- `:BufferClose` — 現在のバッファを閉じる
- `:BufferRestore` — 直前に閉じたバッファを復元
- `:BufferCloseAllButCurrent` — 現在以外を全て閉じる
- `:BufferCloseAllButPinned` — ピン留め以外を全て閉じる
- `:BufferCloseBuffersLeft` — 左側のバッファを全て閉じる
- `:BufferCloseBuffersRight` — 右側のバッファを全て閉じる

**選択**
- `:BufferPick` — バッファ選択モード
- `:BufferPickDelete` — バッファ選択して削除

**ソート**
- `:BufferOrderByBufferNumber` — バッファ番号順
- `:BufferOrderByName` — 名前順
- `:BufferOrderByDirectory` — ディレクトリ順
- `:BufferOrderByLanguage` — 言語順
- `:BufferOrderByWindowNumber` — ウィンドウ番号順

**有効化**
- `:BarbarEnable` — barbar を有効化
- `:BarbarDisable` — barbar を無効化

---

## 注意事項

- `bdelete` ではなく `:BufferClose` を使うこと（ウィンドウレイアウト崩れ防止）
- アイコン表示には Nerd Font が必要
- Mac の iTerm では Option キーを Esc+ として設定すること（Alt キー互換）
