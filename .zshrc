# Profiling (コメント解除して起動時間を計測)
# zmodload zsh/zprof

# PATH configuration
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.deno/bin:$PATH"

# WindowsのPATHをフィルタリング（System32のみ残す）
export PATH=$(echo $PATH | tr ':' '\n' | grep -v '^/mnt/c/' | tr '\n' ':' | sed 's/:$//')
export PATH="$PATH:/mnt/c/Windows/System32"

# 必要に応じてコメント解除
# export PATH="$PATH:/mnt/c/Users/368/AppData/Local/Programs/Microsoft VS Code/bin"  # VS Code
# export PATH="$PATH:/mnt/c/Program Files/Docker/Docker/resources/bin"  # Docker

# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME=""  # カスタムプロンプトを使用するため無効化

# Plugins
plugins=(
  git
  fzf-tab
  zsh-autosuggestions
  zsh-syntax-highlighting
  you-should-use
)

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Starship prompt
eval "$(starship init zsh)"

# NVM configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
eval "$(zoxide init zsh)"

# zeno.zsh configuration (必要時に自動読み込み)
# TabやSpaceが押された時に初めて読み込む
typeset -g _zeno_loaded=0

_zeno_lazy_init() {
  if [[ $_zeno_loaded -eq 0 && -f ~/src/github.com/yuki-yano/zeno.zsh/zeno.zsh ]]; then
    # 設定ファイルのパス
    export ZENO_HOME="$HOME/.config/zeno"
    export ZENO_ENABLE_SOCK=1
    export ZENO_GIT_CAT="bat --color=always"
    export ZENO_GIT_TREE="eza --tree"

    source ~/src/github.com/yuki-yano/zeno.zsh/zeno.zsh

    # キーバインディング設定
    # スペースは通常動作、Ctrl+Spaceでスニペット展開
    bindkey '^ ' zeno-auto-snippet            # Ctrl+Space: スニペット展開
    bindkey '^i' zeno-completion              # Tab: 補完
    bindkey '^r' zeno-history-selection       # Ctrl-R: 履歴検索
    bindkey '^x^s' zeno-insert-snippet        # Ctrl-X Ctrl-S: スニペット挿入

    _zeno_loaded=1
  fi
}

# 遅延読み込み用のトリガー関数
# スペースキーは通常動作するため、TabとCtrl-Rのみトリガー設定

_zeno_trigger_tab() {
  _zeno_lazy_init
  zle zeno-completion
}

_zeno_trigger_ctrl_r() {
  _zeno_lazy_init
  zle zeno-history-selection
}

# ZLE widgetとして登録
zle -N _zeno_trigger_tab
zle -N _zeno_trigger_ctrl_r

# 最初は遅延読み込みトリガーをバインド
# 一度読み込まれたら、zeno.zsh側が正しいキーバインドに上書きする
bindkey '^i' _zeno_trigger_tab
bindkey '^r' _zeno_trigger_ctrl_r

# Override zi to use fzf fuzzy search with initial query
zi() {
  local result
  result=$(zoxide query -l | fzf --query="$*" --select-1 --exit-0 --height=40% --reverse)
  if [[ -n "$result" ]]; then
    cd "$result"
  fi
}

# ======================
# Aliases (from PowerShell config)
# ======================
alias vim='nvim'
alias vi='nvim'
alias v='nvim'
alias c='claude'

# Backup
alias bak='~/.dotfiles/scripts/backup/backup-wsl-to-windows.sh'

# ======================
# eza aliases (ls replacement)
# ======================
alias ls='eza --icons --group-directories-first'
alias l='eza --icons --group-directories-first'
alias ll='eza -l --icons --group-directories-first --git'
alias la='eza -la --icons --group-directories-first --git'
alias lt='eza --tree --level=2 --icons'
alias lta='eza --tree --level=2 --icons -a'
alias lg='eza -l --icons --group-directories-first --git --git-ignore'

