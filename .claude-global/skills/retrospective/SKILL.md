---
name: retrospective
description: 週次のふりかえり学習。セッション要約からpain/successパターンを検出してfeedbackメモリのカウントを更新し、閾値到達でルール/スキルへの昇格を提案する。「/retrospective」「ふりかえり学習」「昇格チェック」「週次ふりかえり」で起動。
version: 1.2.0
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
- **「要約は書かれた時点のスナップショットであり、対象システムの現況を要約から断定しないこと。
  現況に言及する場合は時点を明示し『現況未確認』と添えること」**（過去の事象が現況として
  報告される事故の防止。手順5で親が検証する前提を揃えるため）

**対象が60件を超える場合は日付でチャンク分割し、逐次実行する。** 1回で全件渡すと読み落としが
起きても返却から判別できない。並列にしないこと（feedbackファイルへの書き込みが競合し、
先行チャンクが更新したカウントを後続が見られず二重計上になる）。分割時は:

- パス一覧をファイルに書き出し（`$SCRATCHPAD/sessions-chunk{N}.txt`）、サブエージェントにReadさせる
  （Bashを持たないため60件のパスを直接promptに貼るより確実）
- 分割前に `comm` 等で**重複ゼロを機械的に検証**してから渡す
- 2回目以降のpromptには、先行チャンクが処理した session_id と確立した規約を明記する
  （ディレクトリ日付とセッションのstart日付は乖離するため、**重複判定は session_id で行う**）

`retrospective-analyzer` が利用できない場合は `general-purpose` で代替し、promptに「Bashは使用禁止。書き込みはfeedbackディレクトリ配下のみ」と `.claude-global/agents/retrospective-analyzer.md` の実行手順を含める。

### 5. 結果サマリーの表示

サブエージェントの返却をユーザーに表示する（対象セッション数・カウント更新・新規feedback・昇格候補・警告）。

**ただし「現況の主張」はそのまま通さない（重要）**

要約は書かれた時点のスナップショットであり、その後に修正された問題も「問題がある」と書かれたまま残る。
サブエージェントの集約報告はさらにそれを圧縮するため、**過去の事象が現況の断定として報告される**。
サブエージェント自身はBashを持たず現況を確認できない立場なので、この検証は親の責務。

報告に「〜が壊れている / 欠落している / 未実装 / 設定が古い」等の**現況の主張**が含まれる場合、
ユーザーに伝える前に一次情報で確認する:

| 主張の型 | 確認方法 |
|---|---|
| スクリプト・設定値の不備 | 該当ファイルを `grep` / `sed -n` で直接読む |
| データの欠落・重複 | 実データを数える（`find`・`grep -c`・python で突合） |
| 機能が無い・未実装 | 該当コード・スキル定義を検索する |
| ツール・フックが動いていない | 設定ファイル（settings.json 等）を読む |

確認コストは通常1コマンド。**確認せずに伝えるのは禁止**。確認できないものは
「YYYY-MM-DD時点の要約の記録（現況未確認）」と明示して伝える。

実例（2026-08-21）: 「summarize.sh の MAX_CHARS 切り詰めで46ファイル欠落」を現況として2回報告したが、
`grep MAX_CHARS summarize.sh` 一発で 24万字＋1Mルーティングに改修済みと判明し、実測では全566要約中の
中略発生は0件だった。同時に「要約の重複ペア」も start のみ共有の別セッションで、重複ではなかった。
→ `feedback/cite-primary-source-not-proxy.md`

### 6. rules昇格の承認と実行

rules昇格候補があれば、**承認を求める前に候補ごとに行き先の振り分け判断を行い、判断結果と根拠を提案に含める**:

**最初に問うこと（振り分けより前）: このルールは決定的に強制できるか？**

強制できるなら `learned-rules.md` ではなく Hook / permission へ回す。ルール文は確率的な補助層であって強制層ではない（公式: 「Claude treats them as context, **not enforced configuration**. To block an action regardless of what Claude decides, use a PreToolUse hook instead.」）。

