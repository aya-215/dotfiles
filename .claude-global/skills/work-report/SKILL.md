---
name: work-report
description: 週次の社内作業報告用に、対象期間の作業内容をカテゴリ別の箇条書きでまとめる
allowed-tools: Read, Bash, AskUserQuestion
version: 1.1.0
---

# 作業報告まとめ

月・水・金の社内向け作業報告のために、対象期間の作業内容を日報サマリー・gitログ・Rocket Chatから集計し、コピペしやすい箇条書き形式でチャットに出力する。

ファイル保存やgit commitは行わない。KPTや生産性指標などの追加集計もしない（`weekly-report` skillとは目的が異なる）。

**出力モードは実行曜日で2つに分かれる。** データ収集（日報・gitログ・Rocket Chat・Claudeセッション要約の取得）と分類ロジックは両モード共通で、出力形式だけが異なる。

| モード | 実行曜日 | 想定読者 | 出力 |
|---|---|---|---|
| 会議報告モード | 月・水・その他 | 社内会議の参加者 | 具体的な作業の箇条書き（工数なし）。従来どおり。 |
| 週報モード | 金曜 | **全社員** | ①工数まとめ（プロジェクト単位）＋②作業内容（テーマ単位・抽象的）の2セクション |

---

## 対象期間の決定

実行日の曜日によって対象期間の起点が変わる。

| 実行曜日 | 対象期間 |
|---|---|
| 金曜 | 今週月曜 〜 今日 |
| 上記以外（月・水・その他任意の曜日） | 先週の同じ曜日 〜 今日 |

金曜だけ「今週月曜起点」にするのは、先週金曜の作業はすでに前回報告済みのため、今回の報告に紛れ込ませないようにするため。

```bash
today=$(TZ=Asia/Tokyo date +%Y-%m-%d)
dow=$(TZ=Asia/Tokyo date +%u)  # 1=Mon ... 5=Fri, 7=Sun

if [ "$dow" -eq 5 ]; then
  # 金曜: 今週月曜起点
  start_date=$(TZ=Asia/Tokyo date -d "$today -$((dow-1)) days" +%Y-%m-%d)
else
  # それ以外: 先週の同じ曜日起点
  start_date=$(TZ=Asia/Tokyo date -d "$today -7 days" +%Y-%m-%d)
fi
end_date="$today"

echo "対象期間: $start_date 〜 $end_date"
```

土日も対象期間に含める場合はデータ取得を試みるが、作業実績がないのが正常系のため、0件でもエラー扱いにしない。

---

## データソース

個人リポジトリ（`~/.dotfiles`、`~/src/github.com/aya-215/*` など）は報告対象外のため取得しない。

| ソース | 取得先 | 用途 |
|---|---|---|
| 日報の📝サマリー（Work欄） | `aya-215/life` の日報 Issue（open）または `blog/YYYYMMDD.md`（close済み） | 対象期間内の各日からWork欄を抽出 |
| gitログ（AIカテゴリ） | `~/src/github.com/ebase-dev/*`、`/mnt/d/tomcat/webapps/eb-api-extended` | 日報の書き漏れを補完 |
| gitログ（その他カテゴリ） | `/mnt/d/tomcat/webapps/hankyu` | 日報の書き漏れを補完 |
| Rocket Chat（`mori.a-times`） | `mcp__rocketchat__*` ツール | 自分の作業・レビュー作業を対象期間で取得 |
| Claudeセッション要約 | `~/.nb/claude/sessions/YYYY-MM-DD/*.md` | git対象外の「その他」仕事関連作業（hankyu以外）を補完 |

## gh CLI の認証

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
```

以降のコマンド例では `$GH_TOKEN` を省略しているが、すべての `gh` コマンドに `GH_TOKEN="$GH_TOKEN"` を付与すること。

## コマンド例

### 対象期間内の日報Issue一覧を特定する

対象期間の各日付についてループし、Issueまたはblog mdを取得する。

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
    # GitHub検索は日付をトークン分解する（例: 2026-07-07 → 2026/07/07）ため、
    # 月と日が同じ日付では別日のIssueが先頭に来ることがある。
    # 検索は絞り込みに使い、最終選択はタイトル前方一致で決定的に行う。
    issue_num=$(GH_TOKEN="$GH_TOKEN" gh issue list --repo aya-215/life \
      --search "in:title ${d} の記録" \
      --state all --label memo \
      --json number,title \
      --jq "[.[] | select(.title | startswith(\"${d} \"))][0].number" 2>/dev/null)
    if [ -n "$issue_num" ]; then
      echo "=== $d (issue #$issue_num) ==="
      GH_TOKEN="$GH_TOKEN" gh issue view "$issue_num" --repo aya-215/life \
        --json body --jq '.body' 2>/dev/null | \
        sed -n '/^## 📝 サマリー/,/^## /p' | sed '$d'
    else
      echo "=== $d: 日報なし（スキップ） ==="
    fi
  fi
  d=$(date -d "$d +1 day" +%Y-%m-%d)
done
```

