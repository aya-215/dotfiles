#!/bin/bash
# 配布用 statusline。環境設定なしでそのまま動くことを優先している。
#
# 自分用の statusline-command.sh との違い:
#   - アイコンを使わない。Nerd Font が入っているかを端末に問い合わせる手段は
#     存在せず、TERM 等からの推測は必ず外れる環境が出る。豆腐が並ぶと
#     「壊れている」と見えるため ASCII で固定する。
#   - コンテキスト率は Claude Code 本体の used_percentage をそのまま出す。
#     autocompact 基準の独自計算は値の意味を説明できず本体表示と食い違う。
input=$(cat)

# ANSI colors (Catppuccin Mocha)
# Windows Terminal / conhost (Win10 1703+) / VS Code はいずれも 24bit 対応。
B='\033[38;2;137;180;250m'  # Blue #89B4FA - folder
L='\033[38;2;180;190;254m'  # Lavender #B4BEFE - branch
Y='\033[38;2;249;226;175m'  # Yellow #F9E2AF - dirty
P='\033[38;2;250;179;135m'  # Peach #FAB387 - model
S='\033[38;2;108;112;134m'  # Overlay0 #6C7086 - separator
M='\033[38;2;203;166;247m'  # Mauve #CBA6F7 - context
G='\033[38;2;166;227;161m'  # Green #A6E3A1 - todo
R='\033[0m'

# jq が無い/失敗したとき用。1行目の必須項目のみ拾う。
parse_without_jq() {
  current_dir=$(echo "$input" | grep -o '"current_dir":"[^"]*"' | head -1 | sed 's/"current_dir":"//;s/"//')
  model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | head -1 | sed 's/"display_name":"//;s/"//')
  transcript=$(echo "$input" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')
  context_pct=$(echo "$input" | grep -o '"used_percentage":[0-9.]*' | head -1 | sed 's/"used_percentage"://')
  effort_level=""
  pct_5h=""; reset_5h=""; pct_7d=""; reset_7d=""
}

# NUL 区切りで受ける。タブ区切りだと空フィールドが潰れて以降の変数がズレる。
fields=()
if command -v jq &>/dev/null; then
  while IFS= read -r -d '' _f; do
    fields+=("$_f")
  done < <(
    jq -j '[
      .workspace.current_dir // "",
      .model.display_name // "",
      .transcript_path // "",
      .context_window.used_percentage // 0,
      .effort.level // "",
      .rate_limits.five_hour.used_percentage // "",
      .rate_limits.five_hour.resets_at // "",
      .rate_limits.seven_day.used_percentage // "",
      .rate_limits.seven_day.resets_at // ""
    ] | map(tostring + "\u0000") | add' <<<"$input" 2>/dev/null
  )
fi

# 全フィールドが揃ったときだけ jq の結果を信じる。jq が壊れていたり
# 想定外の入力だと、そのまま使うと行が丸ごと空になる。
if [ "${#fields[@]}" -eq 9 ]; then
  current_dir=${fields[0]}
  model=${fields[1]}
  transcript=${fields[2]}
  context_pct=${fields[3]}
  effort_level=${fields[4]}
  pct_5h=${fields[5]}
  reset_5h=${fields[6]}
  pct_7d=${fields[7]}
  reset_7d=${fields[8]}
else
  parse_without_jq
fi

current_dir=$(basename "$current_dir")

# "Opus 5 (1M context)" -> "Opus 5"。空いた場所に effort を出す。
model_short=$model
case $model in
  *' ('*')')
    _stripped=${model% (*}
    [ -n "$_stripped" ] && model_short=$_stripped
    ;;
esac

context_pct=${context_pct%%.*}
context_info="${context_pct:-0}%"

# --no-optional-locks: status が .git/index.lock を取るのを防ぐ。
# メッセージ更新ごとに走るため、実 git コマンドと衝突すると
# "Unable to create index.lock" として表に出る。
git_branch=""
git_dirty=""
if git --no-optional-locks rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git --no-optional-locks branch --show-current 2>/dev/null)
  if [ -n "$git_branch" ] && [ -n "$(git --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    git_dirty="*"
  fi
fi

todo_count=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  created=$(grep -c '"name":"TaskCreate"' "$transcript" 2>/dev/null) || created=0
  completed=$(grep '"name":"TaskUpdate"' "$transcript" 2>/dev/null | grep -c '"completed"') || completed=0
  deleted=$(grep '"name":"TaskUpdate"' "$transcript" 2>/dev/null | grep -c '"deleted"') || deleted=0
  todo_count=$((created - completed - deleted))
  [ "$todo_count" -lt 0 ] && todo_count=0
fi

color_for_pct() {
  local pct=$1
  if   [ "$pct" -ge 80 ] 2>/dev/null; then printf '\033[38;2;243;139;168m'  # Red #F38BA8
  elif [ "$pct" -ge 50 ] 2>/dev/null; then printf '\033[38;2;249;226;175m'  # Yellow #F9E2AF
  else                                      printf '\033[38;2;166;227;161m'  # Green #A6E3A1
  fi
}

progress_bar() {
  local pct=$1
  local filled=$(( pct / 10 ))
  [ "$filled" -gt 10 ] && filled=10
  [ "$filled" -lt 0 ] && filled=0
  local empty=$(( 10 - filled ))
  local bar="" i
  for ((i=0; i<filled; i++)); do bar="${bar}#"; done
  for ((i=0; i<empty;  i++)); do bar="${bar}-"; done
  printf '%s' "$bar"
}

# date -d は GNU 固有。Git Bash は GNU coreutils を同梱するので通る。
format_reset_time() {
  local epoch="$1" window="$2"
  if [ -z "$epoch" ]; then
    echo "unknown"
    return
  fi
  if [ "$window" = "5h" ]; then
    TZ=Asia/Tokyo date -d "@$epoch" '+%H:%M' 2>/dev/null || echo "$epoch"
  else
    TZ=Asia/Tokyo date -d "@$epoch" '+%a %d日' 2>/dev/null || echo "$epoch"
  fi
}

# --- 1行目 ---
printf "${B}DIR %s${R}" "$current_dir"
printf " ${S}|${R} "
printf "${L}git: %s${R}${Y}%s${R}" "$git_branch" "$git_dirty"
printf " ${S}|${R} "
effort_suffix=""
[ -n "$effort_level" ] && effort_suffix=" ($effort_level)"
printf "${P}AI %s%s${R}" "$model_short" "$effort_suffix"
printf " ${S}|${R} "
printf "${M}ctx %s${R}" "$context_info"
if [ "$todo_count" -gt 0 ] 2>/dev/null; then
  printf " ${S}|${R} "
  printf "${G}TODO %s${R}" "$todo_count"
fi
echo

# --- 2〜3行目: Claude.ai 購読者のみ、初回 API 応答後に出る ---
if [ -n "$pct_5h" ]; then
  pct_5h=${pct_5h%%.*}
  printf "%b[%s] %3d%%${R} ${S}|${R} 5h reset: %s\n" \
    "$(color_for_pct "$pct_5h")" "$(progress_bar "$pct_5h")" \
    "$pct_5h" "$(format_reset_time "${reset_5h%%.*}" 5h)"
fi
if [ -n "$pct_7d" ]; then
  pct_7d=${pct_7d%%.*}
  printf "%b[%s] %3d%%${R} ${S}|${R} 7d reset: %s\n" \
    "$(color_for_pct "$pct_7d")" "$(progress_bar "$pct_7d")" \
    "$pct_7d" "$(format_reset_time "${reset_7d%%.*}" 7d)"
fi
