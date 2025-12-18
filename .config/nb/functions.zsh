# ======================
# nb 共通設定
# ======================
_NB_TASKS_DIR="$HOME/.nb/tasks"
_NB_DAILY_DIR="$HOME/.nb/daily"

# 補完用: 未完了タスク一覧（zeno補完から呼び出し）
_nb_incomplete_tasks() {
  _nb_find_tasks | while read -r file; do
    IFS='|' read -r due status tags priority title folder <<< "$(_nb_parse_task "$file")"
    [[ "$status" == "done" ]] && continue
    echo "${folder:+$folder/}$title"
  done
}

# 共通: タスクファイル一覧取得
_nb_find_tasks() {
  find "$_NB_TASKS_DIR" -name "*.md" \
    -not -path "*/.templates/*" \
    -not -path "*/.git/*" \
    -not -name "inbox.md" 2>/dev/null
}

# 共通: 期限までの日数を計算
_nb_days_until() {
  local due="$1"
  local today=$(date +%Y-%m-%d)
  echo $(( ($(date -d "$due" +%s) - $(date -d "$today" +%s)) / 86400 ))
}

# 共通: タスク情報を取得（due|status|tags|priority|title|folder）
_nb_parse_task() {
  local file="$1"
  local due=$(grep "^due:" "$file" 2>/dev/null | cut -d: -f2- | xargs)
  local status=$(grep "^status:" "$file" 2>/dev/null | cut -d: -f2- | xargs)
  local tags=$(grep "^tags:" "$file" 2>/dev/null | cut -d: -f2- | xargs)
  local priority=$(grep "^priority:" "$file" 2>/dev/null | cut -d: -f2- | xargs)
  local title=$(basename "$file" .md)
  local folder=$(basename "$(dirname "$file")")
  [[ "$folder" == "tasks" ]] && folder=""
  echo "${due:-未定}|${status:-todo}|${tags:-未分類}|${priority:-medium}|$title|$folder"
}

# ======================
# nb 日報管理関数
# ======================

