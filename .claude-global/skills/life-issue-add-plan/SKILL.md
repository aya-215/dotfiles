---
name: life-issue-add-plan
description: workタグのissueを自動調査してPlanセクションを生成する。"/life-issue-add-plan"、"life-issue-add-plan"で起動。claude-checkedラベルなしのissueのみ処理。
allowed-tools: Bash, Read, Glob, Grep, Agent
version: 1.1.0
---

# life-issue-add-plan

`aya-215/life` リポジトリの **workタグ** かつ **claude-checkedなし** のissueを全取得し、各issueに対してサブエージェントを並列起動して調査・Planセクション生成を行う。

## 手順

### 1. 対象issueを取得

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null) \
  gh issue list --repo aya-215/life \
  --label work --state open \
  --json number,title,body,labels \
  --limit 100 \
  | jq '[.[] | select(.labels | map(.name) | contains(["claude-checked"]) | not)]'
```

対象が0件なら「処理対象のissueがありません」と表示して終了。

### 2. サブエージェントを並列起動

> ⚠️ **必須**: issueが何件あっても**1回のメッセージで全件同時に**Agentツールを呼び出すこと。
> Agentツールの並列実行に件数制限は存在しない（8件・10件でも同時起動可能）。
> バッチ分割・複数回に分けての起動は禁止。分割すると処理時間が無駄になる。

Agentツールを使い、対象issueの数だけサブエージェントを**1つのメッセージで並列起動**する。

各サブエージェントへのプロンプトは以下のテンプレートに従う：

---

**サブエージェントプロンプトテンプレート:**

```
あなたはBash, Read, Glob, Grepツールを自由に使えます。

以下のGitHub issue (#{{番号}}: {{タイトル}}) を調査してPlanセクションを生成してください。

## issueの内容
{{body全文}}

## 調査指示

1. issueのbodyの`<!-- metadata -->`に`repo:`フィールドがあればそのパスのコードベースを調査する
2. `repo:`がなければ、以下の手順で関連リポジトリを探す：
   a. `ghq list --full-path` でローカルのリポジトリ一覧を取得
   b. issueのタイトル・内容のキーワードと照合して候補を絞る
   c. 関連しそうなリポジトリがあれば調査、なければissueテキストのみで判断
3. 調査結果をもとに以下フォーマットのPlanセクションを生成する

## Planセクションフォーマット

---

## Plan

**Goal:** （1文でこのタスクの目的）

**調査結果:**
- 関連ファイル・関数（パス付き）
- issueテキストから読み取った制約・要件

**実装ステップ:**
- [ ] Step 1: ...
- [ ] Step 2: ...
- [ ] Step 3: ...

**確認事項:**
- [ ] （何が不明か） → （なぜ不明か：issueに記載なし / 調査したが見つからなかった等）
※確認事項は詳細に書くこと。わからないことの方が多いのが普通。

**見積もり:**
- 難易度: Low / Medium / High
- 規模感: （変更ファイル数・影響範囲の概要）

---

## issueの更新方法

以下のスクリプトでPlanセクションをissue本文に挿入する。
`<!-- metadata`コメントの直前に挿入し、既存のPlanセクションがあれば置き換える。

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)

# 現在のbodyを取得
body=$(GH_TOKEN=$GH_TOKEN gh issue view {{番号}} --repo aya-215/life --json body --jq '.body')

# Planセクションのテキスト（上記フォーマットで生成したもの）
plan_section="---

## Plan
..."

# Pythonでbodyを書き換える（metadataの前に挿入、既存Planは置換）
new_body=$(python3 << 'PYEOF'
import sys, re

body = """${body}"""
plan = """${plan_section}"""

# 既存の --- + ## Plan セクションを除去（metadataより前）
body = re.sub(r'\n*---\n+## Plan\b.*?(?=\n<!-- metadata|\Z)', '', body, flags=re.DOTALL)

# metadataコメントの前にPlanを挿入
marker = '<!-- metadata'
if marker in body:
    idx = body.index(marker)
    new_body = body[:idx].rstrip() + '\n\n' + plan + '\n\n' + body[idx:]
else:
    new_body = body.rstrip() + '\n\n' + plan

print(new_body)
PYEOF
)

# issueを更新
GH_TOKEN=$GH_TOKEN gh issue edit {{番号}} --repo aya-215/life --body "$new_body"

# claude-checkedラベルを付与
GH_TOKEN=$GH_TOKEN gh issue edit {{番号}} --repo aya-215/life --add-label "claude-checked"
```

処理完了後、以下を返してください：
- issue番号とタイトル
- 調査したリポジトリ（あれば）
- Goal文
- 成功/失敗のステータス
```

---

### 3. 完了後サマリー表示

全サブエージェント完了後、以下の形式でサマリーを表示：

```
✅ life-issue-add-plan 完了 (N件処理)

✅ #110 sscvectorの検索をmcp化
  → 調査: ~/src/github.com/ebase-dev/ebase-middleware-mcp
  → Goal: sscvectorの検索機能をMCPサーバーとして公開する

❌ #105 登録側のAPIも見ておく
  → エラー: リポジトリが見つからなかった

...
```

## 注意事項

- `claude-checked`ラベルが既についているissueは**必ずスキップ**する
- サブエージェントはAgentツールで**1メッセージ内に全て並列起動**する（件数上限なし。「3件まで」等の制限はない。2回以上に分けることは禁止）
- issueのbodyを更新する際は `<!-- metadata ... -->` を必ず末尾に保持する
- 既存の`## Plan`セクションがある場合は追記せず**置き換える**
