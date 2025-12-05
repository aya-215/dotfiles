# Neovim設定の現状

## 移行の概要

**LazyVim → pure lazy.nvim への移行中**

- LazyVimディストリビューションの使用を停止
- lazy.nvimプラグインマネージャーのみを使用
- 全ての設定を明示的に管理する方針

## バックアップ

**場所**: `.config/nvim.backup.20251205_165130/`

移行前の完全な設定が保存されており、必要なプラグイン設定はここから参照・コピー可能。

## 現在のプラグイン構成（最小構成）

### コアプラグイン
1. **colorscheme.lua** - Catppuccin Mocha（透過背景）
2. **nvim-treesitter.lua** - シンタックスハイライト + テキストオブジェクト
3. **mason.lua** - LSP/ツール管理（mason + mason-lspconfig + mason-tool-installer）
4. **nvim-lspconfig.lua** - LSP詳細設定（診断表示、lua_ls設定など）
5. **claudecode.lua** - Claude Code統合
6. **snacks/init.lua** - snacks.nvim（スクロール機能）

### 主要な設定ファイル
- `init.lua` - エントリーポイント（leader キー設定、config読み込み）
- `lua/config/lazy.lua` - lazy.nvim設定（LazyVim依存を削除済み）
- `lua/config/options.lua` - Neovim基本設定
- `lua/config/keymaps.lua` - キーマップ設定

## 今後の追加候補

必要に応じて段階的に追加予定のプラグイン：

### UI/UX
- which-key.nvim - キーバインドヘルプ
- lualine.nvim - ステータスライン
- nvim-tree.lua - ファイルエクスプローラー
- telescope.nvim - ファジーファインダー
- barbar.nvim - バッファライン

### コーディング支援
- mini.pairs - 括弧の自動ペアリング
- ts-comments.nvim - コメント機能
- mini.ai - テキストオブジェクト拡張
- blink.cmp - 補完エンジン

### Git統合
- gitsigns.nvim - Git差分表示
- lazygit.nvim - LazyGit統合

### その他
- persistence.nvim - セッション管理
- toggleterm.nvim - ターミナル管理
- trouble.nvim - 診断UI
- conform.nvim - フォーマッター
- nvim-lint - リンター

## 参考リンク

- [LazyVim公式](https://github.com/LazyVim/LazyVim)
- [lazy.nvim公式](https://github.com/folke/lazy.nvim)
- [移行ガイド](./MIGRATION_GUIDE.md)
- [LazyVimデフォルトプラグイン一覧](./LAZYVIM_DEFAULT_PLUGINS.md)
- [未設定プラグイン一覧](./UNCONFIGURED_PLUGINS.md)

## 作業履歴

### 2025-12-05
- [x] nvimフォルダ全体をバックアップ
- [x] 既存プラグイン設定を全削除
- [x] lazy.luaからLazyVim依存を削除
- [x] lazyvim.jsonを削除
- [x] 最小構成プラグインを追加（6個）
- [x] init.luaでleader キー設定を修正
- [ ] 動作確認