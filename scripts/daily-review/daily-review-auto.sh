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
1. claude-nb-sync.py を実行して最新の会話を同期
2. 当日分（${TARGET_DATE}）の日報 Issue を aya-215/life から特定（gh は aya-215 アカウントのトークンを使用）
3. git ログ（Work: ~/src/github.com/ebase-dev/*, Personal: ~/.dotfiles と ~/src/github.com/aya-215/*）を収集
4. 当日 close された task Issue を収集
5. Rocket Chat の発言は下記【Rocket Chat 当日履歴】を入力として使う（MCP は使わない）
6. Claude 会話履歴（~/.nb/claude/${TARGET_DATE}.md）を収集
7. Work/Personal に分類し、スキルの「サマリー形式」に従って「📝 サマリー」セクションを生成
8. Issue が open なら gh issue edit で body のサマリーセクションを更新。close 済みなら blog md を編集して push。

【Rocket Chat 当日履歴（mori.a-times）】
${rocketchat_log}

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
