---
name: verify-daily-report
description: 生成済み日報を一次情報（セッション要約・gitログ・Rocket Chat・fireログ）と照合し、取りこぼし・根拠不明・誤分類・書式ドリフトを実測する。「/verify-daily-report」「日報の検証」「日報の品質チェック」「日報が合ってるか確認」で起動。retrospective（自分の働き方の学習）とは異なり、日報生成システムの出力品質を対象とする。
version: 1.1.0
---

# verify-daily-report（日報の品質検証）

日報（`life/blog/YYYYMMDD.md` の「📝 サマリー」）を、その日の一次情報と機械的に照合する。
**読み取り専用。日報もセッション要約も書き換えない。**

パイプラインの仕様は [docs/daily-report-pipeline.md](../../../docs/daily-report-pipeline.md) を参照。

## 何を検出するか

| 観点 | 定義 |
|---|---|
| **取りこぼし** | 要約に実体ある作業があるのに日報に無い |
| **根拠不明** | 日報にあるがどの一次情報にも見当たらない |
| **誤分類** | Work/Personal、自分の作業/レビュー作業の振り分け誤り |
| **書式ドリフト** | 件数表記の揺れ、Personalへの件数付与、「なし」断定 |
| **配信障害** | そもそも生成が走らなかった日（fireログで判定） |

## 手順

### 1. 対象期間の決定

```bash
LAST_FILE=~/.nb/claude/last_verify_daily_report.txt
if [ -f "$LAST_FILE" ]; then SINCE=$(cat "$LAST_FILE"); else SINCE=$(TZ=Asia/Tokyo date -d '30 days ago' +%Y-%m-%d); fi
TODAY=$(TZ=Asia/Tokyo date +%Y-%m-%d)
echo "対象期間: $SINCE の翌日 〜 $TODAY"
```

初回は直近30日。ユーザーが期間を指定した場合はそちらを優先する。

### 2. 配信障害の切り分け（内容を見る前に必ず実行）

**空の日報を「品質問題」と誤診しないため、先にfireログを見る。**

```bash
grep -E 'fire failed|giving up|skip:' ~/.local/log/fire-daily-review.log | tail -30
```

- `skip: セッション要約なし` → **正常**（作業していない日）。検証対象から外す
- `fire giving up` → **配信障害**。その日は生成が一度も走っていない。品質評価の対象外とし、障害として別枠で報告する。直前の行で原因も確認し、再生成は [docs/daily-report-pipeline.md](../../../docs/daily-report-pipeline.md) の「生成されなかった日の再生成」に従うと提案する
- 401が単発で出て次のattemptで成功 → 正常（リトライで復旧）

### 3. 照合対象日の列挙と方式の判定

日報の入力方式は2つある。対象日ごとに `~/.nb/claude/daily-slices/<date>/` に切り出し md が1件以上あるか（find で数える）で判定し、表に方式を載せる。fire 自身も切り出し md の件数で方式を切り替えている。payload.txt は旧方式の日にも、`--dry-run` でも書かれるので、方式の判定には使わない。

| 方式 | 判定 | 照合の材料 |
|---|---|---|
| 新方式（日次の切り出し要約） | 切り出し md が1件以上 | payload.txt（その日の入力の記録。要約・git・RC・メールが全部入っている）、切り出し md、`check.json` |
| 旧方式 | 切り出し md が0件 | `~/.nb/claude/sessions/<date>/*.md`、git ログ、Rocket Chat（下記） |

```bash
# 対象日は sessions/ と daily-slices/ の両方から集める
days=$( { find ~/.nb/claude/sessions ~/.nb/claude/daily-slices -mindepth 1 -maxdepth 1 -type d -printf '%f\n'; } | sort -u )
for day in $days; do
  [[ "$day" > "$SINCE" ]] || continue
  blog=~/src/github.com/aya-215/life/blog/$(echo "$day" | tr -d '-').md
  [ -f "$blog" ] || continue
  slice=~/.nb/claude/daily-slices/$day
  # ★ ls ではなく find を使う。名前が隠しファイル（.dotfiles-<sid8>.md）の切り出しがある
  ns=$(find "$slice" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
  if [ "$ns" -gt 0 ]; then
    method=新
    nf=$( [ -f "$slice/.failed" ] && grep -c . "$slice/.failed" || echo 0 )
    n="切り出し${ns}+補完${nf}"
  else
    method=旧
    n=$(find ~/.nb/claude/sessions/"$day" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
  fi
  items=$(sed -n '/📝 サマリー/,/^## [^📝]/p' "$blog" | grep -c '^- ')
  echo "$day 方式=$method sessions=$n items=$items"
done
```

