#!/usr/bin/env zsh
# カスタム関数定義
# zsh.nix の initContent から分離

# ======================
# Navigation
# ======================

# zi - zoxide+fzf（デフォルトのziを上書き）
zi() {
  local result
  result=$(zoxide query -l | fzf --query="$*" --select-1 --exit-0 --height=40% --reverse)
  if [[ -n "$result" ]]; then
    cd "$result"
  fi
}

# gj - ghqリポジトリ選択→cd
gj() {
  local selected_dir
  selected_dir=$(ghq list | fzf --preview 'bat --color=always --style=header,grid $(ghq root)/{}/README.* 2>/dev/null || ls -la $(ghq root)/{}')
  if [ -n "$selected_dir" ]; then
    cd "$(ghq root)/${selected_dir}"
  fi
}

# _gj_widget - ZLEウィジェット版（Ctrl+F）
_gj_widget() {
  local selected_dir
  selected_dir=$(ghq list | fzf --query="$LBUFFER" --preview 'bat --color=always --style=header,grid $(ghq root)/{}/README.* 2>/dev/null || ls -la $(ghq root)/{}')
  if [ -n "$selected_dir" ]; then
    BUFFER="cd $(ghq root)/${selected_dir}"
    zle accept-line
  fi
}
zle -N _gj_widget
bindkey '^f' _gj_widget

# ======================
# fzf utilities
# ======================

# fn - ファイル検索→nvim
fn() {
  local file
  file=$(fzf --prompt="File> " --preview 'cat {}' --preview-window=right:60%)
  if [[ -n "$file" ]]; then
    nvim "$file"
  fi
}

# fd - ディレクトリ検索→cd
fd() {
  local dir
  dir=$(find . -type d -maxdepth 3 2>/dev/null | fzf --prompt="Directory> ")
  if [[ -n "$dir" ]]; then
    cd "$dir"
  fi
}

# fe - ファイル検索→VS Code
fe() {
  local file
  file=$(fzf --prompt="VS Code> " --preview 'cat {}' --preview-window=right:60%)
  if [[ -n "$file" ]]; then
    code "$file"
  fi
}

# fbr - Gitブランチ切替
fbr() {
  local branch
  branch=$(git branch --all | sed 's/^[* ]*//' | fzf --prompt="Branch> ")
  if [[ -n "$branch" ]]; then
    branch=$(echo "$branch" | sed 's#remotes/origin/##')
    git checkout "$branch"
  fi
}

# fga - Git add（複数選択）
fga() {
  local files
  files=$(git status -s | fzf -m --prompt="Git Add> " | awk '{print $2}')
  if [[ -n "$files" ]]; then
    echo "$files" | xargs git add
    echo "Added: $files"
  fi
}

# fgl - Gitログ閲覧
fgl() {
  git log --oneline --color=always | \
    fzf --ansi --prompt="Commit> " --preview 'git show --color=always {1}' | \
    awk '{print $1}'
}

# fgco - コミットcheckout
fgco() {
  local commit
  commit=$(git log --oneline --color=always | \
    fzf --ansi --prompt="Checkout Commit> " --preview 'git show --color=always {1}')
  if [[ -n "$commit" ]]; then
    local hash
    hash=$(echo "$commit" | awk '{print $1}')
    git checkout "$hash"
  fi
}

# fgs - スタッシュ管理
fgs() {
  local stash
  stash=$(git stash list | fzf --prompt="Git Stash> " --preview 'git stash show -p {1}')
  if [[ -n "$stash" ]]; then
    local index
    index=$(echo "$stash" | cut -d: -f1)
    git stash apply "$index"
  fi
}

# pk - プロセスkill
pk() {
  local pid
  pid=$(ps -ef | sed 1d | fzf --prompt="Kill Process> " | awk '{print $2}')
  if [[ -n "$pid" ]]; then
    echo "Killing process $pid"
    kill -9 "$pid"
  fi
}

# fenv - 環境変数閲覧
fenv() {
  local var
  var=$(env | sort | fzf --prompt="Environment> ")
  if [[ -n "$var" ]]; then
    echo "$var"
  fi
}

# fh / falias - zeno abbr + カスタム関数の統合検索（fzfプレビュー付き）
fh() {
  {
    # zeno abbr一覧（[abbr] keyword → snippet 形式）
    grep -E '^\s+(keyword|snippet):' "$ZENO_HOME/config.yml" \
      | paste - - \
      | sed 's/^\s*keyword:\s*/[abbr] /; s/\s*snippet:\s*/ → /'

    # カスタム関数一覧（[func] name - description 形式）
    grep -E '^# [a-zA-Z_]+ - ' ~/.dotfiles/config/zsh/functions.zsh \
      | sed 's/^# /[func] /'
  } | fzf \
      --prompt="Commands> " \
      --preview '
        entry="{}"
        if echo "$entry" | grep -q "^\[func\]"; then
          fn_name=$(echo "$entry" | sed "s/\[func\] //; s/ -.*//" | xargs)
          functions "$fn_name" 2>/dev/null || echo "Function not found: $fn_name"
        else
          abbr_key=$(echo "$entry" | sed "s/\[abbr\] //; s/ →.*//" | xargs)
          grep -A2 "keyword: $abbr_key" "$ZENO_HOME/config.yml" 2>/dev/null
        fi
      ' \
      --preview-window=right:50%
}

# ======================
# Tmux
# ======================

# tms - プロジェクトディレクトリからセッション作成/切替
tms() {
  local selected
  if [[ $# -eq 1 ]]; then
    selected=$1
  else
    selected=$(find ~/src -mindepth 3 -maxdepth 3 -type d 2>/dev/null | fzf --prompt="Project> " --preview 'eza -la --icons --group-directories-first {}')
  fi
  [[ -z $selected ]] && return 0
  local selected_name
  selected_name=$(basename "$selected" | tr . _)
  if [[ -z $TMUX ]]; then
    tmux new-session -As "$selected_name" -c "$selected"
  else
    if ! tmux has-session -t="$selected_name" 2>/dev/null; then
      tmux new-session -ds "$selected_name" -c "$selected"
    fi
    tmux switch-client -t "$selected_name"
  fi
}

# tsw - 既存セッション間を切替
tsw() {
  local session
  session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | \
    fzf --prompt="Switch> " \
        --preview 'tmux capture-pane -pt {} -e -p' \
        --preview-window 'right:60%')
  [[ -n $session ]] && tmux switch-client -t "$session"
}

# tsd - セッションを選択して削除
tsd() {
  local session
  session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -v "^$(tmux display-message -p '#S')$" | \
    fzf --prompt="Kill> " \
        --preview 'tmux capture-pane -pt {} -e -p' \
        --preview-window 'right:60%')
  [[ -n $session ]] && tmux kill-session -t "$session" && echo "Killed session: $session"
}

# ======================
# Misc
# ======================

# yy - yazi（終了時にディレクトリ追従）
yy() {
  local tmp
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# gw3 - ネットワーク共有マウント
gw3() {
  net.exe use W: '\\gw3\all' 2>/dev/null
  sudo mkdir -p /mnt/w
  sudo mount -t drvfs W: /mnt/w 2>/dev/null
  echo "gw3 mounted at /mnt/w"
}

# gw3off - Windows共有ドライブ（gw3）のアンマウント
gw3off() {
  sudo umount /mnt/w 2>/dev/null
  net.exe use W: /delete 2>/dev/null
  echo "gw3 unmounted"
}
