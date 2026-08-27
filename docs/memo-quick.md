# 雑メモ（memo/quick）

tmux からワンキーで開く、日時ファイル1枚ずつの雑メモ。
todo.md（`docs/todo-md.md`）と同じ型で、窓の管理と採番は tmux、編集と一覧は Neovim、データは素の markdown。

nb は経由しない。nb を挟むメリット（git 履歴・タイトル付き一覧）が雑メモには薄く、
nvim から直接ファイルを作る設計と nb のインデックス管理が噛み合わないため。
残したいメモだけ `nbn` で `notes:` に昇格させる。

## 開き方

| 操作 | 動き |
|---|---|
| `C-q m`（tmux prefix + m） | `~/memo/quick/YYYYMMDD-HHMMSS.md` を新規作成してポップアップ（中央 60%×70%）で開く |

採番は tmux 側の `date` で行う。Neovim は「そのディレクトリの `.md` を開いた」ことだけで振る舞いを切り替える。
`~/memo/` 直下には todo.md と別の手持ちファイルがあるため、雑メモは `quick/` サブディレクトリに隔離している。
`~/memo` は git リポジトリだが、自動コミットの対象は todo.md だけで、雑メモはコミットしない。

## ファイル

- 1メモ = 1ファイル。テンプレは無く、空バッファから書き始める
- **タイトル**は先頭の非空行（`# ` などの見出し記号は剥がす）。無ければファイル名の日時を `2026-08-27 09:15` 形式で表示する
- **空白しか無いメモは残さない**。`q` で閉じるとき、および Neovim 終了時（`VimLeavePre`）に削除する。vim-auto-save が空ファイルを先に書いていても消える

## バッファ内キー（`~/memo/quick/*.md` を開いたときだけ有効）

| キー | 動き |
|---|---|
| `<leader>e` | メモ一覧（snacks.picker）。通常の「エクスプローラを開く」を、このバッファでは「メモ一覧」に上書き |
| `q` | 中身があれば保存して閉じる（`:exit`）。空なら削除して閉じる |

### 一覧（picker）内

| キー | 動き |
|---|---|
| `<CR>` | 選んだメモを同じウィンドウで開く |
| `<C-n>` | 新規メモを作って開く（ポップアップを閉じずに次のメモへ） |
| `<C-x>` | 確認付きで削除。ファイルとバッファの両方を消してから一覧を再表示 |

一覧は新しい順。表示は「タイトル  日時」、タイトルが無ければ日時のみ。右にファイルプレビュー。

## 実装

| ファイル | 役割 |
|---|---|
| `config/nvim/lua/memo/core.lua` | 純関数（タイトル抽出・空判定・ファイル名⇄日時）。ファイルにもバッファにも触らない |
| `config/nvim/lua/memo/init.lua` | autocmd でキーを付ける層、picker、空メモ削除。`init.lua` から `require("memo").setup()` |
| `config/nvim/tests/memo_core_spec.lua` | core のテスト |
| `modules/tmux.nix` | `bind m display-popup ...` |

テスト実行:

```sh
nvim --headless -u NONE -l config/nvim/tests/memo_core_spec.lua
```

対話的な挙動は `MEMO_DIR` でテスト用ディレクトリに向けて確認する（実ファイルには触らない）:

```sh
MEMO_DIR=/tmp/memo_test nvim /tmp/memo_test/20260827-100000.md
```

## 参考にしたもの

- 流派A（1ファイル scratch）: global-note.nvim / scratch.nvim / flote.nvim / quicknotes.nvim。一覧の概念が無いので不採用
- 流派B（日時ファイル + ピッカー）: tdo.nvim / zk-nvim / telekasten / DumbNotes.nvim。本実装はこちら。picker 内 `<C-n>` 新規 / `<C-x>` 削除は DumbNotes.nvim に倣った
- 「空のまま閉じたら消す」はどこにも無かったが、timestamped draft 方式で空ドラフトがゴミになる問題への対策として入れた

## 既知の問題と対処: popup 内で貼り付けると改行が `^[[27;5;106~` になる

tmux の popup は貼り付け（bracketed paste）を専用処理せず1キーずつ `input_key` に流すため、
`extended-keys on` の環境では LF が拡張キー `\e[27;5;106~`（csi-u なら `\e[106;5u`）にエンコードされて
paste の中に混ざる。通常ペインは `window_pane_paste` で生バイトを書くので起きない（tmux 3.7b、popup.c は master でも未修正）。
nvim は paste 中の内容を解釈しないので、`config/nvim/lua/config/paste.lua` で `vim.paste` をフックして改行に戻している。
todo.md のポップアップも同じ対処で守られる。

参考: tmux #4663 / #4163、neovim #38021、claude-code #43169

## やっていないこと

- タグ・検索（`~/memo/quick` に対して普通の grep / Telescope で足りる）
- nb 連携
- Neovim 内からのトグル表示（サイドバー/フロート）
