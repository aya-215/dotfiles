# ======================
# nb ハイブリッド実装
# ======================
# nbネイティブ機能をベースに、fzfでUXを強化
_NB_TASKS="tasks:"
_NB_DAILY="daily:"

# -------------
# タスク管理
# -------------

# nbt - タスク追加
nbt() {
  local title="" due="" tags="" priority="" desc=""

  # オプション解析
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--due)      due="$2"; shift 2 ;;
      -t|--tags)     tags="$2"; shift 2 ;;
      -p|--priority) priority="$2"; shift 2 ;;
      -D|--desc)     desc="$2"; shift 2 ;;
      -*)            echo "不明なオプション: $1"; return 1 ;;
      *)             title="$1"; shift ;;
    esac
  done

  # 引数なし → 対話形式
  if [[ -z "$title" ]]; then
    read "title?タスク名: "
    [[ -z "$title" ]] && return 1
    read "due?期限 (数字/3d/1w/tomorrow): "
    echo -n "タグ: "
    read "tags_input?"
    if [[ -z "$tags_input" ]]; then
      tags=$(_nb_select_tags)
    else
      tags="$tags_input"
    fi
    read "priority?優先度 (1:high/2:medium/3:low): "
    read "desc?説明 (省略可): "
  fi

  # 優先度をパースしてタグに追加
  priority=$(_nb_parse_priority "$priority")
  [[ -n "$priority" ]] && tags="${tags:+$tags,}$priority"

  # 相対日付をパース
  due=$(_nb_parse_date "$due")

  # nbネイティブコマンド構築
  local cmd="nb ${_NB_TASKS}todo add \"$title\""
  [[ -n "$due" ]] && cmd+=" --due \"$due\""
  [[ -n "$tags" ]] && cmd+=" --tags \"$tags\""
  [[ -n "$desc" ]] && cmd+=" --description \"$desc\""

  eval "$cmd"
  echo "✅ タスク作成: $title"
}

# 相対日付パース
_nb_parse_date() {
  local input="$1"
  [[ -z "$input" ]] && return
  case "$input" in
    today)                 date +%Y-%m-%d ;;
    tomorrow)              date -d "tomorrow" +%Y-%m-%d ;;
    +[0-9]*d|[0-9]*d)      date -d "${input//[+d]/} days" +%Y-%m-%d ;;
    +[0-9]*w|[0-9]*w)      date -d "${input//[+w]/} weeks" +%Y-%m-%d ;;
    [0-9]|[0-9][0-9])      date -d "$input days" +%Y-%m-%d ;;
    *)                     echo "$input" ;;
  esac
}

# 優先度パース
_nb_parse_priority() {
  case "$1" in
    1|high)   echo "high" ;;
    2|medium) echo "medium" ;;
    3|low)    echo "low" ;;
    *)        echo "$1" ;;
  esac
}