# NPM shortcuts with 0.0.0.0 host
alias npmd='npm run dev -- -H 0.0.0.0'
alias npms='npm run storybook -- --host 0.0.0.0'

# ======================
# fzf-based functions (from PowerShell config)
# ======================

# fn - Find file and open in nvim
fn() {
  local file
  file=$(fzf --prompt="File> " --preview 'cat {}' --preview-window=right:60%)
  if [[ -n "$file" ]]; then
    nvim "$file"
  fi
}

# fd - Find directory and cd into it
fd() {
  local dir
  dir=$(find . -type d -maxdepth 3 2>/dev/null | fzf --prompt="Directory> ")
  if [[ -n "$dir" ]]; then
    cd "$dir"
  fi
}

# fe - Find file and open in VS Code
fe() {
  local file
  file=$(fzf --prompt="VS Code> " --preview 'cat {}' --preview-window=right:60%)
  if [[ -n "$file" ]]; then
    code "$file"
  fi
}

# fbr - Git branch switcher with fzf (renamed to avoid conflict)
fbr() {
  local branch
  branch=$(git branch --all | sed 's/^[* ]*//' | fzf --prompt="Branch> ")
  if [[ -n "$branch" ]]; then
    branch=$(echo "$branch" | sed 's#remotes/origin/##')
    git checkout "$branch"
  fi
}

# fga - Git add interactive with fzf (renamed to avoid conflict)
fga() {
  local files
  files=$(git status -s | fzf -m --prompt="Git Add> " | awk '{print $2}')
  if [[ -n "$files" ]]; then
    echo "$files" | xargs git add
    echo "Added: $files"
  fi
}

# fgl - Git log viewer with fzf (renamed to avoid conflict)
fgl() {
  git log --oneline --color=always | \
    fzf --ansi --prompt="Commit> " --preview 'git show --color=always {1}' | \
    awk '{print $1}'
}

# fgco - Git checkout commit with fzf (renamed to avoid conflict)
fgco() {
  local commit
  commit=$(git log --oneline --color=always | \
    fzf --ansi --prompt="Checkout Commit> " --preview 'git show --color=always {1}')
  if [[ -n "$commit" ]]; then
    local hash=$(echo "$commit" | awk '{print $1}')
    git checkout "$hash"
  fi
}

# fgs - Git stash manager with fzf (renamed to avoid conflict)
fgs() {
  local stash
  stash=$(git stash list | fzf --prompt="Git Stash> " --preview 'git stash show -p {1}')
  if [[ -n "$stash" ]]; then
    local index=$(echo "$stash" | cut -d: -f1)
    git stash apply "$index"
  fi
}

# pk - Process killer with fzf
pk() {
  local pid
  pid=$(ps -ef | sed 1d | fzf --prompt="Kill Process> " | awk '{print $2}')
  if [[ -n "$pid" ]]; then
    echo "Killing process $pid"
    kill -9 "$pid"
  fi
}

# fenv - Environment variable viewer with fzf
fenv() {
  local var
  var=$(env | sort | fzf --prompt="Environment> ")
  if [[ -n "$var" ]]; then
    echo "$var"
  fi
}

# falias - Alias viewer with fzf
falias() {
  alias | fzf --prompt="Alias> "
}

# ghq - Repository manager with fzf
# Command line version
gj() {
  local selected_dir=$(ghq list | fzf --preview 'bat --color=always --style=header,grid $(ghq root)/{}/README.* 2>/dev/null || ls -la $(ghq root)/{}')
  if [ -n "$selected_dir" ]; then
    cd "$(ghq root)/${selected_dir}"
  fi
}

# ZLE widget version for keybinding
_gj_widget() {
  local selected_dir=$(ghq list | fzf --query="$LBUFFER" --preview 'bat --color=always --style=header,grid $(ghq root)/{}/README.* 2>/dev/null || ls -la $(ghq root)/{}')
  if [ -n "$selected_dir" ]; then
    BUFFER="cd $(ghq root)/${selected_dir}"
    zle accept-line
  fi
}
zle -N _gj_widget
bindkey '^f' _gj_widget

