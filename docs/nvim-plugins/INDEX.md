# Neovim プラグイン INDEX

> 各プラグインの詳細は同フォルダ内の `{name}.md` を参照

---

## Git

### [gitsigns.nvim](gitsigns.md)
Git の変更をバッファ内に直接表示・操作する（サインカラム、blame、diff など）

- `]h` / `[h`: 次/前のハンクへ移動
- `<leader>hs`: ハンクをステージ
- `<leader>hr`: ハンクをリセット
- `<leader>hp`: ハンクをインラインプレビュー
- `<leader>hb`: 行の blame 表示

### [lazygit.nvim](lazygit.md)
Neovim のフローティングウィンドウから lazygit を直接呼び出す

- `<leader>gg`: LazyGit を起動
- `<leader>gf`: 現在ファイルのプロジェクトルートで起動

### [diffview.nvim](diffview.md)
git の差分を全変更ファイル一覧で閲覧・ファイル履歴の確認ができるインターフェース

- `<leader>gd`: 差分ビューを開く
- `<leader>gD`: 差分ビューを閉じる
- `<leader>gm`: origin/main の merge-base との差分
- `<leader>gh`: 現在ファイルの履歴

### [octo.nvim](octo-nvim.md)
Neovim 内で GitHub の PR / Issue / Discussion を操作する

- `<Space>gop`: PR 一覧
- `<Space>goi`: Issue 一覧
- `<Space>goc`: PR 作成
- `<Space>gor`: レビュー開始

---

## ファイル操作

### [oil.nvim](oil.md)
ファイルシステムを普通の Neovim バッファとして編集できるファイルエクスプローラー

- `-`: 親ディレクトリを開く（どこからでも使える）
- `<leader>e`: ファイルエクスプローラーを開く
- `<CR>`: ファイル/ディレクトリを開く
- `:w`: 変更を保存してファイル操作を実行

### [neo-tree.nvim](neo-tree.md)
ファイルシステム・バッファ・Git 状態をツリー形式でブラウズできるサイドバー

- `<leader>E`: Neo-tree 開閉トグル
- `<leader>ge`: Git 変更ファイル一覧
- `<leader>be`: バッファ一覧
- `H`: 隠しファイル表示切り替え

---

## 検索・ナビゲーション

### [telescope.nvim](telescope.md)
リストに対する高度に拡張可能なファジーファインダー

- `<leader>ff`: ファイル検索
- `<leader>sg`: 文字列検索 (Grep)
- `<leader>fb`: バッファ一覧
- `<leader>fr`: 最近使用したファイル
- `<leader>sw`: カーソル下の単語を検索

### [flash.nvim](flash.md)
検索ラベルと文字モーションで、コード内を素早くナビゲートできるジャンププラグイン

- `s`: Flash ジャンプ（全ウィンドウ対象）
- `S`: Treesitter ノードへジャンプ
- `r`: Remote Flash（遠隔位置でオペレータ実行）

---

## LSP・補完

### [nvim-lspconfig](nvim-lspconfig.md)
Neovim の組み込み LSP クライアント向け言語サーバー設定集

- `gd`: 定義へジャンプ
- `gr`: 参照一覧
- `K`: ホバードキュメント表示
- `<leader>cr`: シンボルのリネーム
- `<leader>ca`: コードアクション

### [blink.cmp](blink-cmp.md)
高速でバッテリー込みの Neovim 補完プラグイン（LSP・スニペット・バッファ対応）

- `<C-space>`: 補完メニューを表示
- `<C-y>` / `<Tab>`: 候補を確定
- `<C-n>` / `<C-p>`: 次/前の候補を選択
- `<C-e>`: 補完メニューを閉じる

### [mason.nvim](mason.md)
LSP サーバー・DAP・リンター・フォーマッターをポータブルに管理するパッケージマネージャー

- `<leader>cm`: Mason UI を開く
- `:MasonInstall <package>`: パッケージをインストール
- `:MasonUpdate`: レジストリを更新

