---
name: zeno-abbr
description: Use when adding, modifying, or removing abbreviations in zeno.zsh config. Triggers on "abbrを追加", "zeno", "略語", "スニペット追加", "/zeno-abbr".
---

## Overview

zeno.zshのabbr（略語展開）を `config/zeno/config.yml` に安全に追加・変更・削除するスキル。

## 実行フロー

### Step 1: 要件確認

AskUserQuestionで以下を確認:
- 展開したいコマンド（snippet）
- キーワード候補（あれば）
- 行頭展開かパイプ後展開か

### Step 2: 衝突チェック

```bash
# 既存abbrとの重複チェック
grep 'keyword:' ~/.dotfiles/config/zeno/config.yml

# コマンド名との衝突チェック
which <keyword> 2>/dev/null; type <keyword> 2>/dev/null
```

**確認ポイント:**
- 既存キーワードと完全一致していないか
- 既存プレフィックスファミリーのプレフィックスになっていないか（例: `g` は `gc`, `gs`, `gp` を壊す）
- 衝突がある場合はユーザーに代替案を提示

### Step 3: 設計

| フィールド | ルール |
|-----------|--------|
| `name` | 人間が読める説明（`falias`で表示される） |
| `keyword` | 命名規約に従う（下記参照） |
| `snippet` | 展開後のコマンド。ユーザー入力部分は `{{説明}}` |
| `context` | パイプ後やサブコマンド位置で使う場合のみ指定 |

### Step 4: config.ymlに追記

`~/.dotfiles/config/zeno/config.yml` の適切なカテゴリセクションに追記。

**カテゴリ一覧（現行）:**
- Git関連 / エディタ / CLI / gh-dash / バックアップ
- eza (ls replacement) / npm / 勤怠打刻 / tmux / nb関連

新カテゴリが必要なら `# カテゴリ名` コメントを追加。

### Step 5: 動作確認案内

```bash
source ~/.zshrc  # またはターミナル再起動
# キーワード + Space で展開確認
# Ctrl+X Space でスペース入力（展開回避）確認
```

## 命名規約

| パターン | 例 | 用途 |
|----------|-----|------|
| 1文字 | `v`, `c`, `l` | 毎日使う最頻出コマンドのみ |
| 2文字（接頭辞+動作） | `gs`, `gc`, `ta` | コマンドファミリー |
| 3文字以上 | `nbs`, `nbta` | 複合操作 |

**既存プレフィックス:** `g`=git, `t`=tmux, `nb`=notebook, `npm`=npm, `k`=勤怠, `tree`=eza

## チェックリスト

```
□ キーワードが既存abbrと重複していない
□ キーワードが既存コマンド名と衝突しない（意図的でない限り）
□ 既存プレフィックスファミリーを壊さない
□ 適切なカテゴリセクションに配置した
□ nameフィールドが分かりやすい
□ プレースホルダ（{{}}）の説明が適切
□ context指定が必要な場面で指定している
□ YAML構文が正しい（インデント2スペース、拡張子.yml）
```

## よくある間違い

| 間違い | 対策 |
|--------|------|
| パイプ後で使うabbrにcontextを付けない | `context: { lbuffer: '.+\|\s*' }` を指定 |
| 1文字abbrを安易に追加 | 既存ファミリーのプレフィックスと衝突する。本当に毎日使うか確認 |
| snippetに特殊文字を含むのにクォートしない | シングル/ダブルクォートで適切に囲む |
| 新カテゴリをコメントなしで追加 | `# カテゴリ名` のセクションコメント必須 |
