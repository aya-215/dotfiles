---
name: effort-estimate
description: 特定タスク1本にかかった工数（人日）を、日報・gitログ・Rocket Chat・Claudeセッション要約の一次データから逆算して見積もる。「〇〇にどれくらいかかった？」「タカショー対応の工数まとめて」「あの作業の合計工数は」等で使用。work-report（期間まるごとのカテゴリ別報告）とは目的が異なる。
---

# 工数見積もり（effort-estimate）

タスク名を入力に、関連する作業期間を全ソース横断で発見し、並行作業を除外して人日ベースで工数を算出し、調査メモ形式でチャットに出力する。

`work-report`（期間まるごと→カテゴリ別箇条書き）とは目的・集計軸が直交する別スキル。ファイル保存やgit commitは行わない。

## 入力

タスク名のテキストのみ（例「タカショーのデモ環境作成」）。期間は入力しない — スキルが全ソースをグリップ横断して自動で発見する。

## やらないこと

- ファイル保存・git commit（チャット出力のみ。保存はユーザーが指示）
- 期間まるごとのカテゴリ別報告（それは work-report の役割）
- KPT・生産性指標などの追加集計

## 処理フロー

1. タスク名テキストを受け取る
2. **期間発見**: 全ソースをタスクのキーワードでグリップ横断し、ヒットした日付範囲を当たりとして特定
3. **境界確認**: 含める範囲の候補が複数あり一意に決まらないときだけ `AskUserQuestion` で確認。それ以外は広めに取る（迷ったら出す側）
4. **データ収集**: 期間内の日報・gitログ（タイムスタンプ付き）・Claudeセッション（start/end付き）・Rocket Chat を取得
5. **工数算出**: 「工数算出の方法論」に従う
6. **出力**: 調査メモ形式でチャットに出力（保存なし）

## 期間発見

タスクのキーワードで全ソースを横断検索し、ヒットした日付の範囲を作業期間の当たりとする。

```bash
# blog md と Claudeセッション要約からキーワードを含むファイルを探す
KEYWORD="タカショー"  # ← タスク名から抽出したキーワード（複数可: "タカショー\|デモ環境"）
LIFE_REPO=~/src/github.com/aya-215/life

echo "=== blog md ==="
grep -rl "$KEYWORD" "$LIFE_REPO/blog/" 2>/dev/null | sort

echo "=== Claudeセッション要約 ==="
# project が .dotfiles / life などメタ系のファイルと、このスキル自身の過去出力
# （effort-estimate の実行セッション）は除外する。過去の工数結論に循環アンカリングするのを防ぐ。
grep -rl "$KEYWORD" ~/.nb/claude/sessions/ 2>/dev/null | sort | \
  grep -viE 'effort-estimate|/\.dotfiles-|/life-'
```

ヒットした日付の最小〜最大を作業期間とする。前後1日程度は関連作業がにじむため、範囲は広めに取る。

**自己汚染の除外（重要）**: このスキルの過去実行が残したセッション要約には工数の結論（「約6人日」等）が書かれており、キーワードにヒットする。発見段階でこれらを除外しないと、自分の過去結論にアンカリングして再現性を損なう。上記 `grep -v` で `effort-estimate`・dotfiles/life 等のメタ系を弾く。

**タスクの切り出し（狭義/広義の線引き）**: タスク名（例「デモ環境作成」）はリテラルではヒットしないことが多く、ブランド名等でしか引けないため、広義の一連の作業がまとめて釣れる。含める範囲は次の基準で狭義・広義を両方見積もり、出力で並べる：

- **狭義（環境構築のみ）に含める**: そのタスクを「動かす」ために不可避な作業（環境セットアップ・接続設定・データ準備・基本動作の検証・タスク固有のプロンプト/設定）
- **広義（一式）に含める**: 上記に加え、そのタスクを機に作った再利用可能なツール・基盤・ワークフロー、品質の作り込み
- **どちらからも除外**: 別タスク・別機能・他者PRレビュー・個人リポ（下記「並行作業の除外」参照）

境界が一意に決まらず、含める範囲の候補が複数あるときだけ `AskUserQuestion` で確認する。

## データ収集

期間発見で確定した `start_date`〜`end_date` について、以下を取得する。

### gh CLI の認証

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
```
以降の `gh` コマンドには `GH_TOKEN="$GH_TOKEN"` を付与する。

### 日報サマリー（一次ソース・工数算出の主軸）

対象期間の各日について blog md（`blog/YYYYMMDD.md`）またはopen Issueから 📝 サマリーの Work欄を抽出する。

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
LIFE_REPO=~/src/github.com/aya-215/life
d="$start_date"
while [ "$(date -d "$d" +%s)" -le "$(date -d "$end_date" +%s)" ]; do
  blog_file="$LIFE_REPO/blog/$(echo "$d" | tr -d '-').md"
  if [ -f "$blog_file" ]; then
    echo "=== $d (blog md) ==="
    sed -n '/^## 📝 サマリー/,/^## /p' "$blog_file" | sed '$d'
  else
    issue_num=$(GH_TOKEN="$GH_TOKEN" gh issue list --repo aya-215/life \
      --search "in:title ${d} の記録" --state all --label memo \
      --json number --jq '.[0].number' 2>/dev/null)
    if [ -n "$issue_num" ]; then
      echo "=== $d (issue #$issue_num) ==="
      GH_TOKEN="$GH_TOKEN" gh issue view "$issue_num" --repo aya-215/life \
        --json body --jq '.body' 2>/dev/null | \
        sed -n '/^## 📝 サマリー/,/^## /p' | sed '$d'
    fi
  fi
  d=$(date -d "$d +1 day" +%Y-%m-%d)
done
```