`life` リポジトリは事前に `git pull` しておく。`ls *.md` や glob は隠しファイルを黙って飛ばし、要約数を過少に数える。

#### 新方式のデータの場所

- 区切り: JST の前日 22:10（含む）〜当日 22:10（含まない）。`source ~/.dotfiles/scripts/daily-review/day-window.sh; day_window <date>` が `<since>\t<until>` を返す。この範囲の外の作業は日報に入らないのが正しい
- `payload.txt`: その日の入力の記録（最後に生成したもの）。後から `--dry-run` を走らせると上書きされるため、送信時点の完全な再現とは限らない
- 切り出し md（`daily-slices/<date>/*.md`）: セッションごとの区切り内の要約。切り出し md 自体に補完の印は付かない
- `.failed`: 切り出しに失敗したセッションの sid8 一覧（無ければファイル自体が無い）。その sid8 の全期間の要約は `sessions/**/*-<sid8>.md`（find で探す。glob は隠しファイルを飛ばす）。fire はこれを payload.txt に補完として入れる
- 補完の印: payload.txt の `## <proj> — HH:MM` 見出しの末尾に `（全期間の要約・補完）` が付く（fire が付ける。切り出し md や sessions/ の要約には付かない）。区切り外の内容を含みうる
- `check.json`: 日報投稿後の自動チェック結果（`scripts/daily-review/check-daily-report.sh --date <date> --no-wait` で再生成できる）。キーは `missing[{text,severity 重大|軽微}]`・`unsupported[{text,confidence 高|中|低}]`・`misclassified[{text}]`・`format[str]`・`notify`・`status`（`ok` / `report_missing` / `check_failed`）。`status` が `ok` 以外のときは `message`（理由）も付き、中身は空なので、手動で照合する。`check.json` は検証の叩き台であり、サブエージェントの判定を置き換えない

#### 旧方式でも Rocket Chat を照合に加える

旧方式の日報も Rocket Chat を入力源にしているのに、セッション要約だけで照合すると RC 由来の記述が根拠不明に化ける。対象日ごとに取得してサブエージェントに渡す。

```bash
bash ~/.dotfiles/scripts/lib/rocketchat.sh --from <date> --to <date> --budget 15000
```

新方式の日は payload.txt の「Rocket Chat 当日履歴」節に入っている（`(Rocket Chat: 取得失敗)` と出ていたら、その日の RC 由来は照合できないので確信度を下げる）。

### 4. サブエージェントで並列照合

**1エージェントあたり10日程度**に分割する（それ以上は精度が落ちる）。
各エージェントへのpromptに以下を必ず含める:

- 担当する日付範囲
- データの場所（blog / 新方式なら payload.txt・切り出し md・check.json / 旧方式なら sessions・RC の取得結果 / fireログ）と、日ごとの方式（新・旧）
- **読み取り専用の明示**
- 下記「判定の注意点」全文
- 出力形式（後述）

### 5. 統合して報告

各エージェントの結果をマージし、**実測表 + ユーザーの判断が要る論点** の形で提示する。

## 判定の注意点

エージェントに必ず伝えること。**これを省くと誤検出だらけになる。**

