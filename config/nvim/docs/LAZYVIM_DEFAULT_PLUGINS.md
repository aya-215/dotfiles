# LazyVimデフォルトプラグイン一覧

このドキュメントは、LazyVimが自動的に提供するデフォルトプラグインの完全なリストです。pure lazy.nvimへの移行時に、これらのプラグインを明示的に設定する必要があります。

---

## 📦 カテゴリ別プラグイン一覧

### 1. **Editor（エディタ機能）**

#### **grug-far.nvim**
- **リポジトリ**: `MagicDuck/grug-far.nvim`
- **用途**: 複数ファイルにわたる検索・置換機能
- **使用場面**: プロジェクト全体での文字列置換が必要な時
- **代替**: `spectre.nvim`, `nvim-spectre`

#### **flash.nvim**
- **リポジトリ**: `folke/flash.nvim`
- **用途**: 高速ナビゲーション・ジャンプ機能
- **使用場面**: ファイル内の特定位置へ素早く移動したい時
- **代替**: `hop.nvim`, `leap.nvim`, `lightspeed.nvim`

#### **which-key.nvim**
- **リポジトリ**: `folke/which-key.nvim`
- **用途**: キーバインド表示ヘルプ
- **使用場面**: コマンド入力中にキーマップのヒントを表示
- **代替**: なし（必須プラグイン）
- **重要度**: ⭐⭐⭐（高）

#### **gitsigns.nvim**
- **リポジトリ**: `lewis6991/gitsigns.nvim`
- **用途**: Git差分表示とハンク操作
- **使用場面**: 変更箇所の可視化、ステージング操作
- **代替**: `vim-gitgutter`
- **重要度**: ⭐⭐⭐（高）

#### **trouble.nvim**
- **リポジトリ**: `folke/trouble.nvim`
- **用途**: LSP診断・参照の統合ビュー
- **使用場面**: エラー一覧の確認、定義・参照のジャンプ
- **代替**: Telescopeの診断機能で代用可能
- **重要度**: ⭐⭐（中）

#### **todo-comments.nvim**
- **リポジトリ**: `folke/todo-comments.nvim`
- **用途**: TODO/HACK/BUGコメントのハイライトと一覧表示
- **使用場面**: プロジェクト内のタスク管理
- **代替**: `vim-todo-lists`
- **重要度**: ⭐（低）

---

### 2. **UI（ユーザーインターフェース）**

#### **bufferline.nvim**
- **リポジトリ**: `akinsho/bufferline.nvim`
- **用途**: バッファタブ表示
- **使用場面**: 開いているファイルの視覚的管理
- **代替**: `barbar.nvim`（あなたは既に使用中）
- **重要度**: ⭐⭐⭐（高） - **既に無効化済み**

#### **lualine.nvim**
- **リポジトリ**: `nvim-lualine/lualine.nvim`
- **用途**: ステータスライン表示
- **使用場面**: ファイル情報、Git状態、LSP状態の表示
- **代替**: `feline.nvim`, `galaxyline.nvim`
- **重要度**: ⭐⭐⭐（高）

#### **noice.nvim**
- **リポジトリ**: `folke/noice.nvim`
- **用途**: メッセージ・コマンドライン・ポップアップのUI改善
- **使用場面**: より洗練されたUI体験が欲しい時
- **代替**: デフォルトのNeovim UIで十分
- **重要度**: ⭐（低）- オプション

#### **mini.icons**
- **リポジトリ**: `nvim-mini/mini.icons`
- **用途**: ファイルタイプアイコン表示
- **使用場面**: ファイルエクスプローラーやバッファラインでのアイコン表示
- **代替**: `nvim-web-devicons`（より一般的）
- **重要度**: ⭐⭐（中）

#### **nui.nvim**
- **リポジトリ**: `MunifTanjim/nui.nvim`
- **用途**: UI構築用ライブラリ（依存関係）
- **使用場面**: 他のプラグインが依存
- **代替**: なし
- **重要度**: ⭐⭐（依存関係として必要）

#### **snacks.nvim**
- **リポジトリ**: `folke/snacks.nvim`
- **用途**: 多機能ユーティリティ（ダッシュボード、通知、インデント表示など）
- **使用場面**: 起動画面、通知表示、インデント可視化
- **代替**: 個別プラグイン（`dashboard-nvim`, `indent-blankline.nvim`など）
- **重要度**: ⭐⭐（中）

---

### 3. **Coding（コーディング支援）**

