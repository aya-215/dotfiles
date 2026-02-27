---
name: nvim-plugin-doc
description: Use when the user wants to create or update a Neovim plugin cheatsheet document. Triggers on "nvimのドキュメント作成", "プラグインのチートシートを作りたい", plugin names with "のドキュメント", or "/nvim-plugin-doc".
allowed-tools: Read, Bash, WebFetch, Write, AskUserQuestion
---

# nvim-plugin-doc

Neovim プラグインのチートシートドキュメントを作成・更新する。

## 引数

$ARGUMENTS

プラグイン名（例: `telescope`, `oil`, `gitsigns`）

## 手順

### Phase 1: 設定ファイルを読む

引数のプラグイン名に対応するファイルを探す：

```
config/nvim/lua/plugins/{name}.lua
```

ファイルが存在しない場合は `AskUserQuestion` で正しいファイル名を確認する。

設定ファイルから以下を抽出する：
- `vim.keymap.set` で設定されているキーマップ（キー・説明・モード）
- `keys` テーブルのキーバインド
- `:` コマンド
- プラグインのリポジトリ名（例: `nvim-telescope/telescope.nvim`）

### Phase 2: テンプレートを読む

```
docs/nvim-plugins/_template.md
```

### Phase 3: GitHub から情報を取得する

設定ファイルから特定したリポジトリ名を使い、以下の順で情報を取得する。
取得できたものをすべて使ってドキュメントを充実させる。

#### 3-1. README を取得

```
https://github.com/{owner}/{repo}/blob/main/README.md
```

`main` で失敗した場合は `master` を試す。それも失敗した場合はスキップ。

README から抽出：
- プラグインの一行説明
- 基本的な使い方・ワークフロー
- 注意事項

#### 3-2. Helpdoc を取得

Vim の `:help` 形式ファイル。README より詳細なキーマップ・コマンド一覧が記載されていることが多い。

まず `doc/` ディレクトリのファイル一覧を確認する：

```
https://github.com/{owner}/{repo}/tree/main/doc
```

存在するファイル（`{plugin}.txt` や `{plugin}.md`）を取得：

```
https://github.com/{owner}/{repo}/blob/main/doc/{filename}
```

Helpdoc から抽出：
- 全キーマップ一覧（デフォルトキーバインド）
- コマンド一覧
- 設定オプション

#### 3-3. デフォルト設定ファイルを取得（任意）

snacks.nvim や blink-cmp のようにデフォルト設定が別ファイルに分離されているプラグインは、
そのファイルもあわせて取得する。README や helpdoc に記載があれば確認する。

### Phase 4: ドキュメント生成

テンプレートの形式に従ってドキュメントを生成する。

**優先順位:**
1. **クイックリファレンス** → 自分の設定ファイル（`plugins/{name}.lua`）のキーマップを優先
2. **詳細セクション** → helpdoc・README から取得したキーマップ・コマンドを網羅
3. **説明** → README の一行説明を使用
4. **使い方** → 複数ステップが必要なワークフローがある場合のみ記載
5. **注意事項** → 特記事項がある場合のみ記載

**生成ルール:**
- セクションは内容がない場合は省略する（テンプレートの指示に従う）
- プラグイン名はリポジトリ上の正式名称を使用
- キーは `` `{key}` `` 形式、コマンドは `` `:{cmd}` `` 形式で統一

### Phase 5: ファイル保存

```
docs/nvim-plugins/{name}.md
```

既存ファイルがある場合は上書きする。

保存後、生成したファイルのパスを表示する。

---

## エラー処理

| 状況 | 対応 |
|------|------|
| プラグイン設定ファイルが見つからない | `AskUserQuestion` でファイル名を確認 |
| リポジトリ名が設定ファイルから特定できない | `AskUserQuestion` でリポジトリ名（owner/repo 形式）を確認 |
| README の取得失敗（main・master 両方） | スキップして helpdoc で補完 |
| `doc/` が存在しない・helpdoc 取得失敗 | スキップして README の情報のみで生成 |
| 情報がほぼ取得できなかった | 設定ファイルの情報だけでドキュメントを生成し、その旨をユーザーに伝える |