- **薄いセッションの脱落は問題ない。** 調査だけ・編集ファイルなしのセッションが日報に無くても取りこぼしに数えない。**実際に何かを成した作業**のみ計上する
- **根拠不明の判定は慎重に。** git活動・Rocket Chat・メールも日報の入力源。セッション要約に無いだけで「捏造」と断定せず、確信度（高/中/低）を必ず添える。RC由来と推定できるものは確信度・低とする。RC の取得結果（旧方式は `rocketchat.sh`、新方式は payload.txt）と突き合わせてから判定する
- **自分のPRへの指摘対応は「自分の作業」が正しい。** 要約に【レビュー作業】と付いていても、それは要約側のラベルの粗さ。日報側が「自分の作業」に置いていれば**誤分類ではない**
- **Work/Personal は「会社に提出・共有するか」で判定。** コミット先のリポジトリでは判断しない。dotfilesの整備はPersonal、社内雑務や発表準備やタスク整理はWork
- **【旧方式のみ】多日セッションの日付帰属に注意。** 要約は `end` の日でバケット分けされるため、`start` が数日前のセッションが混ざる。前日以前から続く作業が当日の日報に無くても、取りこぼしと即断しない
- **【新方式のみ】範囲の外の作業が書かれていたら根拠不明に数える。** 区切り（前日 22:10〜当日 22:10）の外の作業が日報にあれば、日付帰属の言い訳は効かない。ただし補完の印（payload.txt の見出しの `（全期間の要約・補完）`）が付いた要約は区切り外を含みうるので、その由来と分かる場合は理由を添える

## 出力形式

各日:

```
## YYYY-MM-DD
- 方式: 新 / 旧
- セッション要約数: N / 日報項目数: M
- 取りこぼし: N件
  - <内容>（要約ファイル名）
- 根拠不明: N件
  - <該当記述>（確信度: 高/中/低）
- 誤分類: N件
- 書式: 件数表記 あり/なし/自由記述「<実際の文字列>」 / Personalに件数 あり・なし / 「なし」断定 あり・なし
```

全体:

```
## 全体
- 対象日数: N（うち配信障害 N日は対象外）
- 取りこぼし合計: N件（うち重大: N件）
- 根拠不明合計: N件（確信度・高: N件）
- 誤分類合計: N件
- 書式ドリフト: N日
- 新方式の日数: N / 旧方式の日数: N
- 傾向: <箇条書き3-5点>
```

## 報告後

1. **数字を先に出す。** 感覚ではなく実測を提示してから解釈を述べる
2. **判断が要る論点だけユーザーに投げる。** 「粒度は適切か」「この分類でよいか」は好みの問題なので、実例を2つ並べて選んでもらう形にする
3. **修正はユーザーの承認後。** プロンプト変更（`RemoteTrigger update`）は外部アクションなので、差分を提示して承認を得てから適用する
4. 完了したら実行日を記録する:

```bash
TZ=Asia/Tokyo date +%Y-%m-%d > ~/.nb/claude/last_verify_daily_report.txt
```

## 過去の実測（基準値）

2026-08-17に6〜8月の46日を照合した結果。**現状評価は7〜8月を基準とする**（6月は改善前）。

| 期間 | 取りこぼし | 根拠不明 | 誤分類 |
|---|---|---|---|
| 6月（16日） | 18件（重大5） | 20件 | 7件 |
| 7月（21日） | 3件（軽微のみ） | 0件 | 0件 |
| 8月（9日） | 2件（重大1） | 2件（確信度・低） | 4件（実質0） |

2026-11-10に新方式導入前の旧方式の12日（10-14, 10-19, 10-21〜23, 10-26〜30, 11-05, 11-06）を照合した結果。

| 項目 | 結果 |
|---|---|
| 取りこぼし | 2件（いずれも重大。送信失敗日をまたいだ作業） |
| 根拠不明 | 18件（サンプルを調べた範囲では全件 Rocket Chat で裏付けあり。検証側の盲点で、旧手順が RC を見ていなかった） |
| 誤分類 | 2件（雑務寄りの作業が Personal） |
| 書式ドリフト | 0日 |

10-13・10-16・10-20・11-04 は curl の argv 上限で配信障害になり、修正のうえ再生成済み。この実測が、旧方式への RC 照合の追加と、新方式（日次の切り出し要約）導入の動機になっている。

この水準から悪化していたら、プロンプトか上流（要約・収集）に問題が入った可能性が高い。

**予算は逼迫していない**（実測最大36,424字／上限60,000）。取りこぼしが出ても原因は予算ではないので、
`fire-daily-review.sh` の予算設定を疑う前に生成側を見る。
