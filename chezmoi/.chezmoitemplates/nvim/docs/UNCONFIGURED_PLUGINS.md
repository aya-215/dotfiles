# 設定ファイルが存在しないプラグイン一覧

このドキュメントは、`lazy-lock.json`にはあるが `lua/plugins/` に設定ファイルが存在しないプラグインの一覧です。
これらは**LazyVimのデフォルト設定で自動的に読み込まれているプラグイン**です。

---

## 📊 統計情報

- **総プラグイン数**: 52個
- **設定ファイルあり**: 31個
- **設定ファイルなし（未設定）**: 21個

---

## ❌ 設定ファイルが存在しないプラグイン（21個）

### 1. **LazyVim本体**
- **LazyVim** - LazyVimディストリビューション本体
  - 移行時に削除が必要

---

### 2. **依存ライブラリ（4個）**

これらは他のプラグインが依存しているライブラリです。

#### **plenary.nvim**
- **リポジトリ**: `nvim-lua/plenary.nvim`
- **用途**: 汎用Luaライブラリ
- **依存元**: telescope.nvim, gitsigns.nvimなど多数
- **移行時の対応**: ✅ **明示的に追加が必要**
```lua
{ "nvim-lua/plenary.nvim", lazy = true }
```

#### **nui.nvim**
- **リポジトリ**: `MunifTanjim/nui.nvim`
- **用途**: UI構築用コンポーネントライブラリ
- **依存元**: noice.nvim, neo-treeなど
- **移行時の対応**: ✅ **明示的に追加が必要**
```lua
{ "MunifTanjim/nui.nvim", lazy = true }
```

#### **nvim-web-devicons**
- **リポジトリ**: `nvim-tree/nvim-web-devicons`
- **用途**: ファイルタイプアイコン表示
- **依存元**: nvim-tree, lualine, barbarなど
- **移行時の対応**: ✅ **明示的に追加が必要**
```lua
{ "nvim-web-devicons", lazy = true }
```

#### **friendly-snippets**
- **リポジトリ**: `rafamadriz/friendly-snippets`
- **用途**: 汎用スニペット集
- **依存元**: LuaSnip
- **移行時の対応**: ⚠️ **blink-cmpの設定に既に含まれている可能性あり**

---

### 3. **LSP関連（2個）**

#### **mason-lspconfig.nvim**
- **リポジトリ**: `williamboman/mason-lspconfig.nvim`
- **用途**: masonとnvim-lspconfigの統合
- **移行時の対応**: ✅ **nvim-lspconfig.luaのdependenciesに既に含まれている**
- **状態**: 問題なし

#### **mason-tool-installer.nvim**
- **リポジトリ**: `WhoIsSethDaniel/mason-tool-installer.nvim`
- **用途**: Masonツールの自動インストール
- **移行時の対応**: ⚠️ **オプション - 手動インストールで代替可能**
```lua
-- 自動インストールが欲しい場合
{
  "WhoIsSethDaniel/mason-tool-installer.nvim",
  dependencies = { "mason.nvim" },
  opts = {
    ensure_installed = {
      "stylua",
      "shfmt",
      -- その他必要なツール
    },
  },
}
```

---

### 4. **UI/UX改善（3個）**

#### **noice.nvim**
- **リポジトリ**: `folke/noice.nvim`
- **用途**: メッセージ・コマンドライン・ポップアップのUI改善
- **移行時の対応**: ⭐ **オプション - UI改善が欲しい場合のみ**
```lua
{
  "folke/noice.nvim",
  event = "VeryLazy",
  dependencies = { "MunifTanjim/nui.nvim" },
  opts = {
    lsp = {
      override = {
        ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
        ["vim.lsp.util.stylize_markdown"] = true,
        ["cmp.entry.get_documentation"] = true,
      },
    },
    presets = {
      bottom_search = true,
      command_palette = true,
      long_message_to_split = true,
    },
  },
}
```

#### **which-key.nvim**
- **リポジトリ**: `folke/which-key.nvim`
- **用途**: キーバインド表示ヘルプ
- **移行時の対応**: ✅ **強く推奨 - キーマップ確認に必須**
```lua
{
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {},
}
```

#### **snacks.nvim**
- **リポジトリ**: `folke/snacks.nvim`
- **用途**: ダッシュボード、通知、インデント表示など多機能
- **移行時の対応**: ⚠️ **dashboardプラグインで既に使用中**
- **状態**: dashboard.luaの依存として機能している

---

### 5. **エディタ機能拡張（3個）**

#### **flash.nvim**
- **リポジトリ**: `folke/flash.nvim`
- **用途**: 高速ナビゲーション・ジャンプ機能
- **移行時の対応**: ⭐ **オプション - 高速移動が欲しい場合のみ**
```lua
{
  "folke/flash.nvim",
  event = "VeryLazy",
  opts = {},
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
    { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
  },
}
```

#### **grug-far.nvim**
- **リポジトリ**: `MagicDuck/grug-far.nvim`
- **用途**: プロジェクト全体の検索・置換
- **移行時の対応**: ⭐ **オプション - Telescopeで代替可能**
```lua
{
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  opts = {},
  keys = {
    { "<leader>sr", "<cmd>GrugFar<cr>", desc = "Search and Replace" },
  },
}
```

