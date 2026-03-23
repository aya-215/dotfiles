# Phase 3: Neovim設定改善

## 目的

Neovim設定の軽微な問題を修正し、パフォーマンスと可読性を向上させる。

## 対象ファイル一覧

| ファイル | 問題点 | 対応 |
|---|---|---|
| `.config/nvim/lua/plugins/telescope.lua` | fzf-nativeがcmake未インストールでコメントアウト中 | cmake追加して有効化 |
| `.config/nvim/lua/plugins/markdown.lua` | ファイル名が内容と乖離（中身はrender-markdown.nvim） | ファイルリネーム |
| `modules/packages.nix` | cmakeを追加する必要がある | パッケージ追加 |

> **スコープ外:** `vim-auto-save` のsnacks移行は別issueで管理する。

---

## 変更内容

### 1. Telescope fzf-native 有効化

**背景:** `telescope-fzf-native.nvim` はNative C実装でTelescopeのファジー検索を大幅高速化するが、現在 cmake が未インストールのためコメントアウトされている。

**変更ファイル1: `modules/packages.nix`**

cmake を追加する：

```nix
# 修正前（cmakeなし）

# 修正後
cmake
```

**変更ファイル2: `.config/nvim/lua/plugins/telescope.lua`（L158付近）**

コメントアウトを解除してfzf-nativeを有効化：

```lua
-- 修正前（コメントアウト）
-- {
--   'nvim-telescope/telescope-fzf-native.nvim',
--   build = 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release',
-- },

-- 修正後（有効化）
{
  'nvim-telescope/telescope-fzf-native.nvim',
  build = 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release',
},
```

telescope.lua内の `load_extension('fzf')` も合わせて確認・有効化すること。

### 2. markdown.lua のリネーム

**背景:** `markdown.lua` というファイル名だが、中身は `render-markdown.nvim` の設定のみ。ファイル名と内容が乖離していて紛らわしい。

**作業:**

```bash
# ファイルをリネーム
git mv ~/.dotfiles/.config/nvim/lua/plugins/markdown.lua \
        ~/.dotfiles/.config/nvim/lua/plugins/render-markdown.lua
```

> lazy.nvimはプラグイン設定ファイルの名前に依存しないため、リネームしても動作に影響なし。

---

## 作業手順

```bash
# 1. Nixパッケージ追加
nvim ~/.dotfiles/modules/packages.nix
# cmake を追加

# 2. Home Manager 再ビルド
home-manager switch --flake ~/.dotfiles

# 3. telescope.lua のコメントアウト解除
nvim ~/.dotfiles/.config/nvim/lua/plugins/telescope.lua

# 4. markdown.lua をリネーム
git -C ~/.dotfiles mv .config/nvim/lua/plugins/markdown.lua \
                       .config/nvim/lua/plugins/render-markdown.lua

# 5. Neovim起動してプラグインビルド
nvim
# :Lazy build telescope-fzf-native.nvim
```

## 検証

```vim
" Neovim内で確認
:checkhealth telescope
" → fzf: OK と表示されること

:Telescope find_files
" → 正常に動作すること（以前より高速になるはず）

:Lazy
" → render-markdown.nvim が正常にロードされていること
" → telescope-fzf-native.nvim が正常にビルドされていること
```

## 完了後

```bash
git add modules/packages.nix .config/nvim/lua/plugins/telescope.lua
git commit -m "feat: telescope fzf-native を有効化（cmake追加）"

git add .config/nvim/lua/plugins/render-markdown.lua
git commit -m "chore: markdown.lua → render-markdown.lua にリネーム"

git push
```

## 別途 Issue に上げるもの

- `vim-auto-save` の `snacks.autosave` への移行検討
  - 現状の動作に問題はないが、将来的な統一のために検討する
  - ClaudeCode diff除外ロジックの再実装が必要