> **注意:** `echo "$json_var" | jq` はIssue body内の `\n` がリテラル改行に展開されパースエラーになるため使わない。`printf '%s\n' "$json_var" | jq` を使う。

### gitログ取得（AIカテゴリ対象リポジトリ）

```bash
for repo in ~/src/github.com/ebase-dev/*/; do
  repo_name=$(basename "$repo")
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  echo "=== $repo_name ==="
  git -C "$repo" log --oneline --since="$start_date 00:00" --until="$end_date 23:59" --author="$author_email" 2>/dev/null
done

# eb-api-extended（/mnt/配下。index.lockエラーが出た場合は `rm -f "$repo/.git/index.lock"` してリトライ）
repo=/mnt/d/tomcat/webapps/eb-api-extended
if [ -d "$repo" ]; then
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  echo "=== eb-api-extended ==="
  git -C "$repo" log --oneline --since="$start_date 00:00" --until="$end_date 23:59" --author="$author_email" 2>/dev/null
fi
```

### gitログ取得（その他カテゴリ: hankyu）

```bash
# hankyu（阪急キッチンエール、社内GitBucketリポジトリ。/mnt/配下のためindex.lockエラー時はrm -f "$repo/.git/index.lock"してリトライ）
repo=/mnt/d/tomcat/webapps/hankyu
if [ -d "$repo" ]; then
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  echo "=== hankyu ==="
  git -C "$repo" log --oneline --since="$start_date 00:00" --until="$end_date 23:59" --author="$author_email" 2>/dev/null
fi
```

### Claudeセッション要約の取得（その他カテゴリの補完用）

`hankyu` 以外の「その他（仕事関連・AI以外）」の作業はgitログでは網羅できないため、Claudeセッション要約から拾う。SessionEnd hookが自動生成済みのため手動同期は不要。

```bash
d="$start_date"
while [ "$(date -d "$d" +%s)" -le "$(date -d "$end_date" +%s)" ]; do
  if [ -d ~/.nb/claude/sessions/"$d" ]; then
    for sf in ~/.nb/claude/sessions/"$d"/*.md; do
      proj=$(sed -n 's/^project: //p' "$sf" | head -1)
      echo "=== $d: $proj ==="
      # frontmatter構造がファイルごとに異なる（先頭 --- の数が2〜3個）ため固定閾値では本文を取り逃す。
      # `project:` 行を含むfrontmatterブロックの閉じ `---` 以降を本文とする構造非依存な方式を使う。
      awk '
        seen_project && /^---$/ { body=1; next }
        /^project:/ { seen_project=1 }
        body { print }
      ' "$sf"
    done 2>/dev/null
  fi
  d=$(date -d "$d +1 day" +%Y-%m-%d)
done
```

### Rocket Chat 取得

```bash
# room_id特定
# mcp__rocketchat__list_channels（filter: "mori.a-times"）を使う

# 対象期間の発言取得（oldest/latestで絞り込み、JST→UTC変換に注意）
# mcp__rocketchat__get_channel_history（room_id, oldest: "${start_date}T00:00:00.000Z", latest: "${end_date}T23:59:59.000Z"）
# username = mori.a の発言のみ抽出
# threadIdがあるメッセージは mcp__rocketchat__get_thread_messages でスレッド展開
```

---

## 分類ロジック

出力は「カテゴリ → サブプロジェクト（=リポジトリ名 or 作業テーマ） → 箇条書き」の2階層構造にする。個人リポジトリ（dotfiles・life等）の作業はいずれのカテゴリにも含めない。

### カテゴリ判定