# Start in home directory
cd ~


eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
export EDITOR="vim"
export PATH="$HOME/.local/bin:$PATH"

# ======================
# nb 日報管理関数
# ======================

# nbd - 今日の日報を作成（タスク自動連携）
nbd() {
  local date=$(date +%Y-%m-%d)
  local timestamp=$(date '+%a %b %d %H:%M:%S %Z %Y')
  local template="$HOME/.nb/daily/.templates/daily.md"
  local tasks_dir="$HOME/.nb/tasks"

  # 既に存在する場合は編集モードで開く
  if nb daily:show "$date.md" &>/dev/null; then
    echo "📝 既存の日報を編集: daily:$date.md"
    nb daily:edit "$date.md"
    return
  fi

  echo "📋 日報作成の準備中..."
  echo ""

  # 1. inbox.mdを最新化
  echo "🔄 タスク一覧を更新中..."
  nbtsync 2>/dev/null

  # 2. inbox.mdから今週のタスクを収集
  local inbox="$tasks_dir/inbox.md"

  # 今日・期限切れのタスクを抽出
  awk '
    /## 🔥 今日・期限切れ/ { in_section = 1; next }
    in_section && /^## / { in_section = 0 }
    in_section && /^- \[ \]/ {
      sub(/ → \[\[tasks:.*\]\]$/, "")
      print
    }
  ' "$inbox" > /tmp/today_tasks.txt

  # 今週中のタスクを抽出
  awk '
    /## 📅 今週中/ { in_section = 1; next }
    in_section && /^## / { in_section = 0 }
    in_section && /^- \[ \]/ {
      sub(/ → \[\[tasks:.*\]\]$/, "")
      print
    }
  ' "$inbox" >> /tmp/today_tasks.txt

  # 3. 今週のタスクを表示
  echo ""
  echo "📅 今週のタスク:"
  echo "========================="
  if [[ -s /tmp/today_tasks.txt ]]; then
    cat /tmp/today_tasks.txt
  else
    echo "なし"
  fi
  echo ""

  # 4. テンプレートから日報を作成
  if [ -f "$template" ]; then
    local content=$(sed -e "s/{{DATE}}/$date/g" -e "s/{{TIMESTAMP}}/$timestamp/g" "$template")

    # 今日のタスクを自動挿入
    if [[ -s /tmp/today_tasks.txt ]]; then
      local task_list=$(cat /tmp/today_tasks.txt)
      content=$(echo "$content" | awk -v tasks="$task_list" '
        /^## 📋 今日のタスク/ {
          print
          getline
          print
          print tasks
          next
        }
        { print }
      ')
    fi

    nb daily:add "$date.md" --content "$content"
    echo "✅ 日報作成: daily:$date.md"
    echo ""
    echo "💡 ヒント: inbox.mdの確認は 'nbi' コマンド"
    echo ""
    nb daily:edit "$date.md"
  else
    echo "❌ テンプレートが見つかりません: $template"
  fi

  # クリーンアップ
  rm -f /tmp/today_tasks.txt
}

# nbdo - 今日の日報を表示
nbdo() {
  local date=$(date +%Y-%m-%d)
  nb daily:show "$date.md"
}

# nbde - 今日の日報を編集
nbde() {
  local date=$(date +%Y-%m-%d)
  nb daily:edit "$date.md"
}

