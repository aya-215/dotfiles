#!/bin/bash
input=$(cat)

# Nerd Font icons
icon_folder=$'\U000F024B'   # 󰉋 nf-md-folder
icon_branch=$'\UF126'       #  nf-fa-code_fork
icon_model=$'\U000F06A9'    # 󰚩 nf-md-robot
icon_context=$'\U000F01BC'  # 󰆼 nf-md-database
icon_todo=$'\U2611'          # ☑ ballot box with check

# ANSI colors (Catppuccin Mocha)
# Rule: location=cool, status=warm, meta=mid
B='\033[38;2;137;180;250m'  # Blue #89B4FA - folder/path
L='\033[38;2;180;190;254m'  # Lavender #B4BEFE - git branch
Y='\033[38;2;249;226;175m'  # Yellow #F9E2AF - dirty status
P='\033[38;2;250;179;135m'  # Peach #FAB387 - model
S='\033[38;2;108;112;134m'  # Overlay0 #6C7086 - separator
M='\033[38;2;203;166;247m'  # Mauve #CBA6F7 - context
G='\033[38;2;166;227;161m'  # Green #A6E3A1 - todo
R='\033[0m'                  # Reset

# Extract current directory
current_dir=$(echo "$input" | grep -o '"current_dir":"[^"]*"' | head -1 | sed 's/"current_dir":"//;s/"//')
current_dir=$(basename "$current_dir")

# Extract model display_name using grep/sed (no jq required)
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | head -1 | sed 's/"display_name":"//;s/"//')

# Extract context window values
context_size=$(echo "$input" | grep -o '"context_window_size":[0-9]*' | sed 's/"context_window_size"://')
input_tokens=$(echo "$input" | grep -o '"input_tokens":[0-9]*' | head -1 | sed 's/"input_tokens"://')
cache_creation=$(echo "$input" | grep -o '"cache_creation_input_tokens":[0-9]*' | sed 's/"cache_creation_input_tokens"://')
cache_read=$(echo "$input" | grep -o '"cache_read_input_tokens":[0-9]*' | sed 's/"cache_read_input_tokens"://')

