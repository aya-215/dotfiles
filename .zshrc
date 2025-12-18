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
  you-should-use
  zsh-autosuggestions
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

# zeno.zsh configuration
if [[ -f ~/src/github.com/yuki-yano/zeno.zsh/zeno.zsh ]]; then
  export ZENO_HOME="$HOME/.config/zeno"
  export ZENO_ENABLE_SOCK=1
  export ZENO_GIT_CAT="bat --color=always"
  export ZENO_GIT_TREE="eza --tree"

  source ~/src/github.com/yuki-yano/zeno.zsh/zeno.zsh

  # キーバインディング設定
  bindkey '^ ' zeno-auto-snippet            # Ctrl+Space: スニペット展開
  bindkey '^i' zeno-completion              # Tab: 補完
  bindkey '^r' zeno-history-selection       # Ctrl-R: 履歴検索
  bindkey '^x^s' zeno-insert-snippet        # Ctrl-X Ctrl-S: スニペット挿入
fi

# fast-syntax-highlighting（zeno.zshの後に読み込む）
source ~/src/github.com/zdharma-continuum/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

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

# nb関連関数（日報・タスク管理）
[[ -f ~/.config/nb/functions.zsh ]] && source ~/.config/nb/functions.zsh
