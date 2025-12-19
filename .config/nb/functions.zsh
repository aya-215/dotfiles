# ======================
# nb ハイブリッド実装
# ======================
# nbネイティブ機能をベースに、fzfでUXを強化
_NB_TASKS="tasks:"
_NB_DAILY="daily:"
_NB_WEEKLY="weekly:"
_NB_NOTES="notes:"

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

  # nbネイティブコマンド実行（配列で直接実行し文字化けを防止）
  local -a args=("${_NB_TASKS}todo" "add" "$title")
  [[ -n "$due" ]] && args+=(--due "$due")
  [[ -n "$tags" ]] && args+=(--tags "$tags")
  [[ -n "$desc" ]] && args+=(--description "$desc")

  nb "${args[@]}"
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

# 優先度パース（priority/xxx形式で出力）
_nb_parse_priority() {
  case "$1" in
    1|high)   echo "priority/high" ;;
    2|medium) echo "priority/medium" ;;
    3|low)    echo "priority/low" ;;
    *)        [[ -n "$1" ]] && echo "$1" ;;
  esac
}

# タグ取得（notebook指定可能、日本語タグ対応）
_nb_get_tags() {
  local notebook="${1:-tasks}"
  grep -rhoP '#[^\s#]+' ~/.nb/$notebook/*.md 2>/dev/null | sort -u
}

# タグ選択（fzf複数選択）
_nb_select_tags() {
  local notebook="${1:-tasks}"
  local existing=$(_nb_get_tags "$notebook" | sed 's/^#//')
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
  local tag=$(_nb_get_tags tasks | sed 's/^#//' | fzf --prompt="Tag> ")
  [[ -n "$tag" ]] && nb ${_NB_TASKS}search "#$tag"
}

# nbtclosed - 完了タスク一覧
nbtclosed() {
  nb ${_NB_TASKS}todos closed
}

# 優先度を数値に変換（ソート用）
_nb_priority_to_num() {
  case "$1" in
    *"#priority/high"*)   echo "1" ;;
    *"#priority/medium"*) echo "2" ;;
    *"#priority/low"*)    echo "3" ;;
    *)                    echo "4" ;;
  esac
}

# タスク1件を整形出力
_nb_format_single_task() {
  local id="$1"
  # タイトル取得（同じ行 or 次の行の両方に対応）
  local title=$(nb ${_NB_TASKS}show "$id" --no-color 2>/dev/null | awk '
    /^# \[ \]/ {
      gsub(/^# \[ \] */, "")
      if ($0 != "") { print; exit }
      getline
      print
      exit
    }')
  [[ -z "$title" ]] && return
  local due=$(nb ${_NB_TASKS}show "$id" --no-color 2>/dev/null | awk '/^## *Due/{found=1;next} found && /^[0-9]/{print;exit}')
  if [[ -n "$due" && "$due" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    due=$(date -d "$due" +%m/%d 2>/dev/null)
    echo "- $due: $title"
  else
    echo "- $title"
  fi
}

# 日報用タスク整形（workタグ優先、日付順、優先度順）
_nb_format_tasks_for_daily() {
  # タスク情報を収集してソート用キーを生成
  # 形式: GROUP|DUE|PRIORITY|ID
  nb ${_NB_TASKS}todos open --no-color 2>/dev/null | head -20 | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local id=$(echo "$line" | grep -oE '\[tasks:[0-9]+\]' | grep -oE '[0-9]+')
    [[ -z "$id" ]] && continue

    local task_data=$(nb ${_NB_TASKS}show "$id" --no-color 2>/dev/null)
    local tags=$(echo "$task_data" | awk '/^## *Tags/{found=1;next} found && /^#/{print;exit}')
    local due=$(echo "$task_data" | awk '/^## *Due/{found=1;next} found && /^[0-9]/{print;exit}')

    # グループ: work=0, other=1
    local group="1"
    [[ "$tags" == *"#work"* ]] && group="0"

    # 日付: なしは9999-99-99
    [[ -z "$due" || ! "$due" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && due="9999-99-99"

    # 優先度を数値に
    local priority=$(_nb_priority_to_num "$tags")

    echo "${group}|${due}|${priority}|${id}"
  done | sort -t'|' -k1,1 -k2,2 -k3,3n | {
    local prev_group=""
    while IFS='|' read -r group due priority id; do
      # work/otherの間に空行
      if [[ -n "$prev_group" && "$prev_group" == "0" && "$group" == "1" ]]; then
        echo ""
      fi
      _nb_format_single_task "$id"
      prev_group="$group"
    done
  }
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
    yesterday_summary=$(nb ${_NB_DAILY}show "$yesterday.md" --no-color 2>/dev/null | \
      awk '/^## 📝 今日のサマリー/{flag=1;next}/^## /{flag=0}flag' | \
      sed '/^$/d' | sed 's/^/> /')
  fi
  [[ -z "$yesterday_summary" ]] && yesterday_summary="（前日のサマリーなし）"

  # 一時ファイルに日報を作成（文字化け防止のためヒアドキュメント使用）
  local tmpfile=$(mktemp)
  cat > "$tmpfile" <<EOF
# $date 日報

## 📋 前日のサマリー

$yesterday_summary

## 📋 未完了タスク

\`\`\`
$tasks
\`\`\`

## 📝 今日のサマリー

### Work


### Personal


## 💡 メモ

EOF

  nb ${_NB_DAILY}import "$tmpfile" --filename "$date.md"
  rm "$tmpfile"
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

# -------------
# 週報管理
# -------------

# _nb_get_week_monday - 指定日を含む週の月曜日を取得
_nb_get_week_monday() {
  local target="${1:-$(date +%Y-%m-%d)}"
  local dow=$(date -d "$target" +%u)  # 1=月, 7=日
  date -d "$target - $((dow - 1)) days" +%Y-%m-%d
}

# nbw - 今週の週報を編集
nbw() {
  local monday=$(_nb_get_week_monday)
  local filename="${monday}-weekly.md"

  if nb ${_NB_WEEKLY}show "$filename" &>/dev/null; then
    nb ${_NB_WEEKLY}edit "$filename"
  else
    echo "週報がありません: $filename"
    echo "ヒント: Claude Code で /weekly-report を実行して作成"
  fi
}

# nbws - 週報表示
nbws() {
  local monday
  if [[ -n "$1" ]]; then
    monday=$(_nb_get_week_monday "$1")
  else
    monday=$(_nb_get_week_monday)
  fi
  local filename="${monday}-weekly.md"
  nb ${_NB_WEEKLY}show "$filename"
}

# nbwe - 週報編集
nbwe() {
  local monday
  if [[ -n "$1" ]]; then
    monday=$(_nb_get_week_monday "$1")
  else
    monday=$(_nb_get_week_monday)
  fi
  local filename="${monday}-weekly.md"
  nb ${_NB_WEEKLY}edit "$filename"
}

# nbwl - 週報一覧（fzf）
nbwl() {
  local selected=$(nb ${_NB_WEEKLY}list --no-color | \
    fzf --prompt="週報> " --preview 'nb show $(echo {1} | tr -d "[]")')
  [[ -n "$selected" ]] && nb ${_NB_WEEKLY}show "$(echo "$selected" | awk '{print $1}' | tr -d '[]')"
}

# -------------
# メモ管理
# -------------

# nbn - メモ追加
nbn() {
  local title="" tags=""

  # オプション解析
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--tags) tags="$2"; shift 2 ;;
      -*) echo "不明なオプション: $1"; return 1 ;;
      *) title="$1"; shift ;;
    esac
  done

  # 引数なし → 対話形式
  if [[ -z "$title" ]]; then
    read "title?タイトル: "
    [[ -z "$title" ]] && return 1
    echo -n "タグ (カンマ区切り or Tab選択): "
    read "tags_input?"
    if [[ -z "$tags_input" ]]; then
      tags=$(_nb_select_tags notes)
    else
      tags="$tags_input"
    fi
  fi

  # タグなしなら inbox を付与
  [[ -z "$tags" ]] && tags="inbox"

  # タグをハッシュタグ形式に変換（カンマ → スペース + #）
  local hashtags="#${tags//,/ #}"

  # メモ内容を作成
  local content="# $title

$hashtags

## Description



## References

"

  # nb add で直接作成（--edit でエディタを開く）
  nb ${_NB_NOTES}add --content "$content" --edit

  echo "📝 メモ作成: $title"
}

# nbnl - メモ一覧（fzf選択→編集）
nbnl() {
  local selected=$(nb ${_NB_NOTES}list --no-color | \
    fzf --prompt="メモ> " --preview 'nb notes:show $(echo {1} | tr -d "[]")')
  [[ -z "$selected" ]] && return
  local id=$(echo "$selected" | awk '{print $1}' | tr -d '[]')
  nb ${_NB_NOTES}edit "$id"
}

# nbns - メモ検索
nbns() {
  if [[ -z "$1" ]]; then
    nb ${_NB_NOTES}list --no-color | \
      fzf --prompt="Search> " --preview 'nb notes:show $(echo {1} | tr -d "[]")'
  else
    nb ${_NB_NOTES}search "$1"
  fi
}

# nbntag - タグで絞り込み
nbntag() {
  local tag=$(_nb_get_tags notes | sed 's/^#//' | fzf --prompt="Tag> ")
  [[ -n "$tag" ]] && nb ${_NB_NOTES}search "#$tag"
}

# nbninbox - inbox一覧（整理用）
nbninbox() {
  nb ${_NB_NOTES}search "#inbox"
}