# Extract transcript path
transcript=$(echo "$input" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')

# Format number as K (e.g., 35000 -> 35K)
format_k() {
  local n=$1
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    echo "$((n / 1000))K"
  else
    echo "${n:-0}"
  fi
}

# Calculate context usage percentage (until autocompact)
# Autocompact buffer is ~22.5% of context, so effective max is 77.5%
AUTOCOMPACT_RATIO=775  # 77.5% as integer (775/1000)

if [ -n "$context_size" ] && [ "$context_size" -gt 0 ] 2>/dev/null; then
  current=$((${input_tokens:-0} + ${cache_creation:-0} + ${cache_read:-0}))
  effective_max=$((context_size * AUTOCOMPACT_RATIO / 1000))
  compact_pct=$((current * 100 / effective_max))
  current_k=$(format_k $current)
  effective_k=$(format_k $effective_max)
  context_info="${compact_pct}% (${current_k}/${effective_k})"
else
  context_info="0%"
fi

# Get git branch and dirty status
git_branch=""
git_dirty=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git branch --show-current 2>/dev/null)
  if [ -n "$git_branch" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    git_dirty="*"
  fi
fi

# Count pending TODOs from transcript (created - completed - deleted)
todo_count=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  created=$(grep -c '"name":"TaskCreate"' "$transcript" 2>/dev/null) || created=0
  completed=$(grep '"name":"TaskUpdate"' "$transcript" 2>/dev/null | grep -c '"completed"') || completed=0
  deleted=$(grep '"name":"TaskUpdate"' "$transcript" 2>/dev/null | grep -c '"deleted"') || deleted=0
  todo_count=$((created - completed - deleted))
  [ "$todo_count" -lt 0 ] && todo_count=0
fi

# --- Usage API (rate limit display) ---

CACHE_FILE="$HOME/.cache/claude-statusline/usage.json"
CACHE_TTL=360

# Get OAuth token from WSL credentials file
get_access_token() {
  local creds="$HOME/.claude/.credentials.json"
  [ -f "$creds" ] || return
  command -v jq &>/dev/null || return
  jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null
}

# Fetch usage with caching (network I/O runs in background)
get_usage_cached() {
  if [ -f "$CACHE_FILE" ]; then
    local age
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$CACHE_TTL" ]; then
      cat "$CACHE_FILE"
      return
    fi
  fi

  local token
  token=$(get_access_token)
  if [ -z "$token" ]; then
    [ -f "$CACHE_FILE" ] && cat "$CACHE_FILE"
    return
  fi

  # Fetch in background to avoid blocking status line
  (
    mkdir -p "$(dirname "$CACHE_FILE")"
    local result
    result=$(curl -s -m 5 \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if echo "$result" | jq -e '.five_hour' &>/dev/null; then
      printf '%s' "$result" > "$CACHE_FILE"
    fi
  ) &

  [ -f "$CACHE_FILE" ] && cat "$CACHE_FILE"
}

# Color by percentage (Catppuccin Mocha)
color_for_pct() {
  local pct=$1
  if   [ "$pct" -ge 80 ] 2>/dev/null; then printf '\033[38;2;243;139;168m'  # Red #F38BA8
  elif [ "$pct" -ge 50 ] 2>/dev/null; then printf '\033[38;2;249;226;175m'  # Yellow #F9E2AF
  else                                      printf '\033[38;2;166;227;161m'  # Green #A6E3A1
  fi
}

# 10-segment progress bar
progress_bar() {
  local pct=$1
  local filled=$(( pct / 10 ))
  local empty=$(( 10 - filled ))
  local bar=""
  local i
  for i in $(seq 1 $filled); do bar="${bar}█"; done
  for i in $(seq 1 $empty);  do bar="${bar}░"; done
  printf '%s' "$bar"
}

# Format ISO 8601 reset time to human-readable (Asia/Tokyo)
format_reset_time() {
  local iso="$1"
  local window="$2"  # "5h" or "7d"
  if [ -z "$iso" ]; then
    echo "unknown"
    return
  fi
  if [ "$window" = "5h" ]; then
    # Show HH:MM in JST
    TZ=Asia/Tokyo date -d "$iso" '+%H:%M' 2>/dev/null || echo "$iso"
  else
    # Show weekday in JST
    TZ=Asia/Tokyo date -d "$iso" '+%a %d日' 2>/dev/null || echo "$iso"
  fi
}

# Output line 1: existing info
printf "${B}%s %s${R}" "$icon_folder" "$current_dir"
printf " ${S}|${R} "
printf "${L}%s %s${R}${Y}%s${R}" "$icon_branch" "$git_branch" "$git_dirty"
printf " ${S}|${R} "
printf "${P}%s %s${R}" "$icon_model" "$model"
printf " ${S}|${R} "
printf "${M}%s %s${R}" "$icon_context" "$context_info"
if [ "$todo_count" -gt 0 ] 2>/dev/null; then
  printf " ${S}|${R} "
  printf "${G}%s %s${R}" "$icon_todo" "$todo_count"
fi
echo

# Output lines 2-3: usage (only if jq available and cache/API succeeds)
if command -v jq &>/dev/null; then
  usage_json=$(get_usage_cached)
  if [ -n "$usage_json" ] && echo "$usage_json" | jq -e '.five_hour' &>/dev/null; then
    # 5h window
    pct_5h=$(echo "$usage_json" | jq -r '.five_hour.utilization | floor | tostring' 2>/dev/null)
    reset_5h=$(echo "$usage_json" | jq -r '.five_hour.resets_at // ""' 2>/dev/null)
    pct_5h=${pct_5h:-0}
    bar_5h=$(progress_bar "$pct_5h")
    col_5h=$(color_for_pct "$pct_5h")
    time_5h=$(format_reset_time "$reset_5h" "5h")
    printf "${col_5h}[%s] %3d%%${R} ${S}│${R} 5h reset: %s\n" "$bar_5h" "$pct_5h" "$time_5h"

    # 7d window
    pct_7d=$(echo "$usage_json" | jq -r '.seven_day.utilization | floor | tostring' 2>/dev/null)
    reset_7d=$(echo "$usage_json" | jq -r '.seven_day.resets_at // ""' 2>/dev/null)
    pct_7d=${pct_7d:-0}
    bar_7d=$(progress_bar "$pct_7d")
    col_7d=$(color_for_pct "$pct_7d")
    time_7d=$(format_reset_time "$reset_7d" "7d")
    printf "${col_7d}[%s] %3d%%${R} ${S}│${R} 7d reset: %s\n" "$bar_7d" "$pct_7d" "$time_7d"
  fi
fi
