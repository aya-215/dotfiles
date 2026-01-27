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

  # 引数なし → 対話形式（varedでマルチバイト文字対応）
  if [[ -z "$title" ]]; then
    local title="" due="" tags_input="" priority=""
    vared -p "タスク名: " title
    [[ -z "$title" ]] && return 1
    vared -p "期限 (数字/1w/空でスキップ): " due
    vared -p "タグ (カンマ区切り/空でfzf): " tags_input
    if [[ -z "$tags_input" ]]; then
      tags=$(_nb_select_tags)
    else
      tags="$tags_input"
    fi
    vared -p "優先度 (1:high/2:medium/3:low/空で2): " priority
  fi

  # 優先度をパースしてタグに追加
  priority=$(_nb_parse_priority "$priority")
  [[ -n "$priority" ]] && tags="${tags:+$tags,}$priority"

  # 相対日付をパース
  due=$(_nb_parse_date "$due")

  # タグをハッシュタグ形式に変換（カンマ → スペース + #）
  local hashtags=""
  [[ -n "$tags" ]] && hashtags="#${tags//,/ #}"

  # タスク内容を作成
  local content="# [ ] $title

## Tags

$hashtags

## Due

$due

## Description

$desc"

  # nb add で直接作成（--edit でエディタを開く）
  nb ${_NB_TASKS}add --content "$content" --filename "$(date +%Y%m%d%H%M%S).todo.md" --edit

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

# 優先度パース（priority/xxx形式で出力、デフォルトはmedium）
_nb_parse_priority() {
  case "$1" in
    1|high)   echo "priority/high" ;;
    2|medium) echo "priority/medium" ;;
    3|low)    echo "priority/low" ;;
    "")       echo "priority/medium" ;;
    *)        echo "$1" ;;
  esac
}

