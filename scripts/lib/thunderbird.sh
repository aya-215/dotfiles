#!/bin/bash
# thunderbird.sh - Thunderbird のメールから自分に関係するやりとりを収集して整形出力する
#
# 日報 cron（fire-daily-review.sh）と work-report skill の共通データ取得層。
# 期間絞り込み・宛先判定・ノイズ除去・スレッド集約という決定的な処理を担い、
# 作業内容の分類のような非決定的な判断は呼び出し側（Claude）に委ねる。
#
# 採用は2段構え。まず「to/cc/bcc に自分または ai-team が入っているもの」で母集団を
# 絞り（ホワイトリスト）、そこから既知のノイズ送信元を引く（ブラックリスト）。
# この順序により、未知のノイズ送信元は除外リストを増やさずとも自動的に落ちる。
#
# 使用方法:
#   thunderbird.sh --from 2026-07-10 --to 2026-08-10 [--budget N]
#   thunderbird.sh --from ... --to ... --no-body     # 本文を出さず件名のみ（週次以上で使う）
#   thunderbird.sh --from ... --to ... --full-thread # スレッド全体を出す（要約層への入力用）
#   thunderbird.sh --from ... --to ... --replied-only # 一度でも返信したスレッドだけに絞る
#   thunderbird.sh --from ... --to ... --raw     # 除外前の生データを JSON で出す（判別用）
#   thunderbird.sh --from ... --to ... --stats   # 段階ごとの件数だけ出す（デバッグ用）
#
# 期間が長いと本文込みでは肥大する（1ヶ月で約55,000文字）。週次以上は --no-body を使う。
#
# 環境変数:
#   THUNDERBIRD_PROFILE_PATH  プロファイルディレクトリ（未設定なら既定パスを探索）
#   TB_MCP_ENTRY              MCPサーバの build/index.js（未設定なら既定パス）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_MCP_ENTRY="$HOME/src/github.com/ebase-dev/ebase-middleware-mcp/thunderbird-mcp/build/index.js"
readonly DEFAULT_PROFILE="/mnt/c/Users/368/AppData/Roaming/Thunderbird/Profiles/afhbv27s.default-release"

mcp_entry="${TB_MCP_ENTRY:-$DEFAULT_MCP_ENTRY}"
profile="${THUNDERBIRD_PROFILE_PATH:-$DEFAULT_PROFILE}"

from="" to="" budget=0 raw=0 stats=0 no_body=0 full_thread=0 replied_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from)         from="$2"; shift 2 ;;
    --to)           to="$2"; shift 2 ;;
    --budget)       budget="$2"; shift 2 ;;
    --raw)          raw=1; shift ;;
    --stats)        stats=1; shift ;;
    --no-body)      no_body=1; shift ;;
    --full-thread)  full_thread=1; shift ;;
    --replied-only) replied_only=1; shift ;;
    *) echo "不明な引数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$from" ] && [ -n "$to" ] || { echo "--from と --to は必須" >&2; exit 2; }

if [ ! -f "$mcp_entry" ]; then
  echo "ERROR: thunderbird-mcp が見つかりません: $mcp_entry" >&2
  exit 1
fi
if [ ! -d "$profile" ]; then
  echo "ERROR: Thunderbird プロファイルが見つかりません: $profile" >&2
  exit 1
fi

THUNDERBIRD_PROFILE_PATH="$profile" \
TB_FROM="$from" TB_TO="$to" TB_BUDGET="$budget" TB_RAW="$raw" TB_STATS="$stats" \
TB_NO_BODY="$no_body" TB_FULL_THREAD="$full_thread" \
TB_REPLIED_ONLY="$replied_only" \
TB_MCP_ENTRY="$mcp_entry" \
exec python3 "$SCRIPT_DIR/thunderbird_collect.py"
