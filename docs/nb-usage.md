# nb 使用方法ガイド

## 概要

nbネイティブ機能をベースに、fzfでUXを強化したハイブリッド実装。
タスク管理と日報管理に特化。

## ディレクトリ構造

```
~/.nb/
├── tasks/              # タスク管理（フラット構造）
│   └── *.md            # nbが自動命名（20251218150556.todo.md等）
└── daily/              # 日報管理
    ├── .templates/
    │   └── daily.md
    └── YYYY-MM-DD.md
```

## コマンド一覧

### タスク管理

| コマンド | 説明 |
|----------|------|
| `nbt` | タスク追加（対話形式） |
| `nbt "名前" -d DATE -t TAGS` | クイック追加 |
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

#work #high #project/name

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

# 優先度
#high          #medium       #low
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
# 対話形式
nbt

# クイック追加
nbt "レビュー対応" -d 3d -t work,high
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

## 関連ファイル

| ファイル | 用途 |
|----------|------|
| `~/.config/nb/functions.zsh` | 関数定義 |
| `~/.config/zeno/config.yml` | 補完・スニペット設定 |
| `~/.nb/daily/.templates/daily.md` | 日報テンプレート |