# タグ選択（fzf複数選択）
_nb_select_tags() {
  local existing=$(grep -rh '#[a-zA-Z]' ~/.nb/tasks/*.md 2>/dev/null | \
    grep -oE '#[a-zA-Z0-9_/-]+' | sed 's/^#//' | sort -u)
  [[ -z "$existing" ]] && return
  echo "$existing" | fzf --multi --prompt="Tags (tab:複数選択)> " | tr '\n' ',' | sed 's/,$//'
}

# nbtl - タスク一覧
nbtl() {
  local filter="$1"
  if [[ -n "$filter" ]]; then
    nb ${_NB_TASKS}todos open | grep -i "$filter"
  else
    nb ${_NB_TASKS}todos open
  fi
}

# nbtd - タスク完了
nbtd() {
  if [[ -z "$1" ]]; then
    # fzfで選択
    local selected=$(nb ${_NB_TASKS}todos open --no-color | \
      fzf --prompt="Complete> " --preview 'nb show $(echo {1} | tr -d "[]")')
    [[ -z "$selected" ]] && return
    local id=$(echo "$selected" | awk '{print $1}' | tr -d '[]')
    nb ${_NB_TASKS}do "$id"
  else
    nb ${_NB_TASKS}do "$1"
  fi
  echo "✅ 完了"
}

# nbtu - タスク完了取消
nbtu() {
  [[ -z "$1" ]] && { echo "使い方: nbtu <ID>"; return 1; }
  nb ${_NB_TASKS}undo "$1"
  echo "↩️ 取消: #$1"
}

# nbte - タスク編集（fzf選択）
nbte() {
  local selected=$(nb ${_NB_TASKS}todos --no-color | \
    fzf --prompt="Edit> " --preview 'nb show $(echo {1} | tr -d "[]")')
  [[ -z "$selected" ]] && return
  local id=$(echo "$selected" | awk '{print $1}' | tr -d '[]')
  nb ${_NB_TASKS}edit "$id"
}

# nbts - タスク検索
nbts() {
  if [[ -z "$1" ]]; then
    nb ${_NB_TASKS}list --no-color | \
      fzf --prompt="Search> " --preview 'nb show $(echo {1} | tr -d "[]")'
  else
    nb ${_NB_TASKS}search "$1"
  fi
}

# nbtag - タグで絞り込み
nbtag() {
  # タスクファイルからタグを収集
  local tag=$(grep -rh '#[a-zA-Z]' ~/.nb/tasks/*.md 2>/dev/null | \
    grep -oE '#[a-zA-Z0-9_/-]+' | sort -u | fzf --prompt="Tag> ")
  [[ -n "$tag" ]] && nb ${_NB_TASKS}search "$tag"
}

# nbtclosed - 完了タスク一覧
nbtclosed() {
  nb ${_NB_TASKS}todos closed
}

# 日報用タスク整形（期限: タイトル形式、期限なしはタイトルのみ）
_nb_format_tasks_for_daily() {
  nb ${_NB_TASKS}todos open --no-color 2>/dev/null | head -10 | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # ID抽出
    local id=$(echo "$line" | grep -oE '\[tasks:[0-9]+\]' | grep -oE '[0-9]+')
    [[ -z "$id" ]] && continue
    # タイトル抽出
    local title=$(echo "$line" | sed 's/.*\] *✔️ *\[ \] *//')
    # 期限取得（ファイルから）
    local due=$(nb ${_NB_TASKS}show "$id" --no-color 2>/dev/null | awk '/^## *Due/{found=1;next} found && /^[0-9]/{print;exit}')
    if [[ -n "$due" && "$due" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      due=$(date -d "$due" +%m/%d 2>/dev/null)
      echo "- $due: $title"
    else
      echo "- $title"
    fi
  done
}

# -------------
# 日報管理
# -------------

# nbd - 今日の日報作成/編集
nbd() {
  local date=$(date +%Y-%m-%d)
  local yesterday=$(date -d yesterday +%Y-%m-%d)
  local template_path="$HOME/.nb/daily/.templates/daily.md"

  # 既に存在する場合は編集
  if nb ${_NB_DAILY}show "$date.md" &>/dev/null; then
    nb ${_NB_DAILY}edit "$date.md"
    return
  fi

  # 未完了タスク（nbネイティブから取得、整形）
  local tasks=$(_nb_format_tasks_for_daily)
  [[ -z "$tasks" ]] && tasks="（未完了タスクなし）"

  # 前日のサマリーを取得
  local yesterday_summary=""
  if nb ${_NB_DAILY}show "$yesterday.md" &>/dev/null; then
    yesterday_summary=$(nb ${_NB_DAILY}show "$yesterday.md" 2>/dev/null | \
      awk '/^## 📝 今日のサマリー/{flag=1;next}/^## /{flag=0}flag' | \
      sed '/^$/d' | sed 's/^/> /')
  fi
  [[ -z "$yesterday_summary" ]] && yesterday_summary="（前日のサマリーなし）"

  # テンプレートから日報作成
  if [[ ! -f "$template_path" ]]; then
    echo "❌ テンプレートが見つかりません: $template_path"
    return 1
  fi

  local content=$(cat "$template_path")
  content="${content//\{\{DATE\}\}/$date}"
  content="${content//\{\{TASKS\}\}/$tasks}"
  content="${content//\{\{YESTERDAY_SUMMARY\}\}/$yesterday_summary}"

  nb ${_NB_DAILY}add "$date.md" --content "$content"
  nb ${_NB_DAILY}edit "$date.md"
}

# nbds - 今日の日報表示
nbds() { nb ${_NB_DAILY}show "$(date +%Y-%m-%d).md"; }

# nbde - 今日の日報編集
nbde() { nb ${_NB_DAILY}edit "$(date +%Y-%m-%d).md"; }

# nbdy - 昨日の日報表示
nbdy() { nb ${_NB_DAILY}show "$(date -d yesterday +%Y-%m-%d).md"; }

# nbdl - 日報一覧（fzf）
nbdl() {
  local selected=$(nb ${_NB_DAILY}list --no-color | \
    fzf --prompt="日報> " --preview 'nb show $(echo {1} | tr -d "[]")')
  [[ -n "$selected" ]] && nb ${_NB_DAILY}show "$(echo "$selected" | awk '{print $1}' | tr -d '[]')"
}
