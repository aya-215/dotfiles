# nvim-treesitter master → feat/stable 移行メモ

## 背景

Neovim 0.12 で `vim.treesitter.query` の `iter_matches` コールバックの `match` 引数の型が変わった。

- **0.11 以前**: `match[capture_id]` → `TSNode`
- **0.12 以降**: `match[capture_id]` → `TSNode[]`（配列）

nvim-treesitter の `master` ブランチは 2025-05 にアーカイブ済みで、この変更に追従しない。
`feat/stable` ブランチが Nvim 0.12 対応の後継。

## 現状の一時対処

`~/.local/share/nvim/lazy/nvim-treesitter/lua/nvim-treesitter/query_predicates.lua` を直接パッチしている。
Lazy で nvim-treesitter を update するたびにパッチが消えるので注意。

## feat/stable への移行手順

### 1. lazy.nvim の設定変更

`config/nvim/lua/plugins/nvim-treesitter.lua` を修正：

```lua
-- 変更前
"nvim-treesitter/nvim-treesitter",
build = ":TSUpdate",
...
main = "nvim-treesitter.configs",
opts = { ... }

-- 変更後
"nvim-treesitter/nvim-treesitter",
branch = "feat/stable",
build = ":TSUpdate",
...
-- main = "nvim-treesitter.configs" を削除（feat/stable にはこのモジュールがない）
config = function(_, opts)
  require("nvim-treesitter").setup(opts)
end,
```

### 2. opts の変更点

`feat/stable` では設定キーが変わっている可能性がある。
移行後に `:checkhealth nvim-treesitter` で確認すること。

削除された設定（要確認）:
- `highlight.additional_vim_regex_highlighting`
- `incremental_selection`（keymapに移動した可能性）

### 3. nvim-treesitter-textobjects の互換性確認

`feat/stable` で `nvim-treesitter-textobjects` が動くか確認が必要。
動かない場合は textobjects の設定を切り離す。

### 4. lazy-lock.json の更新

```json
"nvim-treesitter": { "branch": "feat/stable", "commit": "78e5944396f57b98109a108a7d05533fe10b176d" }
```

### 5. 動作確認

```vim
:Lazy update nvim-treesitter
:TSUpdate
:checkhealth nvim-treesitter
```

## 参考

- feat/stable の最新コミット（2026-04-01 時点）: `78e59443` (`feat!: drop support for Nvim 0.11`)
- feat/stable では `lua/nvim-treesitter/query_predicates.lua` が存在しない（Nvim 本体に統合）