- 実証データ: `verify-assumptions-with-real-data` は 2026-07-02 に昇格＝常時ロードされているのに、2026-07-14〜27 の2週間で pain 3件。うち2件はセッション要約自身が「学習ルールに反した」と自己記録している。**読ませるだけでは止まらないパターンが実在する**
- 良い実例: `external-actions.md` はルール文＋`settings.json` の `ask` permission の**二段構え**（確率的な補助＋決定的なガード）になっている。これが効く形
- 判定の目安: 「ファイルパス・コマンド名・差分の有無」等で機械判定できる → Hook 向き。「前提が妥当か」「意図が正しいか」等の判断を要する → ルール向き

| パターンの性質 | 行き先 |
|---|---|
| 機械判定できる（パス・コマンド・差分で判定可能） | **Hook / permission を第一候補にする**（ルール昇格より優先） |
| 価値観・構え系（いつでも効く判断原則） | `learned-rules.md` へ昇格 |
| 手順系（「毎回この手順」の定型フロー） | スキル化を提案。**既存スキルがあればそこへの集約を優先**（新規作成しない） |
| 「前後に必ずやる」系の機械的チェック | Hook候補として提示（実装は要相談） |
| 既存のルール・スキル・CLAUDE.mdと重複 | 昇格せず、既存側への集約または reinforce 扱いを提案 |
| ファイル種別・ディレクトリに限定される | `learned-rules.md` ではなく `rules/` の個別ファイル＋`paths:` frontmatter（条件ロード）を検討 |
| プロジェクト固有（scope が global でない） | グローバルルールにしない。scope を明示して行き先を判断 |

重複チェックは必ず行う: `rules/*.md`・CLAUDE.md・既存スキル（`~/.claude/skills/*/SKILL.md` の frontmatter）と突き合わせること。

振り分けの結果 learned-rules.md 行きとなった候補について、AskUserQuestionで承認を確認する。承認されたものについて:

1. `~/.dotfiles/.claude-global/rules/learned-rules.md` の `<!-- ルールはこの下に追記される -->` の下に追記:

```markdown
## <ルールの短いタイトル>

<ルール本文1-3行。「〜すること」形式>

由来: `feedback/<ファイル名>.md`（pain_count: N / 昇格日: YYYY-MM-DD）
```

2. 該当feedbackの `promoted_to` を `rules` に、`updated` を今日に更新する

3. 追記後、learned-rules.md のルール数（`##` 見出しの数）を確認する。15件を超えている場合、または reinforce_count が長期間 0 のままのルールがある場合は、整理（類似ルールの統合・本文の短縮・不要ルールの削除）をユーザーに提案する。削除時は由来feedbackの `promoted_to` を `null` に戻すこと（`learned-rules.md` は frontmatter を持たないため毎セッション無条件で読み込まれる。肥大はコンテキストを圧迫し、公式も「Longer files consume more context and **reduce adherence**」と明記している）

※ `rules/*.md` は `paths:` frontmatter を付けると**該当ファイルを読んだときだけロード**される条件ルールになる（[公式](https://code.claude.com/docs/en/memory.md)）。ファイル種別・ディレクトリに紐づくルールは `learned-rules.md` に混ぜず、個別ファイル＋`paths:` にすること。`learned-rules.md` 自体は全セッションで効かせる価値観系のみを置く前提なので frontmatter なし（無条件ロード）で正しい。

### 7. スキル化候補の提示

以下があれば「スキル化/Hook候補やで」と提示するだけに留める。設計・実装は別セッションで行う（本スキルでは実装しない）:

- `reinforce_count >= 3` の候補（成功の積み重ねによる手順の定型化）
- 昇格後も同じ pain がカウントされ続けている候補（**pain継続** — ルールを読んで守る方式では直らないため、Hook等の機械的強制への格上げを検討する）

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