### gitログ（タイムスタンプ付き・作業窓クロスチェック用）

コミット時刻で「その日の作業窓の下限」を裏取りする。対象タスクに関係するリポジトリを選んで実行する。

**worktree重複に注意**: `~/src/github.com/ebase-dev/` 配下には本体リポジトリと並んで worktree（`epc-feat-*`・`emm-feat-*` 等）が同居しており、`--all` で回すと同一コミットが複数リポジトリ分ダブって出る。人日ベース主軸なら最終値は汚染されないが、**コミット数を数える運用はしないこと**（時刻の分布＝作業窓の裏取りにのみ使う）。

```bash
# ebase-dev配下 + eb-api-extended + hankyu
for repo in ~/src/github.com/ebase-dev/*/ /mnt/d/tomcat/webapps/eb-api-extended /mnt/d/tomcat/webapps/hankyu; do
  [ -d "$repo" ] || continue
  rm -f "$repo/.git/index.lock" 2>/dev/null
  repo_name=$(basename "$repo")
  ae=$(git -C "$repo" config user.email 2>/dev/null)
  echo "=== $repo_name ==="
  git -C "$repo" log --pretty="%ad %s" --date=format-local:'%m/%d %H:%M' \
    --since="$start_date 00:00" --until="$end_date 23:59" --author="$ae" --all 2>/dev/null | sort
done
```

### Claudeセッション要約（start/end付き・作業窓クロスチェック用）

各セッションの frontmatter に `session_id`/`start`/`end` がある。**start/endは合算に使わず、その日の作業窓の裏取りにのみ使う**（後述の方法論を厳守）。

同一 `session_id` の要約が同日に複数ファイル存在することがある（セッション継続中に複数回スナップショットが取られるため）。end 時刻だけが少しずつ違う同一 session_id は1セッションとして扱い、重複計上しないこと。

```bash
d="$start_date"
while [ "$(date -d "$d" +%s)" -le "$(date -d "$end_date" +%s)" ]; do
  if [ -d ~/.nb/claude/sessions/"$d" ]; then
    for sf in ~/.nb/claude/sessions/"$d"/*.md; do
      proj=$(grep -m1 '^project:' "$sf" | sed 's/project: //')
      sid=$(grep -m1 'session_id:' "$sf" | sed 's/.*session_id: //')
      st=$(grep -m1 '^start:' "$sf" | sed 's/start: //')
      en=$(grep -m1 '^end:' "$sf" | sed 's/end: //')
      echo "=== $d $proj sid=${sid:0:8} start=$st end=$en ==="
      awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=3{print}' "$sf"
    done 2>/dev/null
  fi
  d=$(date -d "$d +1 day" +%Y-%m-%d)
done
```

### Rocket Chat（つまずき・進捗の実況）

`mcp__rocketchat__list_channels`（filter: "mori.a-times"）で room_id を特定し、`mcp__rocketchat__get_channel_history`（oldest/latest でJST→UTC変換に注意）で期間内を取得。username=mori.a の発言のみ、タスクのキーワードに関連するものを抽出する。出力が大きい場合はサブエージェントに抽出させる。

**タイムアウト時は即スキップ**: `list_channels` 等が無応答の場合、待たずにこのソースを飛ばして他ソースで算出する（Rocket Chatは「つまずきの実況」の補助ソースであり、無くても人日算出は成立する）。

## 工数算出の方法論

セッション時間の単純合算は破綻するため、以下を必ず守る。

1. **人日ベースが主軸**: 日報の申告を一次ソースにする。各稼働日について「その日のうち対象タスクが占めた割合（0〜1人日）」を見積もる。

2. **セッションの start/end は合算しない**: 同一 session_id の重複要約・複数日またぎのコンテキストにより、合算すると実作業時間の2〜3倍に膨らむ。commit タイムスタンプとセッション時刻は「その日の作業窓の下限」を裏取りするクロスチェックにだけ使う。

3. **並行作業を各日から除外**: 対象タスクに無関係な別リポジトリ・別機能・個人リポの作業を各日の人日から差し引く。ここが精度を決める肝。除外例と採用例を、対象タスクの内容から具体的に判断する。

4. **レンジで出す**: 「37.5h」のような偽精度は禁止。「約6人日」「1人日 ≒ 7.5h 換算」のように推定であることを明示する。

5. **桁のサニティチェック**: 肌感とオーダーがずれたら二重計上を疑う（例: 一連の弧が肌感5〜6人日なのに30hや150hが出たら方法を疑う）。

## 出力形式（調査メモ・デフォルト）

チャット上に以下の構成で出力する。ファイル保存はしない。

- **合計工数（レンジ）** を先頭に置く（例「約6人日（≒45〜48時間）」）
- **作業カテゴリ別の内訳** ＋各人日（表形式）
- **日別クロスチェック表**（作業窓 JST・並行除外作業）
- **前提の明記**（推定である旨・除外したもの・1人日=7.5h換算）
- 範囲の線引きで工数が振れる場合は、狭い解釈と広い解釈の両方の人日を示す

上司報告用の簡潔版が必要なら、ユーザーの追加指示（「上司報告用にして」等）を受けて、詳細版からカジュアル表現・派生作業・Markdown記法を削って整形する。

## エラー処理

| 状況 | 対応 |
|---|---|
| タスク名でヒットするデータが1件もない | 「該当する作業が見つかりません」と表示して終了 |
| gitリポジトリなし | スキップして他ソースで算出 |
| Rocket Chat 発言0件 | スキップして他ソースで算出 |
| Rocket Chat ツール無応答・タイムアウト | 待たずに即スキップして他ソースで算出 |
| 日報が期間内に1日もない | gitログ・セッション要約のみで算出（精度低下を明記） |
