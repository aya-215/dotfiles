---
name: retrospective
description: 週次のふりかえり学習。セッション要約からpain/successパターンを検出してfeedbackメモリのカウントを更新し、閾値到達でルール/スキルへの昇格を提案する。「/retrospective」「ふりかえり学習」「昇格チェック」「週次ふりかえり」で起動。
version: 1.1.0
---

# retrospective（週次ふりかえり学習）

SessionEnd要約（`~/.nb/claude/sessions/`）を一次資料として、繰り返される失敗（pain）と成功（success）を定量検出し、閾値到達でルール化・スキル化を提案する。

**全ての昇格にユーザーの明示的な承認が必要。自動昇格はしない。**

## 手順

### 1. 対象期間の決定

```bash
LAST_FILE=~/.nb/claude/last_retrospective.txt
if [ -f "$LAST_FILE" ]; then SINCE=$(cat "$LAST_FILE"); else SINCE=$(TZ=Asia/Tokyo date -d '14 days ago' +%Y-%m-%d); fi
TODAY=$(TZ=Asia/Tokyo date +%Y-%m-%d)
echo "対象期間: $SINCE の翌日 〜 $TODAY"
```

初回（ファイルなし）は直近14日のバックフィルになる。

### 2. 対象要約ファイルの列挙

```bash
for d in ~/.nb/claude/sessions/*/; do
  day=$(basename "$d")
  [[ "$day" > "$SINCE" ]] && find "$d" -maxdepth 1 -name '*.md'
done
```

0件なら「ふりかえり対象なし」と表示して終了する（last_retrospective.txt は更新する）。

### 3. feedbackディレクトリの準備

```bash
mkdir -p ~/.claude/skills/agent-memory/memories/feedback
```

### 4. サブエージェント分析

Agentツールで `subagent_type: "retrospective-analyzer"` をフォアグラウンドで起動する（`run_in_background` は指定しない）。promptに以下を含める:

- 手順2で列挙した要約ファイルのパス一覧（全パスを明記）
- feedbackディレクトリ: `~/.claude/skills/agent-memory/memories/feedback/`
- 今日の日付（`$TODAY`）

`retrospective-analyzer` が利用できない場合は `general-purpose` で代替し、promptに「Bashは使用禁止。書き込みはfeedbackディレクトリ配下のみ」と `.claude-global/agents/retrospective-analyzer.md` の実行手順を含める。

### 5. 結果サマリーの表示

サブエージェントの返却をそのままユーザーに表示する（対象セッション数・カウント更新・新規feedback・昇格候補・警告）。

### 6. rules昇格の承認と実行

rules昇格候補があれば、候補ごとにAskUserQuestionで承認を確認する。承認されたものについて:

1. `~/.dotfiles/.claude-global/rules/learned-rules.md` の `<!-- ルールはこの下に追記される -->` の下に追記:

```markdown
## <ルールの短いタイトル>

<ルール本文1-3行。「〜すること」形式>

由来: `feedback/<ファイル名>.md`（pain_count: N / 昇格日: YYYY-MM-DD）
```

2. 該当feedbackの `promoted_to` を `rules` に、`updated` を今日に更新する

3. 追記後、learned-rules.md のルール数（`##` 見出しの数）を確認する。15件を超えている場合、または reinforce_count が長期間 0 のままのルールがある場合は、整理（類似ルールの統合・本文の短縮・不要ルールの削除）をユーザーに提案する。削除時は由来feedbackの `promoted_to` を `null` に戻すこと（ルールは毎セッション読み込まれるため、肥大はコンテキストを圧迫する）

### 7. スキル化候補の提示

`reinforce_count >= 3` の候補があれば「スキル化候補やで」と提示するだけに留める。スキル化の設計・実装は別セッションで行う（本スキルでは実装しない）。

### 8. コミットとプッシュ

learned-rules.md に変更があった場合のみ:

```bash
git -C ~/.dotfiles add .claude-global/rules/learned-rules.md
git -C ~/.dotfiles commit -m "feat: retrospective昇格 - <ルール概要>"
git -C ~/.dotfiles push
```

feedbackメモリ（memories/配下）はgitignore対象なのでコミットしない。

### 9. 実行日の記録

```bash
echo "$TODAY" > ~/.nb/claude/last_retrospective.txt
```

## カウント規律（サブエージェントと共有する原則）

- カウントは1セッション1回まで
- reinforce_countは要約に明確な証拠がある場合のみ（推測での水増し禁止）
- 新規feedbackは2セッション以上での出現が条件（1回きりの偶発をLv.1に上げない）

## 効果測定（導入2週間後）

- 継続: カウントが増えたfeedbackが1つ以上、かつ昇格提案が1回以上
- 撤退: カウントが一度も動かない → 本スキルを削除（feedbackメモリは通常メモリとして残す）