### [conform.nvim](conform.md)
ファイルタイプごとに複数のフォーマッターを設定・実行できる軽量フォーマットプラグイン

- `<leader>cf`: バッファをフォーマット
- `:ConformInfo`: 利用可能なフォーマッターを確認

---

## UI・表示

### [lualine.nvim](lualine.md)
高速でカスタマイズしやすい Neovim 用ステータスラインプラグイン

キーマップなし（自動表示）

### [barbar.nvim](barbar.md)
再配置・クリック可能なタブラインプラグイン。バッファをタブとして視覚的に管理する

- `<A-,>` / `<A-.>`: 前/次のバッファへ移動
- `<A-1>` 〜 `<A-9>`: バッファ番号で直接ジャンプ
- `<A-c>`: バッファを閉じる
- `<C-p>`: バッファ選択モード

### [noice.nvim](noice.md)
メッセージ・コマンドライン・ポップアップメニューの UI を完全に置き換える実験的プラグイン

- `:Noice`: メッセージ履歴を表示
- `:Noice last`: 最後のメッセージをポップアップで表示
- `:Noice dismiss`: 表示中のメッセージをすべて閉じる

### [catppuccin/nvim](colorscheme.md)
Neovim 向けの高度にカスタマイズ可能なカラースキームプラグイン（4 種類のフレーバー）

- `:colorscheme catppuccin-mocha`: ダーク系フレーバーを適用

### [nvim-web-devicons](nvim-web-devicons.md)
Neovim プラグイン向けに Nerd Font アイコン（グリフ）を提供するライブラリ

- `:NvimWebDeviconsHiTest`: 全アイコンと色分けを一覧表示

### [undo-glow.nvim](undo-glow.md)
undo・redo・yank・paste・search など各操作にビジュアルフィードバックを追加する

自動動作（キーマップ上書きなし）

---

## エディタ操作・ユーティリティ

### [nvim-treesitter](nvim-treesitter.md)
Tree-sitter パーサーを使ったシンタックスハイライト・インデント・テキストオブジェクト強化

- `<C-space>`: 選択範囲を段階的に拡大
- `af` / `if`: 関数全体/内部を選択
- `]m` / `[m`: 次/前の関数開始へ移動

### [mini.pairs](mini-pairs.md)
括弧・クォートを自動でペアリングする最小限のプラグイン

自動動作（入力時にペアを補完）

### [smart-splits.nvim](smart-splits.md)
直感的にウィンドウ移動・リサイズができるスプリット管理（Tmux / WezTerm 統合対応）

- `<M-h>` / `<M-l>`: 左/右のウィンドウへ移動
- `<M-j>` / `<M-k>`: 下/上のウィンドウへ移動

### [which-key.nvim](which-key.md)
キーを押した途中でポップアップを表示し、利用可能なキーバインドを一覧表示する

- `<leader>`: グループ一覧がポップアップ表示
- `<leader>?`: バッファローカルのキーマップを表示

### [persistence.nvim](persistence.md)
自動セッション管理のためのシンプルな Lua プラグイン

- `<leader>qs`: 現在のディレクトリのセッションを復元
- `<leader>ql`: 最後のセッションを復元
- `<leader>qd`: セッション保存を停止

### [vim-auto-save](vim-auto-save.md)
`:w` なしで変更を自動的にディスクに保存するプラグイン

- `<leader>ua`: 自動保存の切替

### [neoconf.nvim](neoconf.md)
グローバル設定とプロジェクトローカル設定を JSON ファイルで管理し、LSP に自動反映する

- `:Neoconf`: 設定ファイルを選択して開く
- `:Neoconf show`: マージされた設定を確認

### [claudecode.nvim](claudecode.md)
Neovim で Claude Code（Anthropic の AI コーディングアシスタント）を統合する

- `<leader>ac`: Claude の表示切替
- `<leader>as`: 選択範囲を Claude に送信
- `<leader>ab`: 現在のバッファをコンテキストに追加
- `<leader>aa` / `<leader>ad`: Diff を承認/拒否