| カテゴリ | 対象 |
|---|---|
| AI | `ebase-dev` 配下の全リポジトリ ＋ `eb-api-extended` |
| その他 | 仕事関連かつAIカテゴリに属さないもの（`hankyu` のgitログ、および日報・Claudeセッション要約から判明したAI以外の仕事関連作業） |

### サブプロジェクト名（表示名マッピング）

原則リポジトリ名をそのまま使う。例外は以下の固定マッピングのみ。新規の例外が発生したらこの表に手動で追記する（自動推測はしない）。

| リポジトリ名 | 表示名 |
|---|---|
| `ebase-portal-chat` | `AI-search` |
| `hankyu` | 阪急キッチンエール |

gitログに紐づかない作業（日報・Claudeセッション要約のみから判明した作業）は、内容から推測できる作業テーマ名をサブプロジェクト名として使う。

### 統合ルール

- 日報サマリー・gitログ・Rocket Chat・Claudeセッション要約から集めた内容のうち、同一の作業を指すものは1項目に統合する（例: 「PR#24作成」という日報の記述と「セッション認証方式変更」というgitログのコミットメッセージが同じ作業を指すなら1つの箇条書きにまとめる）
- 関連する複数の作業（同じ機能・同じ対応方針に紐づくもの）は可能な限り1行にまとめる（例: 「タカショー聞き返し禁止方針への統一」と「タカショーシステムプロンプトのmatch値表記統一」は関連するので1行に統合する）
- 他者のPRに対するレビュー・approve・マージ対応は原則出力しない（他者が自分の作業として報告するため重複になる。自分がメイン担当でレビューが実質的な主作業だった場合はユーザー側で個別調整する前提でよい）
- 活動がないカテゴリ・サブプロジェクトは出力しない
- 個人開発の話題（dotfiles等）が日報やClaudeセッション要約に含まれていても出力に含めない
- 判断に迷う軽微な作業（定型作業・小さな修正など）は出力から除外せず残す。取捨選択は最終的にユーザー側で行う前提のため、迷ったら出す側に倒す

## 出力形式

コピペしやすいプレーンテキストの箇条書きで、チャット上にそのまま出力する。ファイル保存・git commitは行わない。出力形式は実行曜日のモードで異なる。

### 会議報告モード（月・水・その他）

「カテゴリ → サブプロジェクト → 箇条書き」の2階層。工数は付けない。従来どおり。

```
- AI
    - AI-search
        - タカショーゲスト表示機能の追加、ゲスト表示ブランドのユーザー情報取得エラー抑制
        - タカショー聞き返し禁止方針への統一、タカショーシステムプロンプトのmatch値表記統一・表示項目設計
        - タカショープロンプト自動調整ワークフローの設計・実装、汎用化
        - SSEパーサのチャンク境界での商品カード取りこぼし修正
        - e食住なびの未ログイン固定名のゲスト表示フォールバック実装
    - ebase-middleware-mcp
        - spec-keyed-urlsリソースのタイムアウト修正（正規表現バックトラッキング対策）
    - eb-api-extended
        - ミラー環境の最新化
- その他
    - 阪急キッチンエール
        - 商品番号発番機能の画面実装
```

- 各項目はタイトルのみ（説明文・PR番号などの付加情報なし）、名詞句で統一する
- KPTや所感、生産性指標などの追加セクションは作らない（`weekly-report` skillとの違い）

### 週報モード（金曜・全社員向け）

**工数**と**作業内容**は別セクションにする。読者が全社員のため、実装の詳細（PR番号・修正内容の技術的説明）は書かず抽象的にまとめる。

#### 工数のまとめ方（測定ではなく「配分」）

これは各プロジェクトの絶対工数をボトムアップで測る作業**ではない**。1営業日に複数プロジェクトが並行するため、各プロジェクトを独立に見積もって足しても合計は稼働日数に一致しない。**既知の合計（稼働日数 N）をプロジェクトへ配分（パーティション）する**問題として扱う。手順は決定的な部分と非決定的な部分を分離する。