# nbd - 今日の日報を作成（タスク自動連携）
nbd() {
  local date=$(date +%Y-%m-%d)
  local timestamp=$(date '+%a %b %d %H:%M:%S %Z %Y')
  local template="$_NB_DAILY_DIR/.templates/daily.md"

  # 既に存在する場合は編集モードで開く
  if nb daily:show "$date.md" &>/dev/null; then
    nb daily:edit "$date.md"
    return
  fi

  # inbox.mdを最新化
  nbtsync 2>/dev/null

  # 今日・今週のタスクを収集
  local inbox="$_NB_TASKS_DIR/inbox.md"
  awk '/## 🔥 今日・期限切れ/,/^## [^🔥]/ { if (/^- \[ \]/) { sub(/ → \[\[.*\]\]$/, ""); print } }
       /## 📅 今週中/,/^## [^📅]/ { if (/^- \[ \]/) { sub(/ → \[\[.*\]\]$/, ""); print } }' \
    "$inbox" > /tmp/today_tasks.txt

  # テンプレートから日報を作成
  if [[ ! -f "$template" ]]; then
    echo "❌ テンプレートが見つかりません: $template"
    return 1
  fi

  local content=$(sed -e "s/{{DATE}}/$date/g" -e "s/{{TIMESTAMP}}/$timestamp/g" "$template")

  # 今日のタスクを自動挿入
  if [[ -s /tmp/today_tasks.txt ]]; then
    local task_list=$(cat /tmp/today_tasks.txt)
    content=$(echo "$content" | awk -v tasks="$task_list" '
      /^## 📋 今日のタスク/ { print; getline; print; print tasks; next }
      { print }
    ')
  fi

  nb daily:add "$date.md" --content "$content"
  rm -f /tmp/today_tasks.txt
  nb daily:edit "$date.md"
}

# nbds - 今日の日報を表示 (show)
nbds() { nb daily:show "$(date +%Y-%m-%d).md"; }

# nbde - 今日の日報を編集 (edit)
nbde() { nb daily:edit "$(date +%Y-%m-%d).md"; }

# nbdy - 昨日の日報を表示
nbdy() { nb daily:show "$(date -d yesterday +%Y-%m-%d).md"; }

# nbdl - 日報一覧をfzfで選択
nbdl() {
  local selected=$(nb daily:list --no-color | grep -E "^\[" | \
    fzf --prompt="日報> " --preview "nb daily:show {2}")
  [[ -n "$selected" ]] && nb daily:show "$(echo "$selected" | awk '{print $1}' | tr -d '[]')"
}

# nbi - inbox編集
nbi() { nb tasks:edit inbox.md; }

# ======================
# nb タスク管理関数
# ======================

# nbtf - タスクフォルダ作成
nbtf() {
  [[ -z "$1" ]] && { echo "使い方: nbtf \"フォルダ名\""; return 1; }
  mkdir -p "$_NB_TASKS_DIR/$1"
  echo "✅ フォルダ作成: tasks/$1/"
}

# nbtfl - タスクフォルダ一覧
nbtfl() {
  echo "📁 タスクフォルダ一覧\n"
  find "$_NB_TASKS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name ".*" | while read -r folder; do
    local name=$(basename "$folder")
    local count=$(find "$folder" -name "*.md" 2>/dev/null | wc -l)
    echo "  $name ($count)"
  done
}

# nbt - タスク追加
nbt() {
  local title="$1" folder="$2"
  [[ -z "$title" ]] && { echo "使い方: nbt \"タスク名\" [フォルダ名]"; return 1; }

  # フォルダ選択（fzf）
  if [[ -z "$folder" ]] && command -v fzf &>/dev/null; then
    local folders=$(find "$_NB_TASKS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name ".*" -exec basename {} \; 2>/dev/null)
    if [[ -n "$folders" ]]; then
      folder=$(echo "$folders\n(tasks直下)" | fzf --prompt="Folder> " --height=40% --reverse)
      [[ "$folder" == "(tasks直下)" ]] && folder=""
    fi
  fi

  read "due?期限 (YYYY-MM-DD): "
  read "tags?タグ (カンマ区切り): "
  read "priority?優先度 (high/medium/low): "

  local template="$_NB_TASKS_DIR/.templates/task.md"
  [[ ! -f "$template" ]] && { echo "❌ テンプレートが見つかりません"; return 1; }

  local file_path="${folder:+$folder/}$title.md"
  [[ -n "$folder" ]] && mkdir -p "$_NB_TASKS_DIR/$folder"

  sed -e "s/{{DUE_DATE}}/${due:-未定}/g" \
      -e "s/{{TAGS}}/${tags:-未分類}/g" \
      -e "s/{{TITLE}}/$title/g" \
      -e "s/{{CREATED_DATE}}/$(date +%Y-%m-%d)/g" \
      -e "s/priority: medium/priority: ${priority:-medium}/g" \
      "$template" | nb tasks:add "$file_path"

  echo "✅ タスク作成: tasks:$file_path"
  nb tasks:edit "$file_path"
  nbtsync 2>/dev/null
}

# nbtl - タスク一覧表示
nbtl() {
  local filter="$1"
  echo "📋 タスク一覧\n"

  _nb_find_tasks | while read -r file; do
    IFS='|' read -r due status tags priority title folder <<< "$(_nb_parse_task "$file")"

    [[ "$status" == "done" ]] && continue
    [[ -n "$filter" && ! "$tags" =~ "$filter" ]] && continue

    # 優先度アイコン
    local icon="🟢"; [[ "$priority" == "high" ]] && icon="🔴"; [[ "$priority" == "medium" ]] && icon="🟡"

    # 期限表示
    local due_display="$due"
    if [[ "$due" != "未定" ]]; then
      local days=$(_nb_days_until "$due")
      (( days < 0 )) && due_display="$due ⚠️"
      (( days == 0 )) && due_display="$due 🔥"
      (( days > 0 && days <= 3 )) && due_display="$due ⏰${days}d"
    fi

    local path="${folder:+$folder/}$title"
    echo "$icon $due_display [$tags] $path"
  done | sort
}

# nbtsync - inbox.md自動生成（効率化版）
nbtsync() {
  local inbox="$_NB_TASKS_DIR/inbox.md"
  local today=$(date +%Y-%m-%d)
  local urgent="" week="" undefined=""

  # 1回のループで全タスクを分類
  _nb_find_tasks | while read -r file; do
    IFS='|' read -r due status tags priority title folder <<< "$(_nb_parse_task "$file")"
    [[ "$status" == "done" ]] && continue

    local entry="- [ ] $title${due:+ 📅 $due}${tags:+ $tags} → [[tasks:$title.md]]"

    if [[ "$due" == "未定" ]]; then
      echo "U|$entry"
    else
      local days=$(_nb_days_until "$due")
      if (( days <= 0 )); then
        echo "T|$entry"
      elif (( days <= 7 )); then
        echo "W|$entry"
      fi
    fi
  done | {
    # 分類結果を集約
    while IFS='|' read -r type entry; do
      case "$type" in
        T) urgent+="$entry\n" ;;
        W) week+="$entry\n" ;;
        U) undefined+="$entry\n" ;;
      esac
    done

    # inbox.md生成
    cat > "$inbox" << EOF
# タスク受信箱

> 自動生成（nbtsync）

## 🔥 今日・期限切れ

$(echo -e "$urgent")
## 📅 今週中

$(echo -e "$week")
## 📋 期限未定

$(echo -e "$undefined")
EOF
  }
  echo "✅ inbox.md 更新完了"
}

# nbtdone - タスク完了
nbtdone() {
  [[ -z "$1" ]] && { echo "使い方: nbtdone \"タスク名\""; return 1; }

  local task="$1"
  [[ "$task" != *.md ]] && task="$task.md"

  local file="$_NB_TASKS_DIR/$task"
  if [[ ! -f "$file" ]]; then
    file=$(find "$_NB_TASKS_DIR" -name "$(basename "$task")" -not -path "*/.templates/*" | head -1)
    [[ -z "$file" ]] && { echo "❌ タスクが見つかりません"; return 1; }
  fi

  sed -i 's/^status: todo/status: done/' "$file"
  echo "✅ 完了: $(basename "$file" .md)"
  nbtsync 2>/dev/null
}