#### **mini.pairs**
- **リポジトリ**: `nvim-mini/mini.pairs`
- **用途**: 括弧の自動ペアリング
- **使用場面**: `(`, `{`, `[`などの自動補完
- **代替**: `nvim-autopairs`, `ultimate-autopair.nvim`
- **重要度**: ⭐⭐⭐（高）

#### **ts-comments.nvim**
- **リポジトリ**: `folke/ts-comments.nvim`
- **用途**: Treesitterベースのコメント機能
- **使用場面**: コメントアウト/解除の操作
- **代替**: `Comment.nvim`, `nvim-comment`
- **重要度**: ⭐⭐⭐（高）

#### **mini.ai**
- **リポジトリ**: `nvim-mini/mini.ai`
- **用途**: テキストオブジェクト拡張
- **使用場面**: `vaa`（引数選択）、`vif`（関数内選択）など
- **代替**: `nvim-treesitter-textobjects`（Treesitter版）
- **重要度**: ⭐⭐（中）

#### **lazydev.nvim**
- **リポジトリ**: `folke/lazydev.nvim`
- **用途**: Neovim Lua開発時のLSP補完
- **使用場面**: Neovim設定ファイル（init.lua等）の編集時
- **代替**: なし（Neovim設定編集時に便利）
- **重要度**: ⭐⭐（中）

---

### 4. **LSP（言語サーバープロトコル）**

#### **nvim-lspconfig**
- **リポジトリ**: `neovim/nvim-lspconfig`
- **用途**: LSPサーバー接続設定
- **使用場面**: 言語サーバーとの通信
- **代替**: なし（必須）
- **重要度**: ⭐⭐⭐（必須）

#### **mason.nvim**
- **リポジトリ**: `mason-org/mason.nvim`
- **用途**: LSP/DAP/リンター/フォーマッターのインストール管理
- **使用場面**: 開発ツールの一元管理
- **代替**: 手動インストール
- **重要度**: ⭐⭐⭐（高）

#### **mason-lspconfig.nvim**
- **リポジトリ**: `mason-org/mason-lspconfig.nvim`
- **用途**: masonとnvim-lspconfigの統合
- **使用場面**: LSPサーバーの自動セットアップ
- **代替**: なし（mason使用時は必須）
- **重要度**: ⭐⭐⭐（高）

---

### 5. **Treesitter（構文解析）**

#### **nvim-treesitter**
- **リポジトリ**: `nvim-treesitter/nvim-treesitter`
- **用途**: 高度なシンタックスハイライト
- **使用場面**: コードの色付け、折りたたみ、インデント
- **代替**: なし（必須）
- **重要度**: ⭐⭐⭐（必須）

#### **nvim-treesitter-textobjects**
- **リポジトリ**: `nvim-treesitter/nvim-treesitter-textobjects`
- **用途**: Treesitterベースのテキストオブジェクト
- **使用場面**: 関数、クラス、パラメータ単位での選択・移動
- **代替**: `mini.ai`
- **重要度**: ⭐⭐（中）

#### **nvim-ts-autotag**
- **リポジトリ**: `windwp/nvim-ts-autotag`
- **用途**: HTML/JSXの閉じタグ自動補完
- **使用場面**: Web開発時
- **代替**: なし（Web開発者には便利）
- **重要度**: ⭐⭐（Web開発時は高）

---

### 6. **Formatting（コード整形）**

#### **conform.nvim**
- **リポジトリ**: `stevearc/conform.nvim`
- **用途**: コードフォーマッター管理
- **使用場面**: ファイル保存時の自動整形
- **代替**: `null-ls.nvim`（非推奨）, `formatter.nvim`
- **重要度**: ⭐⭐⭐（高）

---

### 7. **Linting（静的解析）**

#### **nvim-lint**
- **リポジトリ**: `mfussenegger/nvim-lint`
- **用途**: リンター管理
- **使用場面**: コードの静的解析・警告表示
- **代替**: `null-ls.nvim`（非推奨）
- **重要度**: ⭐⭐⭐（高）

---

### 8. **Util（ユーティリティ）**

#### **persistence.nvim**
- **リポジトリ**: `folke/persistence.nvim`
- **用途**: セッション管理
- **使用場面**: プロジェクトの状態を保存・復元
- **代替**: `auto-session`, `possession.nvim`
- **重要度**: ⭐⭐（中）

#### **plenary.nvim**
- **リポジトリ**: `nvim-lua/plenary.nvim`
- **用途**: 汎用Luaライブラリ（依存関係）
- **使用場面**: Telescopeなど多くのプラグインが依存
- **代替**: なし
- **重要度**: ⭐⭐⭐（依存関係として必須）

