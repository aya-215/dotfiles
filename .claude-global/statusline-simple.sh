#!/bin/bash
# 配布用 statusline。自分用の statusline-command.sh とは別実体。
#
# 環境差の大きい2点を設定可能にしてある:
#   CC_STATUSLINE_ICONS=1  Nerd Font のアイコンを使う (既定 0 = ASCII)
#   CC_STATUSLINE_COLOR    truecolor / basic / none (既定 auto)
#
# アイコンは自動検出できない。フォントが持つグリフを問い合わせる手段は
# 端末に存在せず、TERM 等からの推測は必ず外れる環境が出る。既定を off に
# しているのは、豆腐が並ぶと「壊れている」と見えるのに対し ASCII は単に
# 素朴なだけで済むから。
input=$(cat)

# --- アイコン ---
if [ "${CC_STATUSLINE_ICONS:-0}" = "1" ]; then
  icon_folder=$'\U000F024B'   # 󰉋 nf-md-folder
  icon_branch=$'\UF126'       #  nf-fa-code_fork
  icon_model=$'\U000F06A9'    # 󰚩 nf-md-robot
  icon_context=$'\U000F01BC'  # 󰆼 nf-md-database
  icon_todo=$'\U2611'         # ☑
  bar_full='█'; bar_empty='░'; sep_sub='│'
else
  icon_folder='DIR'; icon_branch='git:'; icon_model='AI'
  icon_context='ctx'; icon_todo='TODO'
  bar_full='#'; bar_empty='-'; sep_sub='|'
fi

# --- 配色 ---
# Git Bash は TERM=xterm-256color を出すが COLORTERM は空 (実測済み)。
# COLORTERM だけで判定すると Windows の同僚が全員 basic に落ちるため
# WT_SESSION / TERM_PROGRAM も見る。判定不能なら basic 側に倒す:
# 24bit 非対応端末に truecolor を送ると生のエスケープが出て読めなくなるが、
# 逆に 16 色を送るのは色が地味になるだけで済む。
color_mode="${CC_STATUSLINE_COLOR:-auto}"
if [ "$color_mode" = "auto" ]; then
  case "$COLORTERM" in
    truecolor|24bit) color_mode=truecolor ;;
    *)
      if [ -n "$WT_SESSION" ] || [ -n "$TERM_PROGRAM" ]; then
        color_mode=truecolor
      else
        color_mode=basic
      fi
      ;;
  esac
fi

case "$color_mode" in
  truecolor)
    B='\033[38;2;137;180;250m'  # Blue
    L='\033[38;2;180;190;254m'  # Lavender
    Y='\033[38;2;249;226;175m'  # Yellow
    P='\033[38;2;250;179;135m'  # Peach
    S='\033[38;2;108;112;134m'  # Overlay0
    M='\033[38;2;203;166;247m'  # Mauve
    G='\033[38;2;166;227;161m'  # Green
    C_RED='\033[38;2;243;139;168m'
    C_YEL='\033[38;2;249;226;175m'
    C_GRN='\033[38;2;166;227;161m'
    R='\033[0m'
    ;;
  none)
    B=''; L=''; Y=''; P=''; S=''; M=''; G=''
    C_RED=''; C_YEL=''; C_GRN=''; R=''
    ;;
  *)
    B='\033[34m'; L='\033[35m'; Y='\033[33m'; P='\033[36m'
    S='\033[90m'; M='\033[35m'; G='\033[32m'
    C_RED='\033[31m'; C_YEL='\033[33m'; C_GRN='\033[32m'
    R='\033[0m'
    ;;
esac

# jq が無い/失敗したとき用。line 1 の必須項目のみ拾う。
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

# "Opus 5 (1M context)" -> "Opus 5"
model_short=$model
case $model in
  *' ('*')')
    _stripped=${model% (*}
    [ -n "$_stripped" ] && model_short=$_stripped
    ;;
esac

# Claude Code 本体が出す used_percentage をそのまま使う。autocompact 基準の
# 独自計算 + 分数表示は、値の意味を説明できないと「本体の表示と数字が違う」
# という問い合わせになるため配布版では採らない。
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
  if   [ "$pct" -ge 80 ] 2>/dev/null; then printf '%b' "$C_RED"
  elif [ "$pct" -ge 50 ] 2>/dev/null; then printf '%b' "$C_YEL"
  else                                      printf '%b' "$C_GRN"
  fi
}

progress_bar() {
  local pct=$1
  local filled=$(( pct / 10 ))
  [ "$filled" -gt 10 ] && filled=10
  [ "$filled" -lt 0 ] && filled=0
  local empty=$(( 10 - filled ))
  local bar="" i
  for ((i=0; i<filled; i++)); do bar="${bar}${bar_full}"; done
  for ((i=0; i<empty;  i++)); do bar="${bar}${bar_empty}"; done
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

# --- line 1 ---
printf "${B}%s %s${R}" "$icon_folder" "$current_dir"
printf " ${S}|${R} "
printf "${L}%s %s${R}${Y}%s${R}" "$icon_branch" "$git_branch" "$git_dirty"
printf " ${S}|${R} "
effort_suffix=""
[ -n "$effort_level" ] && effort_suffix=" ($effort_level)"
printf "${P}%s %s%s${R}" "$icon_model" "$model_short" "$effort_suffix"
printf " ${S}|${R} "
printf "${M}%s %s${R}" "$icon_context" "$context_info"
if [ "$todo_count" -gt 0 ] 2>/dev/null; then
  printf " ${S}|${R} "
  printf "${G}%s %s${R}" "$icon_todo" "$todo_count"
fi
echo

# --- lines 2-3: Claude.ai 購読者のみ、初回 API 応答後に出る ---
if [ -n "$pct_5h" ]; then
  pct_5h=${pct_5h%%.*}
  printf "%b[%s] %3d%%${R} ${S}%s${R} 5h reset: %s\n" \
    "$(color_for_pct "$pct_5h")" "$(progress_bar "$pct_5h")" \
    "$pct_5h" "$sep_sub" "$(format_reset_time "${reset_5h%%.*}" 5h)"
fi
if [ -n "$pct_7d" ]; then
  pct_7d=${pct_7d%%.*}
  printf "%b[%s] %3d%%${R} ${S}%s${R} 7d reset: %s\n" \
    "$(color_for_pct "$pct_7d")" "$(progress_bar "$pct_7d")" \
    "$pct_7d" "$sep_sub" "$(format_reset_time "${reset_7d%%.*}" 7d)"
fi