# nbdy - 昨日の日報を表示
nbdy() {
  local yesterday=$(date -d yesterday +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
  nb daily:show "$yesterday.md"
}

# nbdl - 日報一覧をfzfで選択して表示
nbdl() {
  local selected
  selected=$(nb daily:list --no-color | grep -E "^\[" | fzf --prompt="日報> " --preview "nb daily:show {2}")
  if [[ -n "$selected" ]]; then
    local id=$(echo "$selected" | awk '{print $1}' | tr -d '[]')
    nb daily:show "$id"
  fi
}

# nbi - inbox（タスク受信箱）を編集
nbi() {
  nb tasks:edit inbox.md
}

# ======================
# nb タスク管理関数（個別ファイル + 自動一覧）
# ======================

# nbtf - タスクフォルダ作成
nbtf() {
  local folder="$1"

  if [[ -z "$folder" ]]; then
    echo "使い方: nbtf \"フォルダ名\""
    echo "例: nbtf \"プロジェクトA\""
    return 1
  fi

  mkdir -p "$HOME/.nb/tasks/$folder"
  echo "✅ フォルダ作成: tasks/$folder/"
  echo "使い方: nbt \"タスク名\" \"$folder\""
}

# nbtfl - タスクフォルダ一覧
nbtfl() {
  local tasks_dir="$HOME/.nb/tasks"

  echo "📁 タスクフォルダ一覧"
  echo "===================="
  echo ""

  find "$tasks_dir" -mindepth 1 -maxdepth 1 -type d -not -name ".*" | while read -r folder; do
    local folder_name=$(basename "$folder")
    local count=$(find "$folder" -name "*.md" -not -name "inbox.md" 2>/dev/null | wc -l)
    echo "📁 $folder_name ($count タスク)"
  done

  echo ""
  echo "フォルダ作成: nbtf \"フォルダ名\""
}

# nbt - タスク追加（フォルダ対応・frontmatter付き）
nbt() {
  local title="$1"
  local folder="$2"

  if [[ -z "$title" ]]; then
    echo "使い方: nbt \"タスク名\" [フォルダ名]"
    echo "例: nbt \"資料作成\" \"プロジェクトA\""
    echo "例: nbt \"買い物\"  # フォルダなし（tasks直下）"
    return 1
  fi

  # 対話形式で情報入力
  echo "📝 タスク追加: $title"
  echo ""

  # フォルダが指定されていない場合、fzfで選択
  if [[ -z "$folder" ]]; then
    local tasks_dir="$HOME/.nb/tasks"

    # fzfが使える場合はfzfで選択、なければ対話形式
    if command -v fzf &>/dev/null; then
      local folders=$(find "$tasks_dir" -mindepth 1 -maxdepth 1 -type d -not -name ".*" -exec basename {} \; 2>/dev/null)

      if [[ -n "$folders" ]]; then
        echo "📁 フォルダを選択（Escでスキップ→tasks直下）"
        folder=$(echo "$folders\n📁 tasks直下（フォルダなし）" | fzf --prompt="Task Folder> " --height=40% --reverse --header="フォルダ選択")

        # "tasks直下"が選ばれた場合は空に
        [[ "$folder" == "📁 tasks直下（フォルダなし）" ]] && folder=""
      fi
    else
      # fzfがない場合は従来の対話形式
      local folders=($(find "$tasks_dir" -mindepth 1 -maxdepth 1 -type d -not -name ".*" -exec basename {} \; 2>/dev/null))

      if [[ ${#folders[@]} -gt 0 ]]; then
        echo "既存のフォルダ:"
        for f in "${folders[@]}"; do
          echo "  - $f"
        done
        echo ""
      fi

      read "folder?フォルダ (空白で tasks直下): "
    fi
  fi

  read "due?期限 (YYYY-MM-DD, 空白でスキップ): "
  read "tags?タグ (カンマ区切り, 例: 仕事,緊急): "
  read "priority?優先度 (high/medium/low, デフォルト: medium): "

  # デフォルト値設定
  [[ -z "$due" ]] && due="未定"
  [[ -z "$tags" ]] && tags="未分類"
  [[ -z "$priority" ]] && priority="medium"

  local created=$(date +%Y-%m-%d)
  local template="$HOME/.nb/tasks/.templates/task.md"

  # フォルダパスを構築
  local file_path="$title.md"
  if [[ -n "$folder" ]]; then
    # フォルダが存在しない場合は作成
    mkdir -p "$HOME/.nb/tasks/$folder"
    file_path="$folder/$title.md"
  fi

  # テンプレートから作成
  if [[ -f "$template" ]]; then
    # テンプレートの内容を変数に格納
    local content=$(sed -e "s/{{DUE_DATE}}/$due/g" \
        -e "s/{{TAGS}}/$tags/g" \
        -e "s/{{TITLE}}/$title/g" \
        -e "s/{{CREATED_DATE}}/$created/g" \
        -e "s/priority: medium/priority: $priority/g" \
        "$template")

    # nbにファイルを追加
    echo "$content" | nb tasks:add "$file_path"

    echo "✅ タスク作成: tasks:$file_path"
    nb tasks:edit "$file_path"

    # inbox.mdを自動更新
    nbtsync
  else
    echo "❌ テンプレートが見つかりません: $template"
  fi
}

# nbtl - タスク一覧表示（期限順・タグフィルタ可能）
nbtl() {
  local filter="$1"
  local tasks_dir="$HOME/.nb/tasks"

  echo "📋 タスク一覧"
  echo "===================="
  echo ""

  # .mdファイルを検索（テンプレート除外）
  find "$tasks_dir" -name "*.md" -not -path "*/.templates/*" -not -name "inbox.md" -not -name "2025-*.md" | while read -r file; do
    # frontmatterから情報抽出
    local due=$(grep "^due:" "$file" | cut -d: -f2- | xargs)
    local tags=$(grep "^tags:" "$file" | cut -d: -f2- | xargs)
    local task_status=$(grep "^status:" "$file" | cut -d: -f2- | xargs)
    local priority=$(grep "^priority:" "$file" | cut -d: -f2- | xargs)
    local title=$(basename "$file" .md)

    # フォルダ名を抽出
    local folder_path=$(dirname "$file")
    local folder_name=$(basename "$folder_path")
    [[ "$folder_name" == "tasks" ]] && folder_name="📁-"  # tasks直下の場合

    # フィルタリング
    if [[ -n "$filter" ]] && [[ ! "$tags" =~ "$filter" ]]; then
      continue
    fi

    # statusがdone以外のものだけ表示
    if [[ "$task_status" == "done" ]]; then
      continue
    fi

    # 優先度アイコン
    local priority_icon="🟢"
    [[ "$priority" == "high" ]] && priority_icon="🔴"
    [[ "$priority" == "medium" ]] && priority_icon="🟡"

    # 期限表示
    local due_display="$due"
    if [[ "$due" != "未定" ]]; then
      # 今日との差分を計算
      local today=$(date +%Y-%m-%d)
      local days_diff=$(( ($(date -d "$due" +%s) - $(date -d "$today" +%s)) / 86400 ))

      if [[ $days_diff -lt 0 ]]; then
        due_display="$due ⚠️ 期限切れ"
      elif [[ $days_diff -eq 0 ]]; then
        due_display="$due 🔥 今日"
      elif [[ $days_diff -le 3 ]]; then
        due_display="$due ⏰ あと${days_diff}日"
      fi
    fi

    echo "$priority_icon $due_display [$tags] $folder_name/$title"
  done | sort

  echo ""
  echo "使い方:"
  echo "  nbtl          - 全タスク表示"
  echo "  nbtl 仕事      - タグでフィルタ"
  echo "  nbtfl         - フォルダ一覧"
  echo "  nb tasks:edit フォルダ/タスク名.md  - タスク編集"
}

# nbtsync - inbox.mdを個別ファイルから自動生成
nbtsync() {
  local tasks_dir="$HOME/.nb/tasks"
  local inbox="$tasks_dir/inbox.md"

  echo "🔄 inbox.mdを自動生成中..."

  # ヘッダー作成
  cat > "$inbox" << 'EOF'
# タスク受信箱

> 自動生成（nbtsyncコマンド）
> 個別タスクファイルから生成されています

EOF

  # 期限別にセクション作成
  echo "## 🔥 今日・期限切れ" >> "$inbox"
  echo "" >> "$inbox"

  find "$tasks_dir" -name "*.md" -not -path "*/.templates/*" -not -path "*/.git/*" -not -name "inbox.md" -not -name "2025-*.md" | while read -r file; do
    local due=$(grep "^due:" "$file" | cut -d: -f2- | xargs)
    local task_status=$(grep "^status:" "$file" | cut -d: -f2- | xargs)
    local title=$(basename "$file" .md)

    [[ "$task_status" == "done" ]] && continue

    if [[ "$due" != "未定" ]]; then
      local today=$(date +%Y-%m-%d)
      local days_diff=$(( ($(date -d "$due" +%s) - $(date -d "$today" +%s)) / 86400 ))

      if [[ $days_diff -le 0 ]]; then
        echo "- [ ] $title 📅 $due → [[tasks:$title.md]]" >> "$inbox"
      fi
    fi
  done

  echo "" >> "$inbox"
  echo "## 📅 今週中" >> "$inbox"
  echo "" >> "$inbox"

  find "$tasks_dir" -name "*.md" -not -path "*/.templates/*" -not -path "*/.git/*" -not -name "inbox.md" -not -name "2025-*.md" | while read -r file; do
    local due=$(grep "^due:" "$file" | cut -d: -f2- | xargs)
    local task_status=$(grep "^status:" "$file" | cut -d: -f2- | xargs)
    local tags=$(grep "^tags:" "$file" | cut -d: -f2- | xargs)
    local title=$(basename "$file" .md)

    [[ "$task_status" == "done" ]] && continue

    if [[ "$due" != "未定" ]]; then
      local today=$(date +%Y-%m-%d)
      local days_diff=$(( ($(date -d "$due" +%s) - $(date -d "$today" +%s)) / 86400 ))

      if [[ $days_diff -gt 0 ]] && [[ $days_diff -le 7 ]]; then
        echo "- [ ] $title 📅 $due $tags → [[tasks:$title.md]]" >> "$inbox"
      fi
    fi
  done

  echo "" >> "$inbox"
  echo "## 📋 期限未定" >> "$inbox"
  echo "" >> "$inbox"

  find "$tasks_dir" -name "*.md" -not -path "*/.templates/*" -not -path "*/.git/*" -not -name "inbox.md" -not -name "2025-*.md" | while read -r file; do
    local due=$(grep "^due:" "$file" | cut -d: -f2- | xargs)
    local task_status=$(grep "^status:" "$file" | cut -d: -f2- | xargs)
    local tags=$(grep "^tags:" "$file" | cut -d: -f2- | xargs)
    local title=$(basename "$file" .md)

    [[ "$task_status" == "done" ]] && continue

    if [[ "$due" == "未定" ]]; then
      echo "- [ ] $title $tags → [[tasks:$title.md]]" >> "$inbox"
    fi
  done

  echo "✅ inbox.md を更新しました"
  echo "確認: nbi"
}

# nbtdone - タスクを完了にする（フォルダ対応）
nbtdone() {
  local task="$1"

  if [[ -z "$task" ]]; then
    echo "使い方: nbtdone \"タスク名\" または nbtdone \"フォルダ/タスク名\""
    echo "例: nbtdone \"資料作成\""
    echo "例: nbtdone \"プロジェクトA/タスク1\""
    return 1
  fi

  # .md拡張子がない場合は追加
  [[ "$task" != *.md ]] && task="$task.md"

  local file="$HOME/.nb/tasks/$task"

  # ファイルが見つからない場合、全検索
  if [[ ! -f "$file" ]]; then
    local found=$(find "$HOME/.nb/tasks" -name "$(basename "$task")" -not -path "*/.templates/*" | head -1)
    if [[ -n "$found" ]]; then
      file="$found"
    else
      echo "❌ タスクが見つかりません: $task"
      return 1
    fi
  fi

  # statusをdoneに変更
  sed -i 's/^status: todo/status: done/' "$file"
  echo "✅ タスク完了: $(basename "$file" .md)"

  # inbox.mdを自動更新
  nbtsync
}