#### **nvim-treesitter-textobjects**
- **リポジトリ**: `nvim-treesitter/nvim-treesitter-textobjects`
- **用途**: Treesitterベースのテキストオブジェクト
- **移行時の対応**: ✅ **推奨 - 関数/クラス単位の操作に便利**
```lua
-- nvim-treesitter.luaのdependenciesに追加
dependencies = {
  "nvim-treesitter/nvim-treesitter-textobjects",
}
```

---

### 6. **コーディング支援（4個）**

#### **mini.ai**
- **リポジトリ**: `echasnovski/mini.ai`
- **用途**: テキストオブジェクト拡張（引数、関数内など）
- **移行時の対応**: ✅ **推奨 - `vaa`, `vif`などの操作に必須**
```lua
{
  "echasnovski/mini.ai",
  event = "VeryLazy",
  opts = {},
}
```

#### **mini.pairs**
- **リポジトリ**: `echasnovski/mini.pairs`
- **用途**: 括弧の自動ペアリング
- **移行時の対応**: ✅ **必須 - 括弧補完機能**
```lua
{
  "echasnovski/mini.pairs",
  event = "VeryLazy",
  opts = {},
}
```

#### **mini.icons**
- **リポジトリ**: `echasnovski/mini.icons`
- **用途**: アイコン表示（nvim-web-deviconsの代替）
- **移行時の対応**: ❌ **不要 - nvim-web-deviconsを使用**

#### **ts-comments.nvim**
- **リポジトリ**: `folke/ts-comments.nvim`
- **用途**: Treesitterベースのコメント機能
- **移行時の対応**: ✅ **必須 - コメント切り替え機能**
```lua
{
  "folke/ts-comments.nvim",
  event = "VeryLazy",
  opts = {},
}
```

---

### 7. **開発ツール（2個）**

#### **lazydev.nvim**
- **リポジトリ**: `folke/lazydev.nvim`
- **用途**: Neovim Lua開発時のLSP補完
- **移行時の対応**: ⭐ **オプション - Neovim設定編集時に便利**
```lua
{
  "folke/lazydev.nvim",
  ft = "lua",
  opts = {
    library = {
      { path = "luvit-meta/library", words = { "vim%.uv" } },
    },
  },
}
```

#### **render-markdown.nvim**
- **リポジトリ**: `MeanderingProgrammer/render-markdown.nvim`
- **用途**: Markdownのリアルタイムプレビュー
- **移行時の対応**: ⚠️ **markdown.luaで既に設定されている可能性あり**

---

### 8. **カラースキーム（2個）**

#### **tokyonight.nvim**
- **リポジトリ**: `folke/tokyonight.nvim`
- **用途**: TokyoNightカラースキーム
- **移行時の対応**: ⚠️ **colorscheme.luaで既に設定されている可能性あり**

#### **catppuccin**
- **リポジトリ**: `catppuccin/nvim`
- **用途**: Catppuccinカラースキーム
- **移行時の対応**: ⚠️ **colorscheme.luaで既に設定されている可能性あり**

---

### 9. **その他（1個）**

#### **nvim-ts-autotag**
- **リポジトリ**: `windwp/nvim-ts-autotag`
- **用途**: HTML/JSXの閉じタグ自動補完
- **移行時の対応**: ⭐ **Web開発時のみ必要**
```lua
-- nvim-treesitter.luaのdependenciesに追加
dependencies = {
  "windwp/nvim-ts-autotag",
}
```

---

## 📋 移行時の優先度別リスト

### 🔴 必須（必ず追加が必要）

1. **plenary.nvim** - 依存ライブラリ
2. **nvim-web-devicons** - アイコン表示
3. **mini.pairs** - 括弧ペアリング
4. **ts-comments.nvim** - コメント機能
5. **which-key.nvim** - キーバインドヘルプ

### 🟡 推奨（機能向上のため追加推奨）

6. **mini.ai** - テキストオブジェクト拡張
7. **nvim-treesitter-textobjects** - Treesitterテキストオブジェクト
8. **nui.nvim** - UI依存ライブラリ（noiceなど使う場合）

### 🟢 オプション（必要に応じて追加）

9. **flash.nvim** - 高速ナビゲーション
10. **grug-far.nvim** - プロジェクト全体検索置換
11. **noice.nvim** - UI改善
12. **lazydev.nvim** - Neovim Lua開発支援
13. **nvim-ts-autotag** - HTML/JSX開発
14. **mason-tool-installer.nvim** - ツール自動インストール

---

## 📝 移行時の設定テンプレート

### 必須プラグインのまとめ設定

```lua
-- lua/plugins/core.lua
return {
  -- 依存ライブラリ
  { "nvim-lua/plenary.nvim", lazy = true },
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- コーディング支援
  {
    "echasnovski/mini.pairs",
    event = "VeryLazy",
    opts = {},
  },
  {
    "folke/ts-comments.nvim",
    event = "VeryLazy",
    opts = {},
  },
  {
    "echasnovski/mini.ai",
    event = "VeryLazy",
    opts = {},
  },

  -- UI
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },
}
```

---

## ✅ まとめ

### 設定済みプラグイン（31個）
あなたの `lua/plugins/` に既に設定ファイルがあるため、移行時に問題ありません。

### 未設定プラグイン（21個）
- **LazyVim本体**: 1個 → 削除
- **必須追加**: 5個
- **推奨追加**: 3個
- **オプション**: 7個
- **設定済みの可能性**: 5個（colorscheme.lua、markdown.lua、dashboard.luaなどで既に含まれている）

**実質的に追加が必要なプラグイン数: 5〜8個**