1. **N を決定的にカウントする**：対象期間（今週月〜金）で日報が存在する平日の数を数える。祝日・有給・休みは日報が無いため自然に除外される。

   ```bash
   # 対象期間内で日報（blog md または life Issue）が存在する平日の数を数える
   N=0
   d="$start_date"
   while [ "$(date -d "$d" +%s)" -le "$(date -d "$end_date" +%s)" ]; do
     dow_d=$(date -d "$d" +%u)
     if [ "$dow_d" -le 5 ]; then  # 平日のみ
       blog_file="$LIFE_REPO/blog/$(echo "$d" | tr -d '-').md"
       if [ -f "$blog_file" ]; then
         N=$((N+1))
       else
         issue_num=$(GH_TOKEN="$GH_TOKEN" gh issue list --repo aya-215/life \
           --search "in:title ${d} の記録" --state all --label memo \
           --json number,title \
           --jq "[.[] | select(.title | startswith(\"${d} \"))][0].number" 2>/dev/null)
         [ -n "$issue_num" ] && N=$((N+1))
       fi
     fi
     d=$(date -d "$d +1 day" +%Y-%m-%d)
   done
   echo "稼働日数 N=$N 人日"
   ```

2. **各プロジェクトの相対比率を非決定的に見積もる**：日報の記述量・commit量・チャットの濃さから「今週どのプロジェクトが主軸だったか」を重み付けする。ここはLLMの判断（確率的）。
   - **日報Work欄が薄い/空の日の扱い**：日報Work欄が空でも稼働日はある（Nには含まれる）。その日の重みは commit量・Claudeセッション密度にフォールバックして推定する。日報の記述量だけで重み付けするとWork欄が空の日がゼロ重みになり配分が壊れるため、必ずセッション/gitで裏取りする。
   - **worktreeの二重計上に注意**：`emm-*`・`epc-*` 等はそれぞれ `ebase-middleware-mcp`・`ebase-portal-chat` のworktreeで、同一commitがgitログに重複して出る。工数はリポジトリ単位に統合して数える（worktreeを別プロジェクトとして立てない）。
   - **リポジトリ名の取り違えに注意**：`ebase-middleware-mcp` のcommitはスコープが `eb-api-mcp` と書かれるが、これはデータソースの `eb-api-extended`（別リポジトリ）とは**別物**。スコープ名に引きずられてラベルを間違えない。

3. **合計が厳密に N になるよう決定的に正規化する**：0.5人日刻みで丸め、丸め誤差はその週で最も比率が大きいプロジェクトに吸わせて合計を N に一致させる。「各プロジェクトの工数をLLMに出させて足したら N になっているはず」に頼らない（まず一致しない）。

**レビュー主体の日の配分ポリシー**：ある日の実作業がほぼ他者ブランチのレビュー・実機検証だった場合も、その日は稼働日として N に含め、レビュー対象プロジェクトのバケツへ工数を配分する。ただし■作業内容には出さない（工数と内容は別軸。「他者PRレビューは■作業内容に出さない」統合ルールは維持）。

#### 出力例（N=5 の週）

```
【今週の作業報告】稼働 5人日

■ 工数
- AI-search: 3人日
- eb-api-extended: 0.5人日
- 阪急キッチンエール: 1.5人日
  合計: 5人日

■ 作業内容
- AI-search
    - タカショー向けデモ環境の構築とチューニング
    - ゲスト表示・未ログインユーザー対応
- eb-api-extended
    - ミラー環境の最新化
- 阪急キッチンエール
    - 商品番号発番機能の画面実装
```

- 工数セクションはプロジェクト単位。テーマや個別修正まで分解しない。合計行を必ず付け、稼働日数 N と一致させる
- 作業内容セクションはテーマ単位で抽象化する。「どう実装したか」の技術的詳細・PR番号は書かない
- **週報モードでは「AI／その他」のカテゴリ見出しは付けない**（会議報告モードとの違い）。プロジェクトを最上位に置き、AI系を先・その他を後の順で並べる
- 工数はざっくりでよい（0.5人日刻み）。偽の精度（「0.3人日」等）は出さない

## エラー処理

| 状況 | 対応 |
|---|---|
| 対象期間内の日報が1日も見つからない | gitログ・Rocket Chat・Claudeセッション要約のみで生成を続行 |
| gitリポジトリなし | スキップして他のソースで生成 |
| Rocket Chat発言が0件 | スキップして他のソースで生成 |
| Claudeセッション要約なし（`sessions/YYYY-MM-DD/` が空） | スキップして他のソースで生成 |
| 入力ソースがすべて空 | 「対象期間の作業内容が見つかりません」と表示して終了 |
| 土日にデータがない | 正常系として扱い、警告等は出さない |