---

## 🔍 あなたの環境で既にカスタマイズ済みのプラグイン

以下は`lua/plugins/`で既に明示的に設定されているため、移行時に問題ありません：

- ✅ **barbar.nvim** - bufferline.nvimの代替として既に使用中
- ✅ **blink.cmp** - 補完エンジン（LazyVimはnvim-cmpを使用）
- ✅ **LuaSnip** - スニペットエンジン
- ✅ **conform.nvim** - フォーマッター（カスタム設定済み）
- ✅ **gitsigns.nvim** - Git統合（カスタム設定済み）
- ✅ **lazygit.nvim** - LazyGit統合
- ✅ **lualine.nvim** - ステータスライン（カスタム設定済み）
- ✅ **mason.nvim** - ツール管理（カスタム設定済み）
- ✅ **nvim-lint** - リンター（カスタム設定済み）
- ✅ **nvim-lspconfig** - LSP設定（カスタム設定済み）
- ✅ **nvim-tree.lua** - ファイルエクスプローラー（LazyVimはneo-treeを使用）
- ✅ **nvim-treesitter** - Treesitter（カスタム設定済み）
- ✅ **persistence.nvim** - セッション管理（カスタム設定済み）
- ✅ **telescope.nvim** - ファジーファインダー（カスタム設定済み）
- ✅ **todo-comments.nvim** - TODOコメント（カスタム設定済み）
- ✅ **toggleterm.nvim** - ターミナル管理
- ✅ **trouble.nvim** - 診断UI（カスタム設定済み）
- ✅ **which-key.nvim** - キーマップヘルプ（LazyVimのデフォルトだが依存なし）

---

## 📋 移行時に追加が必要なプラグイン

LazyVimから移行する際、以下のプラグインを明示的に追加する必要があります：

### **必須プラグイン（追加推奨）**

```lua
-- lua/plugins/core.lua
return {
  -- 依存ライブラリ
  { "nvim-lua/plenary.nvim", lazy = true },
  { "MunifTanjim/nui.nvim", lazy = true },

  -- アイコン表示
  {
    "nvim-tree/nvim-web-devicons",  -- mini.iconsの代替
    lazy = true
  },

  -- コメント機能
  {
    "folke/ts-comments.nvim",
    event = "VeryLazy",
    opts = {},
  },

  -- 括弧ペアリング
  {
    "echasnovski/mini.pairs",
    event = "VeryLazy",
    opts = {},
  },

  -- テキストオブジェクト拡張
  {
    "echasnovski/mini.ai",
    event = "VeryLazy",
    opts = {},
  },
}
```

### **オプションプラグイン（必要に応じて）**

```lua
-- lua/plugins/optional.lua
return {
  -- 検索・置換
  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    opts = {},
  },

  -- 高速ナビゲーション
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
  },

  -- UI改善（オプション）
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {},
  },

  -- ダッシュボード・通知など
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {},
  },

  -- Neovim Lua開発支援
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {},
  },
}
```

---

## 🎯 移行戦略の推奨

### ステップ1: 最小構成で移行
まずは必須プラグインのみを追加：
- plenary.nvim
- nvim-web-devicons
- ts-comments.nvim
- mini.pairs
- mini.ai

### ステップ2: 機能確認
基本機能が正常に動作することを確認。

### ステップ3: オプション追加
必要に応じて以下を追加：
- flash.nvim（高速移動が欲しい場合）
- grug-far.nvim（プロジェクト全体置換が必要な場合）
- snacks.nvim（ダッシュボードや通知が欲しい場合）

---

## 📚 参考リンク

- [LazyVim Core Plugins](http://www.lazyvim.org/plugins)
- [LazyVim GitHub - Editor Plugins](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/editor.lua)
- [LazyVim GitHub - UI Plugins](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/ui.lua)
- [LazyVim GitHub - Coding Plugins](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/coding.lua)
- [LazyVim GitHub - LSP Plugins](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/lsp/init.lua)

---

## ✅ まとめ

あなたの環境では既に多くのプラグインをカスタマイズしているため、LazyVimからの移行は比較的スムーズです。

**追加が必要な主要プラグイン:**
- mini.pairs（括弧ペアリング）
- ts-comments.nvim（コメント機能）
- mini.ai（テキストオブジェクト）
- nvim-web-devicons（アイコン）
- plenary.nvim（依存ライブラリ）

これらを追加すれば、LazyVimの主要機能を維持しながらpure lazy.nvimに移行できます。
