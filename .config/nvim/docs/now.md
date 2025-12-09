# Neovim設定の現状

## 移行の概要

**LazyVim → pure lazy.nvim への移行中**

- LazyVimディストリビューションの使用を停止
- lazy.nvimプラグインマネージャーのみを使用
- 全ての設定を明示的に管理する方針

## バックアップ

**場所**: `.config/nvim.backup.20251205_165130/`

移行前の完全な設定が保存されており、必要なプラグイン設定はここから参照・コピー可能。

## 現在のプラグイン構成

### コアプラグイン
1. **colorscheme.lua** - Catppuccin Mocha（透過背景）
2. **nvim-treesitter.lua** - シンタックスハイライト + テキストオブジェクト
3. **mason.lua** - LSP/ツール管理（mason + mason-lspconfig + mason-tool-installer）
4. **nvim-lspconfig.lua** - LSP詳細設定（診断表示、lua_ls設定など）
5. **claudecode.lua** - Claude Code統合
6. **snacks/** - snacks.nvim（スクロール、ダッシュボード機能）
7. **telescope.lua** - ファジーファインダー（plenary.nvim + telescope-fzf-native.nvim）

### UI/UX
8. **which-key.lua** - キーバインドヘルプ
9. **lualine.lua** - ステータスライン
10. **barbar.lua** - バッファライン
11. **nvim-web-devicons.lua** - アイコン表示
12. **noice.lua** - コマンドライン・通知UI改善
13. **oil.lua** - ファイルエクスプローラー（oil-git-status統合）

### コーディング支援
14. **blink-cmp.lua** - 補完エンジン（LuaSnip + friendly-snippets）
15. **vim-auto-save.lua** - 自動保存
16. **mini-pairs.lua** - 括弧・引用符の自動ペアリング

### Git統合
17. **gitsigns.lua** - Git差分表示

### 主要な設定ファイル
- `init.lua` - エントリーポイント（leader キー設定、config読み込み）
- `lua/config/lazy.lua` - lazy.nvim設定（LazyVim依存を削除済み）
- `lua/config/options.lua` - Neovim基本設定
- `lua/config/keymaps.lua` - キーマップ設定

## 今後の追加候補

必要に応じて段階的に追加予定のプラグイン：

### コーディング支援
- ts-comments.nvim - コメント機能
- mini.ai - テキストオブジェクト拡張

### Git統合
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
- [x] 最小構成プラグインを追加（7個）
- [x] init.luaでleader キー設定を修正
- [x] 動作確認

### 2025-12-08
- [x] UI/UXプラグインを追加（which-key, lualine, barbar, nvim-web-devicons, oil, noice）
- [x] 補完エンジン追加（blink-cmp + LuaSnip + friendly-snippets）
- [x] Git統合追加（gitsigns + oil-git-status）
- [x] 自動保存機能追加（vim-auto-save）
- [x] snacks.nvimの機能拡張（ダッシュボード追加）
- [x] 合計16プラグインの構成に拡張完了
- [x] mini.pairs追加（括弧・引用符の自動ペアリング）
- [x] Visual modeインデント後の選択維持設定追加
- [x] Escキーで検索ハイライト解除設定追加
- [x] 合計17プラグインの構成に拡張完了
