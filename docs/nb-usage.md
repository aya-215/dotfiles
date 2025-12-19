# nb 使用方法ガイド

## 概要

nbネイティブ機能をベースに、fzfでUXを強化したハイブリッド実装。
タスク管理、日報管理、メモ管理に特化。

## ディレクトリ構造

```
~/.nb/
├── tasks/              # タスク管理（フラット構造）
│   └── *.md            # nbが自動命名（20251218150556.todo.md等）
├── notes/              # メモ管理（フラット構造）
│   └── *.md            # nbが自動命名（20251219150556.md等）
├── daily/              # 日報管理
│   ├── .templates/
│   │   └── daily.md
│   └── YYYY-MM-DD.md
└── weekly/             # 週報管理
    └── YYYY-MM-DD-weekly.md  # 週の開始日(月曜)
```

## コマンド一覧

### タスク管理

| コマンド | 説明 |
|----------|------|
| `nbt` | タスク追加（対話形式） |
| `nbt "名前" -d DATE -t TAGS -p PRIORITY -D DESC` | クイック追加 |
| `nbtl [フィルタ]` | 未完了タスク一覧 |
| `nbtd [ID]` | タスク完了（fzf選択可） |
| `nbtu <ID>` | 完了取消 |
| `nbte` | タスク編集（fzf選択） |
| `nbts [検索語]` | タスク検索 |
| `nbtag` | タグで絞り込み |
| `nbtclosed` | 完了タスク一覧 |

### 日報管理

| コマンド | 説明 |
|----------|------|
| `nbd` | 今日の日報作成/編集 |
| `nbds` | 今日の日報表示 |
| `nbde` | 今日の日報編集 |
| `nbdy` | 昨日の日報表示 |
| `nbdl` | 日報一覧（fzf選択） |

日報作成時は以下が自動で挿入される：
- 前日のサマリー（引用形式）
- 未完了タスク一覧（workタグ優先、日付順、優先度順でソート）

### 週報管理

| コマンド | 説明 |
|----------|------|
| `nbw` | 今週の週報を編集 |
| `nbws [日付]` | 週報表示（引数なしで今週） |
| `nbwe [日付]` | 週報編集 |
| `nbwl` | 週報一覧（fzf選択） |

週報の作成は Claude Code で `/weekly-report` を実行。

### メモ管理

| コマンド | 説明 |
|----------|------|
| `nbn` | メモ追加（対話形式） |
| `nbn "タイトル"` | クイック追加（#inbox 自動付与） |
| `nbn "タイトル" -t TAGS` | タグ付きで追加 |
| `nbnl` | メモ一覧（fzf選択→編集） |
| `nbns [検索語]` | メモ検索 |
| `nbntag` | タグで絞り込み |
| `nbninbox` | #inbox メモ一覧（整理用） |

### zeno補完

| パターン | 動作 |
|----------|------|
| `nbtd <Tab>` | タスクID補完 |
| `nbtu <Tab>` | タスクID補完 |
| `nb <Tab>` | ノートブック選択 |

### zenoスニペット

| キーワード | 展開 |
|------------|------|
| `nbta` | `nbt "{{task}}" -d {{due}} -t {{tags}}` |

## タスクファイル形式（nbネイティブ）

```markdown
# [ ] タスク名

## Tags

#work #priority/high #project/name

## Due

2025-12-20

## Description

タスクの詳細説明
```

## タグ設計（階層タグ）

フォルダの代わりに階層タグで分類：

```bash
# コンテキスト
#work          #personal     #study

# プロジェクト（階層タグ）
#work/AI                    # AI関連全般
#work/portal-chat           # 具体的なプロジェクト

# 優先度（対話形式で1/2/3入力可）
#priority/high   #priority/medium   #priority/low
```

## 日付入力形式

`nbt`の`-d`オプションまたは対話入力で使用可能：

| 入力 | 結果 |
|------|------|
| `today` | 今日 |
| `tomorrow` | 明日 |
| `3` または `3d` | 3日後 |
| `1w` | 1週間後 |
| `2025-12-25` | 指定日 |

## 典型的なワークフロー

### 朝のルーティン

```bash
nbd          # 日報作成（未完了タスクが自動表示）
nbtl         # タスク一覧確認
```

### タスク追加

```bash
# 対話形式（タスク名、期限、タグ、優先度、説明を順に入力）
nbt

# クイック追加
nbt "レビュー対応" -d 3d -t work -p 1
nbt "ドキュメント更新" -d tomorrow -t work -p 2 -D "API仕様書の更新"
```

### タスク管理

```bash
nbtl              # 未完了一覧
nbtag             # タグで絞り込み
nbtd              # fzfで選択して完了
nbtd 12           # ID指定で完了
```

### タスク検索

```bash
nbts "keyword"    # キーワード検索
nb tasks:search "#work"  # タグ検索（nbネイティブ）
```

## 日報形式

`nbd`で作成される日報の構造：

```markdown
# YYYY-MM-DD 日報

## 📋 前日のサマリー

> （前日のサマリーが引用表示）

## 📋 未完了タスク

\`\`\`
（workタグ優先、日付順、優先度順でソート済み）
\`\`\`

## 📝 今日のサマリー

### Work

### Personal

## 💡 メモ
```

## メモ管理

### メモのタグ設計

日本語タグにも対応。`nbtag`/`nbntag` では `#` なしで表示される。

```bash
# 種類
#tech      #meeting    #idea      #scratch
#雑務      #電話       #アイデア

# プロジェクト（階層タグ）
#work/project-name

# 未整理
#inbox     # タグなしで作成時に自動付与
```

### メモファイル形式

```markdown
# タイトル

#tech #vim

## Description

メモの内容

## References

- https://example.com
```

## 関連ファイル

| ファイル | 用途 |
|----------|------|
| `~/.config/nb/functions.zsh` | 関数定義 |
| `~/.config/zeno/config.yml` | 補完・スニペット設定 |
| `~/.nb/daily/.templates/daily.md` | 日報テンプレート |