# タグ取得（notebook指定可能、日本語タグ対応、タスク・メモ両形式対応）
_nb_get_tags() {
  local notebook="${1:-tasks}"
  {
    # タスク形式: ## Tags セクション内のタグ
    awk 'FNR==1{found=0} /^## *Tags$/{found=1;next} found && /^#/{print;found=0}' ~/.nb/$notebook/*.md 2>/dev/null
    # メモ形式: タイトル直下（2行目以降）の #tag 行（各ファイルから1行ずつ）
    awk 'FNR>1 && /^#[^ \t#]/ {print; nextfile}' ~/.nb/$notebook/*.md 2>/dev/null
  } | grep -oP '#[^\s#]+' | sort -u
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
  {
    nb ${_NB_TASKS}todos open --no-color 2>/dev/null | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local id=$(echo "$line" | grep -oE '\[tasks:[0-9]+\]' | grep -oE '[0-9]+')
      [[ -z "$id" ]] && continue
      _nb_format_single_task "$id" sort
    done
  } | sort | cut -d'|' -f2- | if [[ -n "$filter" ]]; then grep -i "$filter"; else cat; fi
}

# nbtd - タスク完了
nbtd() {
  local id=""
  if [[ -z "$1" ]]; then
    # ID付きで一覧生成（選択用）
    local list=$(nb ${_NB_TASKS}todos open --no-color 2>/dev/null | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local tid=$(echo "$line" | grep -oE '\[tasks:[0-9]+\]' | grep -oE '[0-9]+')
      [[ -z "$tid" ]] && continue
      local formatted=$(_nb_format_single_task "$tid")
      [[ -n "$formatted" ]] && echo "${tid}|${formatted#- }"
    done)

    local selected=$(echo "$list" | fzf --prompt="Complete> " \
      --with-nth=2.. --delimiter='|' \
      --preview 'nb tasks:show {1}')
    [[ -z "$selected" ]] && return
    id=$(echo "$selected" | cut -d'|' -f1)
  else
    id="$1"
  fi

  # タスク完了
  nb ${_NB_TASKS}do "$id"

  # 完了日時を追記
  local filepath=$(nb ${_NB_TASKS}show "$id" --path 2>/dev/null)
  if [[ -n "$filepath" && -f "$filepath" ]]; then
    local today=$(date +%Y-%m-%d)
    # ## Description の前に ## Completed セクションを挿入
    sed -i "/^## Description/i ## Completed\n\n$today\n" "$filepath"
  fi

  echo "✅ 完了"
}

# nbtu - タスク完了取消
nbtu() {
  [[ -z "$1" ]] && { echo "使い方: nbtu <ID>"; return 1; }

  # 完了取消
  nb ${_NB_TASKS}undo "$1"

  # Completedセクションを削除（## Completed + 空行 + 日付 + 空行）
  local filepath=$(nb ${_NB_TASKS}show "$1" --path 2>/dev/null)
  if [[ -n "$filepath" && -f "$filepath" ]]; then
    awk '
      /^## Completed$/ { skip=1; next }
      skip && /^## / { skip=0 }
      skip { next }
      { print }
    ' "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
  fi

  echo "↩️ 取消: #$1"
}

# nbte - タスク編集（fzf選択）
nbte() {
  local selected=$(nb ${_NB_TASKS}todos open --no-color | \
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

# nbtag - タグで絞り込み（タスク列挙形式）
nbtag() {
  local tag=$(_nb_get_tags tasks | sed 's/^#//' | fzf --prompt="Tag> ")
  [[ -z "$tag" ]] && return

  {
    nb ${_NB_TASKS}todos open --no-color 2>/dev/null | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local id=$(echo "$line" | grep -oE '\[tasks:[0-9]+\]' | grep -oE '[0-9]+')
      [[ -z "$id" ]] && continue

      local filepath=$(nb ${_NB_TASKS}show "$id" --path 2>/dev/null)
      [[ ! -f "$filepath" ]] && continue

      # タグチェック
      grep -q "#$tag" "$filepath" || continue

      _nb_format_single_task "$id" sort
    done
  } | sort | cut -d'|' -f2-
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

# タスク1件を整形出力（ソート用キー付き）
# 引数2に "sort" を指定するとソート用キー付きで出力
_nb_format_single_task() {
  local id="$1"
  local mode="$2"
  # ファイルパスを取得して直接読む（nb showの幅制限による文字化け回避）
  local filepath=$(nb ${_NB_TASKS}show "$id" --path 2>/dev/null)
  [[ ! -f "$filepath" ]] && return

  # タイトル取得（# [ ] の後）
  local title=$(head -1 "$filepath" | sed 's/^# \[ \] *//')
  [[ -z "$title" ]] && return

  # Due取得
  local due=$(awk '/^## *Due/{found=1;next} found && /^[0-9]/{print;exit}' "$filepath")
  local display_due=""
  local sort_key="9999-99-99"  # 日付なしは最後

  if [[ -n "$due" && "$due" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    display_due=$(date -d "$due" +%m/%d 2>/dev/null)
    sort_key="$due"
  fi

  if [[ "$mode" == "sort" ]]; then
    if [[ -n "$display_due" ]]; then
      echo "${sort_key}|- ${display_due}: ${title}"
    else
      echo "${sort_key}|- ${title}"
    fi
  else
    if [[ -n "$display_due" ]]; then
      echo "- ${display_due}: ${title}"
    else
      echo "- ${title}"
    fi
  fi
}

# メモ1件を整形出力（タイトル + タグ）
_nb_format_single_note() {
  local id="$1"
  local filepath=$(nb ${_NB_NOTES}show "$id" --path 2>/dev/null)
  [[ ! -f "$filepath" ]] && return

  # タイトル取得（# の後）
  local title=$(head -1 "$filepath" | sed 's/^# *//')
  [[ -z "$title" ]] && return

  # タグ取得（2行目以降で#から始まる行、日本語対応）
  local tags=$(awk 'NR>1 && /^#[^ \t#]/ {print; exit}' "$filepath")

  if [[ -n "$tags" ]]; then
    echo "${title}  ${tags}"
  else
    echo "${title}"
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

    # ファイルパスを取得して直接読む（文字化け回避）
    local filepath=$(nb ${_NB_TASKS}show "$id" --path 2>/dev/null)
    [[ ! -f "$filepath" ]] && continue

    local tags=$(awk '/^## *Tags/{found=1;next} found && /^#/{print;exit}' "$filepath")
    local due=$(awk '/^## *Due/{found=1;next} found && /^[0-9]/{print;exit}' "$filepath")

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

# _nb_get_latest_daily - 最新の日報ファイル名を取得（今日を除く）
_nb_get_latest_daily() {
  local today=$(date +%Y-%m-%d)
  ls -1 ~/.nb/daily/*.md 2>/dev/null | grep -v '.templates' | \
    xargs -I{} basename {} .md | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | \
    grep -v "^$today$" | sort -r | head -1
}

# _nb_get_second_latest_daily - 2番目に新しい日報ファイル名を取得
_nb_get_second_latest_daily() {
  ls -1 ~/.nb/daily/*.md 2>/dev/null | grep -v '.templates' | \
    xargs -I{} basename {} .md | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | \
    sort -r | sed -n '2p'
}

# _nb_format_schedule_date - gcalcliの日付をMM-DD (曜日)形式に変換し、日付ごとにグループ化
_nb_format_schedule_date() {
  awk '{
    # 曜日の変換マップ
    day_map["Sun"] = "日"; day_map["Mon"] = "月"; day_map["Tue"] = "火";
    day_map["Wed"] = "水"; day_map["Thu"] = "木"; day_map["Fri"] = "金"; day_map["Sat"] = "土";

    # 月の変換マップ
    month_map["Jan"] = "01"; month_map["Feb"] = "02"; month_map["Mar"] = "03";
    month_map["Apr"] = "04"; month_map["May"] = "05"; month_map["Jun"] = "06";
    month_map["Jul"] = "07"; month_map["Aug"] = "08"; month_map["Sep"] = "09";
    month_map["Oct"] = "10"; month_map["Nov"] = "11"; month_map["Dec"] = "12";

    # 日付行の場合 (例: "Thu Jan 08  10:00  テスト" or "Thu Jan 08         成人の日")
    if ($1 in day_map && $2 in month_map && $3 ~ /^[0-9]+$/) {
      date_str = month_map[$2] "-" $3 " (" day_map[$1] ")";

      # 残りの部分を取得
      rest = substr($0, index($0, $4));
      gsub(/^[ \t]+/, "", rest);  # 先頭の空白を削除

      # 時刻があるかチェック (HH:MM形式)
      if (rest ~ /^[0-9]{1,2}:[0-9]{2}/) {
        # 時刻とイベント名を分離
        match(rest, /^[0-9]{1,2}:[0-9]{2}/);
        time_str = substr(rest, RSTART, RLENGTH);
        event = substr(rest, RLENGTH + 1);
        gsub(/^[ \t]+/, "", event);  # イベント名の先頭空白削除
        printf "%s\n  %s %s\n", date_str, time_str, event;
      } else if (rest != "") {
        # 終日イベント
        printf "%s\n  終日  %s\n", date_str, rest;
      } else {
        # 日付のみ（イベント名なし）
        printf "%s\n", date_str;
      }
    } else if ($0 ~ /^[ \t]+[0-9]{1,2}:[0-9]{2}/) {
      # 継続行（同じ日の次のイベント）
      gsub(/^[ \t]+/, "");  # 先頭の空白を削除
      match($0, /^[0-9]{1,2}:[0-9]{2}/);
      time_str = substr($0, RSTART, RLENGTH);
      event = substr($0, RLENGTH + 1);
      gsub(/^[ \t]+/, "", event);
      printf "  %s %s\n", time_str, event;
    } else if ($0 ~ /^[ \t]+/) {
      # 継続行（終日イベント）
      gsub(/^[ \t]+/, "");
      printf "  終日  %s\n", $0;
    } else {
      print $0;
    }
  }'
}

# _nb_get_today_schedule - 今日のスケジュールを取得（日付行なし）
_nb_get_today_schedule() {
  if ! command -v gcalcli &>/dev/null; then
    echo "（gcalcliが未インストール）"
    return
  fi
  local schedule=$(gcalcli agenda "today" "tomorrow" --nocolor --nodeclined 2>/dev/null | \
    sed 's/\x1b\[[0-9;]*m//g' | grep -v '^$' | _nb_format_schedule_date | \
    grep -v '^[0-9][0-9]-[0-9][0-9] ' | sed 's/No Events Found\.\.\./予定なし/g' | head -20)
  [[ -z "$schedule" ]] && schedule="予定なし"
  echo "$schedule"
}

# _nb_get_week_schedule - 今日から7日後までのスケジュールを取得
_nb_get_week_schedule() {
  if ! command -v gcalcli &>/dev/null; then
    echo "（gcalcliが未インストール）"
    return
  fi
  # 今日から7日後までの予定を取得
  local end_date=$(date -d "+7 days" +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d)
  local schedule=$(gcalcli agenda "tomorrow" "$end_date" --nocolor --nodeclined 2>/dev/null | \
    sed 's/\x1b\[[0-9;]*m//g' | grep -v '^$' | _nb_format_schedule_date | \
    sed 's/No Events Found\.\.\./予定なし/g' | head -30)
  [[ -z "$schedule" ]] && schedule="予定なし"
  echo "$schedule"
}

# nbd - 今日の日報作成/編集
nbd() {
  local date=$(date +%Y-%m-%d)
  local template_path="$HOME/.nb/daily/.templates/daily.md"

  # 既に存在する場合は編集
  if nb ${_NB_DAILY}show "$date.md" &>/dev/null; then
    nb ${_NB_DAILY}edit "$date.md"
    return
  fi

  # 未完了タスク（nbネイティブから取得、整形）
  local tasks=$(_nb_format_tasks_for_daily)
  [[ -z "$tasks" ]] && tasks="（未完了タスクなし）"

  # 最新の日報（今日を除く）からサマリーを取得
  local latest_daily=$(_nb_get_latest_daily)
  local yesterday_summary=""
  if [[ -n "$latest_daily" ]] && nb ${_NB_DAILY}show "$latest_daily.md" &>/dev/null; then
    yesterday_summary=$(nb ${_NB_DAILY}show "$latest_daily.md" --no-color 2>/dev/null | \
      awk '/^## 📝 今日のサマリー/{flag=1;next}/^## /{flag=0}flag' | \
      sed '/^$/d' | sed 's/^/> /')
  fi
  [[ -z "$yesterday_summary" ]] && yesterday_summary="（前日のサマリーなし）"

  # スケジュール取得
  local today_schedule=$(_nb_get_today_schedule)
  local week_schedule=$(_nb_get_week_schedule)

  # 一時ファイルに日報を作成（文字化け防止のためヒアドキュメント使用）
  local tmpfile=$(mktemp)
  cat > "$tmpfile" <<EOF
# $date 日報

## 📋 前日のサマリー

$yesterday_summary

## 📅 スケジュール

**今日**

$today_schedule

**1週間**

$week_schedule

## 📋 未完了タスク

$tasks

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

# nbdy - 最新の1つ前の日報表示
nbdy() {
  local second_latest=$(_nb_get_second_latest_daily)
  if [[ -n "$second_latest" ]]; then
    nb ${_NB_DAILY}show "$second_latest.md"
  else
    echo "前回の日報がありません"
  fi
}

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

  # 引数なし → 対話形式（varedでマルチバイト文字対応）
  if [[ -z "$title" ]]; then
    local title="" tags_input=""
    vared -p "タイトル: " title
    [[ -z "$title" ]] && return 1
    vared -p "タグ (カンマ区切り/空でfzf): " tags_input
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
  # ID付きで一覧生成（選択用）
  local list=$(nb ${_NB_NOTES}list --no-color 2>/dev/null | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local id=$(echo "$line" | grep -oE '\[notes:[0-9]+\]' | grep -oE '[0-9]+')
    [[ -z "$id" ]] && continue
    local formatted=$(_nb_format_single_note "$id")
    [[ -n "$formatted" ]] && echo "${id}|${formatted}"
  done)

  local selected=$(echo "$list" | fzf --prompt="メモ> " \
    --with-nth=2.. --delimiter='|' \
    --preview 'nb notes:show {1}')
  [[ -z "$selected" ]] && return

  local id=$(echo "$selected" | cut -d'|' -f1)
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
