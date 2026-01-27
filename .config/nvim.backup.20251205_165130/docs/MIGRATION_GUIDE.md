# LazyVimからlazy.nvimへの移行ガイド

## 概要

このドキュメントは、現在の設定をLazyVimディストリビューションからlazy.nvimプラグインマネージャーのみを使用する構成に移行するためのガイドです。

## 現状分析

### 現在の構成

- **プラグインマネージャー**: lazy.nvim（既に使用中）
- **設定ディストリビューション**: LazyVim（追加の抽象化レイヤー）

### 設定ファイルの場所

```
.config/nvim/
├── init.lua                    # エントリーポイント
├── lazy-lock.json              # プラグインバージョン固定
├── lazyvim.json                # LazyVim設定（削除予定）
└── lua/
    ├── config/
    │   ├── lazy.lua            # lazy.nvim設定（要変更）
    │   ├── options.lua         # Neovim設定
    │   └── keymaps.lua         # キーマップ設定
    └── plugins/                # カスタムプラグイン設定
```

## LazyVimとlazy.nvimの違い

### lazy.nvim
- Neovim向けの**プラグインマネージャー本体**
- 効率的な遅延読み込み機能
- シンプルな設定記法
- プラグインの依存関係管理

### LazyVim
- lazy.nvimの上に構築された**事前設定済みのNeovim設定フレームワーク**
- デフォルトプラグイン群を自動提供
- 設定の規約とベストプラクティス
- 追加の抽象化レイヤー

## 移行のメリット・デメリット

### メリット
1. **軽量化**: 不要なLazyVimの抽象化レイヤーを削除
2. **制御の向上**: すべてのプラグインを明示的に管理
3. **シンプル化**: 設定の流れが明確になる
4. **カスタマイズ性**: LazyVimの規約に縛られない

### デメリット
1. **初期設定の手間**: LazyVimが自動で提供していたプラグインを手動で設定
2. **メンテナンス**: LazyVimのアップデートの恩恵を受けられない
3. **学習コスト**: LazyVimの規約から離れる必要がある

## 移行手順

### 1. バックアップの作成

```bash
# 現在の設定を完全バックアップ
cp -r .config/nvim .config/nvim.backup
```

### 2. LazyVimが提供するデフォルトプラグインの確認

LazyVimが自動的に提供している主要プラグイン：

- **コア機能**
  - nvim-treesitter（シンタックスハイライト）
  - nvim-lspconfig（LSP設定）
  - mason.nvim（LSP/ツールインストーラー）

- **UI/UX**
  - telescope.nvim（ファジーファインダー）
  - neo-tree.nvim または nvim-tree.lua（ファイルエクスプローラー）
  - which-key.nvim（キーバインドヘルプ）
  - bufferline.nvim（バッファライン）
  - lualine.nvim（ステータスライン）

- **Git統合**
  - gitsigns.nvim（Git差分表示）
  - lazygit.nvim（LazyGit統合）

- **編集支援**
  - nvim-cmp（補完エンジン）
  - LuaSnip（スニペットエンジン）
  - Comment.nvim（コメント切り替え）
  - vim-surround（括弧操作）

これらを明示的に`lua/plugins/`配下に定義する必要があります。

### 3. lazy.luaの書き換え

**現在の設定（`.config/nvim/lua/config/lazy.lua`）:**

```lua
require("lazy").setup({
  spec = {
    -- LazyVimとそのプラグインを追加
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- カスタムプラグインをインポート/上書き
    { import = "plugins" },
  },
  defaults = {
    lazy = true,
    version = false,
  },
  -- その他の設定...
})
```

**移行後の設定:**

```lua
require("lazy").setup({
  spec = {
    -- LazyVimへの依存を削除し、カスタムプラグインのみをロード
    { import = "plugins" },
  },
  defaults = {
    lazy = true,
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true,
    notify = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
```

### 4. 必要なプラグインを明示的に追加

現在暗黙的に読み込まれているLazyVimのコアプラグインを明示的に定義します。

#### 新規作成が必要なファイル例

**`lua/plugins/core.lua`** - 基本プラグイン群:

```lua
return {
  -- Treesitter: シンタックスハイライト
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    -- 設定は既存のnvim-treesitter.luaを参照
  },

  -- LSP設定
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    -- 設定は既存のnvim-lspconfig.luaを参照
  },

  -- Mason: LSP/ツールインストーラー
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    -- 設定は既存のmason.luaを参照
  },
}
```

**`lua/plugins/ui.lua`** - UI関連プラグイン:

```lua
return {
  -- Telescope: ファジーファインダー
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim" },
    -- 設定は既存のtelescope.luaを参照
  },

  -- Which-key: キーバインドヘルプ
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
  },
}
```

