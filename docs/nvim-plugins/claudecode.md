# claudecode.nvim

Neovim で Claude Code（Anthropic の AI コーディングアシスタント）を統合する、最初の本格的な IDE インテグレーション。

設定ファイル: `config/nvim/lua/plugins/claudecode.lua`

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<leader>ac` | Claude の表示切替 |
| `<leader>af` | Claude にフォーカス |
| `<leader>as` | 選択範囲を Claude に送信（ビジュアルモード） |
| `<leader>ab` | 現在のバッファをコンテキストに追加 |
| `<leader>aa` | Diff を承認 |
| `<leader>ad` | Diff を拒否 |
| `<leader>ar` | セッション再開 |
| `<leader>am` | モデル選択 |

---

## 詳細

### 基本操作

- `<leader>ac` — Claude ターミナルの表示切替（`:ClaudeCode`）
- `<leader>af` — Claude にフォーカスを移動（`:ClaudeCodeFocus`）

### セッション管理

- `<leader>ar` — 前回のセッションを再開（`:ClaudeCode --resume`）
- `<leader>aC` — セッションを続行（`:ClaudeCode --continue`）
- `<leader>am` — 使用モデルを選択して起動（`:ClaudeCodeSelectModel`）

### コンテキスト追加

- `<leader>ab` — 現在のバッファをコンテキストに追加（`:ClaudeCodeAdd %`）
- `<leader>as` — ビジュアル選択範囲を Claude に送信（`:ClaudeCodeSend`）
- `<leader>as` — ファイラーで選択中のファイルを追加（`:ClaudeCodeTreeAdd`）
  - 対応ファイラー: NvimTree, neo-tree, oil, minifiles, netrw

### Diff 管理

- `<leader>aa` — Claude の提案した変更を承認（`:ClaudeCodeDiffAccept`）
- `<leader>ad` — Claude の提案した変更を拒否（`:ClaudeCodeDiffDeny`）

---

## 使い方

### 基本フロー

1. `<leader>ac` で右側に Claude ターミナルを開く
2. コードを書きながら必要に応じてコンテキストを追加
   - バッファ追加: `<leader>ab`
   - 選択範囲送信: ビジュアルモードで `<leader>as`
   - ファイラーからファイル追加: `<leader>as`
3. Claude がファイルの変更を提案すると Diff が表示される
4. 変更内容を確認して `<leader>aa`（承認）または `<leader>ad`（拒否）

---

## 注意事項

- **WSL 環境での `<S-CR>` 問題**: snacks_win_opts の `keys = {}` でデフォルトキーを無効化済み（ペースト問題の回避策）
- **Diff ウィンドウ増加問題**: `*(proposed)*` パターンの BufEnter autocmd で不要なウィンドウを自動クローズ（[Issue #155](https://github.com/coder/claudecode.nvim/issues/155) の回避策）
- **自動保存プラグインとの競合**: claudecode の diff バッファ（`buftype="acwrite"`）を自動保存対象から除外すること
- **接続トラブル時**: `:ClaudeCodeStatus` で状態確認、`~/.claude/ide/` のロックファイルを確認
