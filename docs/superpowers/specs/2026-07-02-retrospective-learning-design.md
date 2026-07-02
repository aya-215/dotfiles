# retrospective学習機構 設計書

作成日: 2026-07-02
ステータス: 承認済み（設計）

## 背景・目的

[cc-retrospective-learner](https://github.com/echolimitless/cc-retrospective-learner)（Zenn記事「Claude Codeに同じバグを3回出すと、自動でルール化される話」）の調査を受け、その中核アイデア（pain/successカウントと閾値ベースの昇格階段）を本環境に取り込む。

目的は2つ:

1. **失敗の繰り返し防止**: Claudeが繰り返す失敗パターンを定量検出し、閾値到達でルール化する
2. **成功パターンの資産化**: うまくいった進め方を検出し、スキル/コマンドに育てる

## 導入方式の判断: そのまま導入ではなく「アイデア統合」

cc-retrospective-learnerをそのままインストールしない。理由は本環境との衝突が4点あるため:

| 衝突点 | 内容 |
|---|---|
| CLAUDE.md追記 | `~/.claude/CLAUDE.md` はdotfilesへのsymlink。セットアップスクリプトの追記はNix/dotfiles管理思想と不整合 |
| メモリ二重化 | 保存先 `~/.claude/projects/*/memory/` はagent-memoryと分裂し、「メモリ操作は必ずagent-memory」ルールと矛盾 |
| 生transcript読み | 601セッションのバックログがあり、既存のSessionEnd要約と処理が二重になる |
| 役割重複 | daily-review・weekly-reportとふりかえり機能が被る |

一方、本環境は既にcc-retrospective-learnerの前半を持っている:

- **Lv.0（セッション記録）**: SessionEnd hook（`scripts/claude-summarize/summarize.sh`）がHaikuで6項目要約を `~/.nb/claude/sessions/YYYY-MM-DD/*.md` に全自動生成済み
- **知識ストア**: agent-memoryスキル（summary-first検索、frontmatter規約）
- **欠けているのは「カウント・閾値昇格・週次横断分析」のみ** — この部分だけを移植する

## 昇格階段（採用する4段階モデル）

| レベル | 置き場所 | 昇格条件 |
|---|---|---|
| Lv.0 | `~/.nb/claude/sessions/`（SessionEnd要約・既存） | 全自動 |
| Lv.1 | agent-memory `memories/feedback/` | 週次分析でパターン検出 |
| Lv.2 | `.claude-global/rules/learned-rules.md` | pain_count >= 3 または success_count >= 3、**ユーザー承認必須** |
| Lv.3 | スキル（`.claude-global/skills/`） | 昇格後 reinforce_count >= 3 で候補提示、**手動判断** |

全ての昇格にユーザーの明示的な承認が必要。自動昇格はしない（本家の設計原則を踏襲）。

## アーキテクチャ / データフロー

```
[既存] SessionEnd hook → Haiku要約 → ~/.nb/claude/sessions/YYYY-MM-DD/*.md（Lv.0・全自動）
                                            │
[新規] /retrospective スキル（週次・ローカル・対話）
        ├─ last_retrospective.txt 以降の要約を収集
        ├─ サブエージェントで分析（親コンテキスト保護）
        │    ├─ 既存 feedback と照合 → pain/success カウント更新
        │    ├─ promoted_to: rules の feedback → reinforce_count 更新
        │    └─ 新パターン検出 → feedback 新規作成（Lv.1）
        ├─ 閾値チェック: count >= 3 → 昇格候補として提示
        └─ ユーザー承認後:
             ├─ rules/learned-rules.md にルール追記（Lv.2）
             ├─ reinforce_count >= 3 のものはスキル化を提案（Lv.3・手動判断）
             └─ dotfiles を commit + push
```

クラウドルーティン（daily-review自動化）はローカルの `~/.claude/` に書き込めないため、カウント更新・昇格はローカルの対話セッションで実行する。

## feedbackメモリ形式（agent-memory拡張）

保存先: `.claude-global/skills/agent-memory/memories/feedback/`（kebab-caseファイル名）

```yaml
---
summary: "設定値未設定(null)時の例外 - 未設定チェック/フォールバック徹底"
created: 2026-07-02
updated: 2026-07-09        # カウント更新時に更新
type: feedback             # 既存メモリと区別
pain_count: 2              # 失敗の繰り返し数
success_count: 0           # 成功の積み重ね数
reinforce_count: 0         # 昇格後の適用実績（promoted_to が null の間は 0 のまま）
promoted_to: null          # null | rules | skill
tags: [error-handling]
scope: global              # global | <プロジェクト名>
---

**Why:** なぜこれが重要か
**How to apply:** いつ・どこで適用すべきか
**出現記録:** 2026-06-25 (ebase-web), 2026-07-01 (dotfiles)
```

設計意図:

- agent-memoryの既存規約（`summary` 必須、summary-first検索、`--no-ignore --hidden`）にそのまま乗る
- `scope` で普遍ルールとプロジェクト固有判断を分離（本家記事の「複数プロジェクト間の記憶混在」対策）
- `出現記録` はカウントの根拠を人間が検証できるようにするため（日付+プロジェクト）

## retrospectiveスキル仕様

配置: `.claude-global/skills/retrospective/SKILL.md`

### トリガー

- `/retrospective` で手動起動（週1回目安）
- description に「ふりかえり」「振り返り」「昇格」等のキーワードを含める

### 処理手順

1. `~/.nb/claude/last_retrospective.txt`（YYYY-MM-DD 1行）から前回実行日を取得。ファイルがなければ初回として14日前を起点にする（バックフィル実験を兼ねる）
2. 前回実行日翌日〜今日の `~/.nb/claude/sessions/*/` 要約ファイルを列挙
3. サブエージェント（tools: Read, Glob, Grep, Write, Edit。**Bashなし**）に以下を渡して分析させる:
   - 対象要約ファイルのパス一覧
   - 既存feedbackの一覧（summary行）
   - 分析指示: (a) 既存feedbackに該当するpain/successの照合とカウント更新 (b) `promoted_to: rules` のfeedbackについて、要約の「フィードバック/承認」セクションに**明確な適用証拠がある場合のみ** reinforce_count をインクリメント (c) 新パターン（2セッション以上で出現）のfeedback新規作成 (d) 昇格候補（count >= 3）と Lv.3 候補（reinforce_count >= 3）の検出
4. サブエージェントの結果サマリーを表示: カウント更新・新規feedback・昇格候補
5. 昇格候補ごとに AskUserQuestion で承認確認
6. 承認分を `rules/learned-rules.md` に追記し、該当feedbackの `promoted_to: rules` を更新
7. Lv.3候補（reinforce_count >= 3）があればスキル化を提案（実装は別セッションで手動判断）
8. dotfilesの変更を commit + push（コミットメッセージ: `feat: retrospective昇格 - <ルール概要>` 等）
9. `last_retrospective.txt` を今日の日付で更新

### カウントの規律

- カウントは1セッション1回まで（同一セッション内の複数回出現は1とカウント）
- reinforce_count は「明確な証拠がある場合のみ」。守られたルールは記録に残りにくいため、証拠なしの推測カウントは禁止
- 新規feedbackは2セッション以上での出現を条件とする（1回きりの偶発をLv.1に上げない）

## 昇格先: rules/learned-rules.md

`.claude-global/rules/learned-rules.md` を新設する。既存の rules/*.md（neovim-style, shell-conventions, git-workflow）と同じ仕組みで全セッションに読み込まれる。

- CLAUDE.md 本体には手を入れない（dotfiles管理の分離を保つ）
- 1ルール = 見出し1つ + 数行。由来のfeedbackファイル名を併記して追跡可能にする
- ルールが増えすぎたら retrospective 実行時に整理を提案（インデックス肥大対策）

## SessionEnd要約テンプレ拡張

`scripts/claude-summarize/summarize.sh` のプロンプト6項目に7項目目を追加:

```
- ## フィードバック/承認 — ユーザーから修正・指摘された点（pain）と、明確に承認された進め方（success）。なければ「なし」
```

- pain/success検出の一次データを明示化する（既存の「ナレッジ候補」だけでは修正・承認の信号が弱い）
- daily-review等の既存要約消費者は6項目を前提にしていないため（セクション追加は後方互換）、影響なし

## 作らないもの（YAGNI）

| 見送り | 理由 |
|---|---|
| 書き込みガードhook（本家のguard-memory-write.sh相当） | まず `tools` 制限のみで運用。サブエージェントの逸脱が実際に起きたら追加 |
| Lv.3自動昇格（スキル/Hook自動生成） | 候補提示まで。スキル化は設計判断を伴うため手動 |
| 毎セッション即時カウント（本家の経路A） | 週次バッチに一本化。要約が既に非同期で溜まるため即時性は不要 |
| セッション開始時の自動ふりかえり（本家everytime方式） | 本家自身が「しんどい」と反省しオンデマンド方式を追加した経緯を踏襲 |

## 効果測定・撤退基準（2週間後、本家方式）

- **継続**: カウントが実際に増えたfeedbackが1つ以上、かつ昇格提案が1回以上発生
- **撤退**: カウントが一度も動かない → retrospectiveスキルを削除。feedbackメモリは通常のagent-memoryメモリとして残す（「仕組みは消えるが学習成果は残る」）

## 変更対象ファイル一覧

| ファイル | 変更 |
|---|---|
| `.claude-global/skills/retrospective/SKILL.md` | 新規: 週次ふりかえりスキル |
| `.claude-global/skills/agent-memory/SKILL.md` | 追記: feedbackメモリ形式の定義 |
| `.claude-global/rules/learned-rules.md` | 新規: 昇格ルールの置き場（初期は空テンプレート） |
| `scripts/claude-summarize/summarize.sh` | 変更: 要約プロンプトに7項目目を追加 |
| `~/.nb/claude/last_retrospective.txt` | 新規（実行時生成、リポジトリ外） |

## 参考

- [cc-retrospective-learner](https://github.com/echolimitless/cc-retrospective-learner)（MIT）
- [Claude Codeに同じバグを3回出すと、自動でルール化される話](https://zenn.dev/nexta_/articles/858e92ee22b4a4)
- 既存設計書: `docs/superpowers/specs/2026-06-09-claude-session-summary-design.md`（SessionEnd要約の設計）