**`lua/plugins/editor.lua`** - エディタ拡張:

```lua
return {
  -- Comment.nvim: コメント切り替え
  {
    "numToStr/Comment.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },

  -- vim-surround: 括弧操作
  {
    "tpope/vim-surround",
    event = { "BufReadPost", "BufNewFile" },
  },
}
```

### 5. 既存のプラグイン設定ファイルの確認

以下のファイルは既に詳細な設定があるため、そのまま使用できます：

- `lua/plugins/nvim-treesitter.lua`
- `lua/plugins/nvim-lspconfig.lua`
- `lua/plugins/mason.lua`
- `lua/plugins/telescope.lua`
- `lua/plugins/gitsigns.lua`
- その他すべてのカスタムプラグイン設定

これらのファイルは既に`return { ... }`形式で記述されているため、lazy.nvimが自動的に読み込みます。

### 6. options.luaとkeymaps.luaの確認

これらのファイルはLazyVimのデフォルト設定を上書きしているため、移行後も必要です。

**確認事項:**
- LazyVimの設定への依存がないか確認
- コメント内の参照URLを更新（必要に応じて）

### 7. 削除が必要なファイル

```bash
# LazyVim固有の設定ファイルを削除
rm .config/nvim/lazyvim.json
```

### 8. プラグインの再インストール

```bash
# Neovimを起動してプラグインをインストール
nvim
# Neovim内で
:Lazy sync
```

## 段階的移行（推奨アプローチ）

`$NVIM_APPNAME`環境変数を活用して、新旧設定を並行使用：

### 新しい設定環境の作成

```bash
# 新しい設定ディレクトリを作成
cp -r .config/nvim .config/nvim-pure

# 新しい設定を編集
cd .config/nvim-pure
# 上記の移行手順を実施
```

### エイリアスの設定（PowerShellプロファイルに追加）

```powershell
# 旧設定（LazyVim）
function nvim-old { $env:NVIM_APPNAME = "nvim"; nvim $args; $env:NVIM_APPNAME = $null }

# 新設定（pure lazy.nvim）
function nvim-new { $env:NVIM_APPNAME = "nvim-pure"; nvim $args; $env:NVIM_APPNAME = $null }
```

これにより、リスクなく移行をテストできます。

## 移行後の確認事項

### 1. 起動確認
```bash
nvim
# エラーが出ないか確認
```

### 2. プラグイン状態確認
```vim
:Lazy
# すべてのプラグインが正しくインストールされているか確認
```

### 3. LSP動作確認
```vim
:LspInfo
# LSPサーバーが正しく起動しているか確認
```

### 4. 各機能の動作確認
- [ ] ファイルエクスプローラー（nvim-tree）
- [ ] ファジーファインダー（Telescope）
- [ ] 補完機能（blink-cmp）
- [ ] シンタックスハイライト（Treesitter）
- [ ] Git統合（gitsigns, lazygit）
- [ ] ターミナル（toggleterm）
- [ ] カスタムキーマップ

## トラブルシューティング

### 問題: プラグインが読み込まれない

**原因**: プラグイン設定ファイルの`return`文が不適切

**解決**: すべてのプラグイン設定ファイルが以下の形式になっているか確認

```lua
return {
  {
    "plugin/name",
    -- 設定...
  },
}
```

### 問題: LSPが起動しない

**原因**: mason.nvimまたはnvim-lspconfigの設定不足

**解決**: `lua/plugins/mason.lua`と`lua/plugins/nvim-lspconfig.lua`を確認

### 問題: キーマップが動作しない

**原因**: LazyVimのデフォルトキーマップへの依存

**解決**: `lua/config/keymaps.lua`に必要なキーマップを明示的に追加

## 参考リンク

- [lazy.nvim 公式ドキュメント](https://github.com/folke/lazy.nvim)
- [LazyVim 公式サイト](http://www.lazyvim.org/)
- [Migration Guide - Commentary of Dotfiles](https://coralpink.github.io/commentary/outro/lazy-migration-guide.html)
- [Moving from Packer to Lazy.nvim](https://lyndon.codes/2025/02/05/moving-from-packer-to-lazy-nvim/)
- [lazy.nvim から vim.pack に移行してみた](https://zenn.dev/knsh14/articles/nvim-pack-2025-07-25)

## まとめ

LazyVimからlazy.nvimへの移行は、設定の透明性と制御性を高める良い機会です。段階的移行を活用し、慎重に進めることで、リスクを最小限に抑えられます。

移行後は、すべてのプラグインと設定が明示的に管理されるため、メンテナンスが容易になります。
