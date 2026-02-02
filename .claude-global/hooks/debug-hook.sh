#!/bin/bash
# Claude Code hookデバッグ用スクリプト
# 標準入力からのJSON入力をファイルに記録

DEBUG_DIR="$HOME/.claude/hook-debug"
mkdir -p "$DEBUG_DIR"

timestamp=$(date +%Y%m%d_%H%M%S)
output_file="$DEBUG_DIR/hook_${timestamp}.json"

# 標準入力から全データを読み取り
read -r json_input

# ファイルに保存
echo "$json_input" > "$output_file"

# 基本情報も追記
{
  echo "=== Environment ==="
  echo "PWD: $PWD"
  echo "WEZTERM_PANE: ${WEZTERM_PANE:-not set}"
  echo "USER: $USER"
  echo ""
  echo "=== Hook Input ==="
  cat "$output_file"
} >> "$output_file"

exit 0
