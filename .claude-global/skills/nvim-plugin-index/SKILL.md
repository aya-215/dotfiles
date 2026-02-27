---
name: nvim-plugin-index
description: Use when the user wants to update or regenerate the Neovim plugin INDEX.md from docs/nvim-plugins/. Triggers on "INDEX.mdを更新", "プラグイン一覧を更新", "nvim-plugin-index", or "/nvim-plugin-index".
allowed-tools: Read, Bash, Glob, Write
---

# nvim-plugin-index

`docs/nvim-plugins/` フォルダのプラグインドキュメントを読み込み、`INDEX.md` を最新の状態に更新する。

## 手順

### Phase 1: ファイル一覧を取得

以下のディレクトリにある `.md` ファイルを列挙する（`_template.md` と `INDEX.md` は除外）：

```
docs/nvim-plugins/
```

```bash
ls /home/aya/.dotfiles/docs/nvim-plugins/*.md | grep -v '_template\|INDEX'
```

### Phase 2: 各ファイルから情報を抽出

**全ファイルを並列で読み込む**（Explore サブエージェントを使う）。

各ファイルから抽出する情報：
- **プラグイン名**: `# ` で始まる最初の見出し
- **一行説明**: 見出し直後の説明文（`設定ファイル:` の行より前）
- **クイックリファレンスのキーマップ**: `## クイックリファレンス` セクションのテーブル全行

### Phase 3: カテゴリ分類

抽出したプラグインを以下のカテゴリに分類する。
新しいプラグインが追加された場合は、名前・機能から適切なカテゴリを判断して配置する。

| カテゴリ | 対象プラグイン（例） |
|---------|-------------------|
| **Git** | gitsigns, lazygit, diffview, octo |
| **ファイル操作** | oil, neo-tree |
| **検索・ナビゲーション** | telescope, flash |
| **LSP・補完** | nvim-lspconfig, blink-cmp, mason, conform |
| **UI・表示** | lualine, barbar, noice, colorscheme, nvim-web-devicons, undo-glow |
| **エディタ操作・ユーティリティ** | nvim-treesitter, mini-pairs, smart-splits, which-key, persistence, vim-auto-save, neoconf, claudecode |

**新規プラグインの分類ルール:**
- Git 操作・差分・blame → Git
- ファイルブラウザ・エクスプローラー → ファイル操作
- 検索・ジャンプ・ナビゲーション → 検索・ナビゲーション
- LSP・補完・フォーマット・リント → LSP・補完
- ステータスライン・カラースキーム・通知・アイコン → UI・表示
- テキスト操作・ウィンドウ管理・設定管理・AI → エディタ操作・ユーティリティ

### Phase 4: INDEX.md を生成

以下の形式で `docs/nvim-plugins/INDEX.md` を**上書き**保存する。

**フォーマット:**

```markdown
# Neovim プラグイン INDEX

> 各プラグインの詳細は同フォルダ内の `{name}.md` を参照

---

## {カテゴリ名}

### [{プラグイン名}]({ファイル名}.md)
{一行説明}

- `{キー}`: {説明}
- `{キー}`: {説明}
...

```

**生成ルール:**
- プラグイン名はリンク形式 `[{名前}]({ファイル名}.md)` にする
  - ファイル名は `docs/nvim-plugins/` のファイル名から `.md` を除いたもの（例: `gitsigns.md` → `gitsigns`）
- キーマップは **クイックリファレンスから 3〜5 個** を選ぶ（重要度が高いものを優先）
  - キーマップがないプラグイン（lualine など）は「キーマップなし（自動動作）」と記載
- キーマップ形式: `` - `{キー}`: {説明} ``（箇条書き）
- カテゴリの順序は上記テーブルの順番を維持する

### Phase 5: 完了報告

保存完了後、以下を報告する：
- 更新した `INDEX.md` のパス
- 追加・削除されたプラグインがあれば一覧

---

## エラー処理

| 状況 | 対応 |
|------|------|
| 新規プラグインのカテゴリが判断できない | AskUserQuestion でカテゴリを確認 |
| クイックリファレンスセクションがない | 詳細セクションの最重要キーマップを使用 |
| キーマップが一切ない | 「キーマップなし（自動動作）」と記載 |
