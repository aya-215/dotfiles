#!/bin/bash
# daily-review-auto.sh - daily-review のフェーズ1（サマリー生成）を無人実行する
#
# cron から毎晩呼び出し、当日分の日報 Issue の「📝 サマリー」セクションを
# Claude Code の headless 実行（claude -p）で自動更新する。
#
# Rocket Chat 履歴は MCP ではなく fetch-rocketchat.sh（REST 直叩き）で
# 事前収集し、整形済みテキストをプロンプトに埋め込む。git log や gh と同じく
# 「スクリプトが収集 → Claude は要約のみ」の流儀に揃える。
#
# 対話ステップ（調子・ルーティン・就寝時刻の質問、メモリ整理）は一切行わない。
# 必要な情報は日報 Issue の 💡 メモに事前に記入しておく運用とする。
#
# 使用方法:
#   cron から: 0 22 * * * /home/aya/.dotfiles/scripts/daily-review/daily-review-auto.sh
#   手動テスト: unset CLAUDECODE && bash ~/.dotfiles/scripts/daily-review/daily-review-auto.sh
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLAUDE_BIN="$HOME/.local/bin/claude"
readonly LOG_FILE="$HOME/.local/log/daily-review-auto.log"
readonly TARGET_DATE="$(TZ=Asia/Tokyo date +%Y-%m-%d)"
# claude を dotfiles 直下で起動する（プロジェクト設定・gh 認証等の解決のため）
readonly PROJECT_DIR="$HOME/.dotfiles"

mkdir -p "$(dirname "$LOG_FILE")"
cd "$PROJECT_DIR" || { echo "エラー: $PROJECT_DIR に移動できません" >&2; exit 1; }

# Rocket Chat 当日履歴を事前収集（失敗してもサマリー生成は続行する）
rocketchat_log="$(bash "$SCRIPT_DIR/fetch-rocketchat.sh" "$TARGET_DATE" 2>/dev/null || echo "(Rocket Chat: 取得失敗)")"

# その日のセッション要約を集約（プロジェクトごとにまとまる。なければプレースホルダ）
# 各要約に「## <project> — <終了時刻>」見出しを付け、frontmatter を除いた本文を連結する。
# ファイル名が <project>-<時刻>-<id>.md なので glob 順でプロジェクトごとにまとまる。
sessions_dir="$HOME/.nb/claude/sessions/$TARGET_DATE"
if compgen -G "$sessions_dir/*.md" > /dev/null; then
  session_summaries=""
  for sf in "$sessions_dir"/*.md; do
    proj="$(sed -n 's/^project: //p' "$sf" | head -1)"
    [ -z "$proj" ] && proj="unknown"
    end_ts="$(sed -n 's/^end: //p' "$sf" | head -1)"
    end_hm="$(TZ=Asia/Tokyo date -d "$end_ts" +%H:%M 2>/dev/null || echo "??:??")"
    # frontmatter を除いた本文を取り出す
    # 実際のファイル構造: --- (空) / --- / フィールド / --- / 本文 （--- が3つ）
    body="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=3{print}' "$sf")"
    session_summaries="${session_summaries}## ${proj} — ${end_hm}

${body}

---

"
  done
else
  session_summaries="(本日のセッション要約なし)"
fi

# Claude へ渡す無人実行用プロンプト。daily-review スキルのフェーズ1のみを実行させる。
read -r -d '' PROMPT <<EOF || true
/daily-review を「無人モード」で実行してください。以下のルールを厳守すること:

【対象日】${TARGET_DATE}（当日分）

【無人モードの制約】
- ユーザーへの質問（AskUserQuestion）は一切行わない。この実行は cron からの無人実行であり、応答できる人間はいない。
- 調子・ルーティン・就寝時刻の確認ステップ（フェーズ1の 8.5〜8.8）は全てスキップする。
- フェーズ2（メモリ整理）は実行しない。
- 「ユーザー確認後に更新」のステップは、確認を取らずにそのまま更新を実行してよい。承認は事前に与えられている。

【実行すること（フェーズ1のサマリー生成のみ）】
1. 当日分（${TARGET_DATE}）の日報 Issue を aya-215/life から特定（gh は aya-215 アカウントのトークンを使用）
2. git ログ（Work: ~/src/github.com/ebase-dev/*, Personal: ~/.dotfiles と ~/src/github.com/aya-215/*）を収集
3. 当日 close された task Issue を収集
4. Rocket Chat の発言は下記【Rocket Chat 当日履歴】を入力として使う（MCP は使わない）
5. Claude 会話履歴は下記【セッション要約】を入力として使う（各セッションが意図/作業内容/結論/編集ファイル/コマンド/ナレッジ候補の6項目で要約済み）。生ログ参照は不要。
6. Work/Personal に分類し、スキルの「サマリー形式」に従って「📝 サマリー」セクションを生成。**Work セクション内では「自分の作業（自分が実装・PR作成・issue作成したもの）」と「レビュー作業（他者のPRをレビュー・approve・マージしたもの）」を区別すること**。セッション要約の「## 意図」冒頭に【レビュー作業】【実装作業】の明記があるので、それに従って分類する。レビューで見た内容を自分の実装成果として記録しないよう注意する。
7. Issue が open なら gh issue edit で body のサマリーセクションを更新。close 済みなら blog md を編集して push。

【Rocket Chat 当日履歴（mori.a-times）】
${rocketchat_log}

【セッション要約（${TARGET_DATE}・プロジェクト別）】
${session_summaries}

【完了後】
- 更新したサマリーの全文を標準出力に出力すること。
EOF

{
  echo "===== [$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] daily-review-auto start (target: ${TARGET_DATE}) ====="
  "$CLAUDE_BIN" -p "$PROMPT" \
    --model opus \
    --dangerously-skip-permissions
  echo "===== [$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] daily-review-auto done ====="
} >> "$LOG_FILE" 2>&1
