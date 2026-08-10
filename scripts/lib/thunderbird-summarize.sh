#!/bin/bash
# thunderbird-summarize.sh - メールスレッドを claude -p で日報向けに要約する
#
# thunderbird.sh --full-thread の出力（スレッド全体・経緯込み）を入力に取り、
# 「その日に何をしたか」を数行へ落として stdout に出す。
#
# なぜ要約層を挟むか:
#   日報ペイロードには予算があるため、生データを直接載せると1通700文字・当日分のみに
#   切り詰めるしかない。スレッド全体を読ませてから圧縮すれば、「少し返信しただけ」の
#   作業でも経緯を踏まえた記述ができる。入力は数万文字でも出力は数百文字で済む。
#
# クレジットを消費する（claude バイナリを使う）。cron 日報から呼ばれる。
#
# 使用方法:
#   thunderbird-summarize.sh 2026-08-06            # 指定日を要約
#   thunderbird-summarize.sh 2026-08-06 --dry-run  # プロンプトだけ出して claude を呼ばない
#
# 環境変数:
#   TB_SUMMARIZER_MODEL  使用モデル（既定: haiku。長尺は自動で sonnet に回す）
#   CLAUDE_BIN           claude バイナリのパス
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CLAUDE_BIN="${CLAUDE_BIN:-claude}"
# 情報を落とさず整理させるため、圧縮に強い haiku ではなく sonnet を既定にする。
# ※ '[1m]' は角括弧を含むためグロブ展開されないよう必ずクォートして使う。
readonly MODEL="${TB_SUMMARIZER_MODEL:-claude-sonnet-5}"
readonly MODEL_LARGE="${TB_SUMMARIZER_MODEL_LARGE:-claude-sonnet-5[1m]}"
readonly LARGE_THRESHOLD="${LARGE_THRESHOLD:-200000}"
readonly MAX_CHARS="${MAX_CHARS:-200000}"

readonly SYSTEM_PROMPT='あなたは日報作成の補助として、業務メールを整理します。

これは要約ではなく「整理」です。文章を短くすることが目的ではありません。
挨拶・署名・定型表現を落として事実だけを残す、という整形作業をしてください。
情報を落とさないことを最優先し、長さの制約は考えないでください。

出力は箇条書きの本体のみ。前置き・確認・判断理由・区切り線・締めの文を書かない。
「〜を確認しました」「指示に照らし合わせると」のような説明を書き始めてはいけない。
1文字目は必ず「-」または「(」にする。

出力形式:
- スレッドごとに「- 案件名（相手の名前）」の見出し行を作る
- その下に、内容を1事実1行でインデントして並べる（「  - 」で始める）
- 行数の上限はない。事実の数だけ行を作る
- 事務連絡・自動通知・サービス通知のスレッドは出力しない
- 該当が無ければ「(業務メールなし)」のみを出力する

残すもの（省略してはいけない）:
- 決まったこと、合意したこと、変更になったこと
- 日付・期限・数値・金額・バージョン・サーバ名・機能名などの具体的な値
- 誰が何を担当するか、誰に何を依頼したか
- 未解決の論点、保留事項、次のアクション
- 原文が番号付きの議事録などで構造を持つ場合は、その項目をすべて拾う

落とすもの:
- 挨拶、お礼、時候の表現、署名、定型的な締めの文
- 同じ内容の繰り返し（引用の再掲など）

評価・感想・お礼だけのメール（実務上の決定や依頼を含まないもの）は、個別に行を
立てず、そのスレッドの中で1行にまとめる。例:「8/5の顧客対応について越智さん・
西山さんと謝辞を交換」。ただし評価の文中に今後の方針や依頼が含まれる場合は、
その部分は実務情報として別行に残す。

書き方:
- 「★対象期間」が付いたメールが対象日の動き。それ以前のメールは経緯として読み、
  対象日の内容を理解するために必要な範囲で補う
- 原文の表現・用語をそのまま使う。言い換えて抽象化しない
- 憶測で補完しない。書かれていないことは書かない

例:
- シフトオン/AI eBASE（越智さん・彌永さん）
  - 8/5のキックオフMTGの議事が共有された
  - 双方の齟齬により主要要件が漏れていた。Webカタログサイトの車両検索のAIチャット化は必須
  - 既存車両検索と故障診断コード検索の連携は無し
  - 故障診断コード検索は当社案で概ね問題なし。「推奨確認順序」部分は少し簡素になる
  - 要件漏れによりスケジュールを再調整。IDCFクラウドの課金開始は10/1からで変更なし
  - 彌永さんの故障診断コード画面デザイン作成は予定通り8/18目途'

target_date="${1:?usage: thunderbird-summarize.sh <YYYY-MM-DD> [--dry-run]}"
dry_run=0
[ "${2:-}" = "--dry-run" ] && dry_run=1

# スレッド全体（経緯込み）を取得する。空なら要約せず終了する。
# --replied-only: 一度でも返信したスレッドだけを対象にする。他人同士のやりとりを
# CC で受けているだけのスレッドは自分の作業ではないため日報に載せない。
raw="$(bash "$SCRIPT_DIR/thunderbird.sh" \
  --from "$target_date" --to "$target_date" \
  --full-thread --replied-only 2>/dev/null || true)"

if [ -z "$raw" ] || [ "$raw" = "(メールなし)" ]; then
  echo "(業務メールなし)"
  exit 0
fi

# ロケールを固定し文字単位の切り詰めを保証する（cron では LANG 未設定）
export LANG=ja_JP.UTF-8

model="$MODEL"
max_chars="$MAX_CHARS"
if [ "${#raw}" -gt "$LARGE_THRESHOLD" ]; then
  model="$MODEL_LARGE"
  max_chars=950000
fi

# 上限超過時は末尾を残す（新しいメールほど対象日の活動に近い）
if [ "${#raw}" -gt "$max_chars" ]; then
  raw="（※ スレッドが長いため冒頭を省略）
${raw: -$max_chars}"
fi

prompt="対象日: ${target_date}

以下は対象日に動きがあったメールスレッドです。スレッド全体の経緯を読んだうえで、
対象日に自分（森）が行った業務を要約してください。

${raw}"

if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' "$prompt"
  echo "--- (${#prompt} chars, model=$model, dry-run のため claude を呼びません)" >&2
  exit 0
fi

if ! out="$(printf '%s' "$prompt" | "$CLAUDE_BIN" -p --model "$model" \
    --no-session-persistence --setting-sources '' \
    --system-prompt "$SYSTEM_PROMPT" \
    --settings '{"disableAllHooks":true}' 2>/dev/null)"; then
  # 要約に失敗しても日報を落とさない。呼び出し側がそのまま使える文言を返す。
  echo "(メール要約に失敗)"
  exit 0
fi

# 前置きや判断理由が混入することがあるため、箇条書き行だけを機械的に残す
# （プロンプトでの禁止だけでは漏れる。実データ: 2026-08-04 で説明文が出力された）。
# インデントは階層を表すため保持する（潰すと見出しと事実が区別できなくなる）。
# 括弧行は「(業務メールなし)」だけを通す。それ以外の括弧書き（"(以下、返信は無し)" 等の
# 補足コメント）は箇条書きの体裁で混入するため落とす。
out="$(printf '%s' "$out" \
  | sed '/^[[:space:]]*$/d' \
  | grep -E '^[[:space:]]*(-|\(業務メールなし\))' \
  | grep -vE '^[[:space:]]*-+[[:space:]]*$' || true)"
[ -n "$out" ] || out="(業務メールなし)"
printf '%s\n' "$out"
