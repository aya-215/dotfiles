{ config, pkgs, ... }:

{
  # 環境変数（shell.nixから移行）
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    LANG = "ja_JP.UTF-8";
    BROWSER = "wslview";
    CLAUDE_CODE_SKIP_WINDOWS_PROFILE = "1";
    USERPROFILE = "/mnt/c/Users/368";
  };

  # PATH設定（shell.nixから移行）
  home.sessionPath = [
    "$HOME/.cargo/bin"
    "$HOME/.local/bin"
  ];

  programs.zsh = {
    enable = true;

    # .zshenvに追加（PATH設定）
    envExtra = ''
      # Nix profile PATH
      export PATH="$HOME/.nix-profile/bin:$PATH"
    '';

    # Nixパッケージ経由のプラグイン
    plugins = [
      {
        name = "you-should-use";
        src = pkgs.zsh-you-should-use;
        file = "share/zsh/plugins/you-should-use/you-should-use.plugin.zsh";
      }
      {
        name = "zsh-autosuggestions";
        src = pkgs.zsh-autosuggestions;
        file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
      }
    ];

    # エイリアスは zeno.zsh abbr に移行済み（config/zeno/config.yml）
    shellAliases = {};

    # 補完初期化（-C: セキュリティチェックスキップで高速化）
    completionInit = "autoload -Uz compinit && compinit -C";

    # 履歴設定
    history = {
      size = 10000;
      save = 10000;
      path = "$HOME/.zsh_history";
    };

    # .zshrcに追加（メイン部分）
    initContent = ''
      # ======================
      # Zsh options
      # ======================
      setopt INTERACTIVE_COMMENTS # コメント許可
      setopt NO_BEEP              # ビープ音なし
      setopt HIST_REDUCE_BLANKS   # ヒストリの余分な空白を削除
      setopt HIST_VERIFY          # !展開を確認

      # ======================
      # Completion styles
      # ======================
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case-insensitive
      zstyle ':completion:*' menu select
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"

      # ======================
      # Key bindings（ターミナル基本操作）
      # ======================
      bindkey '^[[H'    beginning-of-line   # Home: 行頭へ
      bindkey '^[[F'    end-of-line         # End: 行末へ
      bindkey '^[[3~'   delete-char         # Delete: カーソル右の文字削除
      bindkey '^[[1;5C' forward-word        # Ctrl+Right: 単語単位で右へ
      bindkey '^[[1;5D' backward-word       # Ctrl+Left: 単語単位で左へ

      # fnm (Node version manager)
      eval "$(fnm env --use-on-cd)"

      # PATH configuration
      export PATH=$(echo $PATH | tr ':' '\n' | grep -v '^/mnt/c/' | tr '\n' ':' | sed 's/:$//')
      export PATH="$PATH:/mnt/c/Windows/System32"
      export PATH="$PATH:/mnt/c/Users/368/AppData/Local/Programs/Microsoft VS Code/bin"

      # WezTerm OSC 7（ディレクトリ変更をWeztermに通知）
      __wezterm_osc7() {
        printf "\033]7;file://%s%s\033\\" "''${HOST}" "''${PWD}"
      }
      autoload -Uz add-zsh-hook
      add-zsh-hook chpwd __wezterm_osc7
      __wezterm_osc7

      # zoxide (スマートcd)
      eval "$(zoxide init zsh)"

      # fzf (ファジーファインダー)
      [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

      # zi - zoxide+fzf（デフォルトのziを上書き）
      zi() {
        local result
        result=$(zoxide query -l | fzf --query="$*" --select-1 --exit-0 --height=40% --reverse)
        if [[ -n "$result" ]]; then
          cd "$result"
        fi
      }

      # zeno.zsh（スニペット/補完）
      if [[ -f ~/src/github.com/yuki-yano/zeno.zsh/zeno.zsh ]]; then
        export ZENO_HOME="$HOME/.config/zeno"
        export ZENO_ENABLE_SOCK=1
        export ZENO_GIT_CAT="bat --color=always"
        export ZENO_GIT_TREE="eza --tree"
        source ~/src/github.com/yuki-yano/zeno.zsh/zeno.zsh
        bindkey ' '    zeno-auto-snippet                 # Space: abbr展開
        bindkey '^m'   zeno-auto-snippet-and-accept-line  # Enter: abbr展開+実行
        bindkey '^x '  zeno-insert-space                  # Ctrl-X Space: 展開せずスペース挿入
        bindkey '^x^m' accept-line                        # Ctrl-X Enter: 展開せず実行
        bindkey '^x^z' zeno-toggle-auto-snippet           # Ctrl-X Ctrl-Z: 自動展開on/off切替
        bindkey '^i'   zeno-completion                    # Tab: 補完
        bindkey '^r'   zeno-history-selection             # Ctrl-R: 履歴検索
        bindkey '^xx'  zeno-insert-snippet                # Ctrl-X X: スニペット選択挿入
      fi

      # fast-syntax-highlighting（zeno.zshの後に読み込む）
      source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

      # yazi (ターミナルファイルマネージャー) - 終了時にディレクトリ追従
      yy() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        yazi "$@" --cwd-file="$tmp"
        if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
          builtin cd -- "$cwd"
        fi
        rm -f -- "$tmp"
      }

      # gw3ネットワーク共有マウント
      gw3() {
        net.exe use W: '\\gw3\all' 2>/dev/null
        sudo mkdir -p /mnt/w
        sudo mount -t drvfs W: /mnt/w 2>/dev/null
        echo "gw3 mounted at /mnt/w"
      }

      gw3off() {
        sudo umount /mnt/w 2>/dev/null
        net.exe use W: /delete 2>/dev/null
        echo "gw3 unmounted"
      }

      # カスタム関数
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
          local hash=$(echo "$commit" | awk '{print $1}')
          git checkout "$hash"
        fi
      }

      # fgs - スタッシュ管理
      fgs() {
        local stash
        stash=$(git stash list | fzf --prompt="Git Stash> " --preview 'git stash show -p {1}')
        if [[ -n "$stash" ]]; then
          local index=$(echo "$stash" | cut -d: -f1)
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

      # falias - zeno abbr一覧閲覧
      falias() {
        cat "$ZENO_HOME/config.yml" | grep -E '^\s+(keyword|snippet):' | paste - - | sed 's/keyword://;s/snippet:/→/' | fzf --prompt="Abbr> "
      }

      # gj - ghqリポジトリ選択→cd
      gj() {
        local selected_dir=$(ghq list | fzf --preview 'bat --color=always --style=header,grid $(ghq root)/{}/README.* 2>/dev/null || ls -la $(ghq root)/{}')
        if [ -n "$selected_dir" ]; then
          cd "$(ghq root)/''${selected_dir}"
        fi
      }

      # _gj_widget - ZLEウィジェット版（Ctrl+F）
      _gj_widget() {
        local selected_dir=$(ghq list | fzf --query="$LBUFFER" --preview 'bat --color=always --style=header,grid $(ghq root)/{}/README.* 2>/dev/null || ls -la $(ghq root)/{}')
        if [ -n "$selected_dir" ]; then
          BUFFER="cd $(ghq root)/''${selected_dir}"
          zle accept-line
        fi
      }
      zle -N _gj_widget
      bindkey '^f' _gj_widget

      # auto-pull: 特定リポジトリに移動したらバックグラウンドでpull
      __auto_pull_on_cd() {
        case "$PWD" in
          */eBASE-Mori/meeting|*/.dotfiles|*/aya-215/life)
            (git pull --ff-only &>/dev/null &)
            ;;
        esac
      }
      add-zsh-hook chpwd __auto_pull_on_cd

      # entire CLI補完
      if command -v entire &>/dev/null; then
        eval "$(entire completion zsh)"
      fi

      # nb関数（タスク管理）
      [[ -f ~/.config/nb/functions.zsh ]] && source ~/.config/nb/functions.zsh

      # j-functions（GitHub Issueベースのパーソナル管理 - journal）
      [[ -f ~/src/github.com/aya-215/life/scripts/j-functions.zsh ]] && source ~/src/github.com/aya-215/life/scripts/j-functions.zsh

      # ======================
      # Tmux functions
      # ======================
      # tmux aliases は zeno.zsh abbr に移行済み（config/zeno/config.yml）

      # tmux session picker (fzf) - プロジェクトディレクトリからセッション作成/切替
      tms() {
        local selected
        if [[ $# -eq 1 ]]; then
          selected=$1
        else
          selected=$(find ~/src -mindepth 3 -maxdepth 3 -type d 2>/dev/null | fzf --prompt="Project> " --preview 'eza -la --icons --group-directories-first {}')
        fi
        [[ -z $selected ]] && return 0
        local selected_name=$(basename "$selected" | tr . _)
        if [[ -z $TMUX ]]; then
          tmux new-session -As "$selected_name" -c "$selected"
        else
          if ! tmux has-session -t="$selected_name" 2>/dev/null; then
            tmux new-session -ds "$selected_name" -c "$selected"
          fi
          tmux switch-client -t "$selected_name"
        fi
      }

      # tmux session switcher (fzf) - 既存セッション間を切替
      tsw() {
        local session
        session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | \
          fzf --prompt="Switch> " \
              --preview '~/.dotfiles/scripts/tmux-preview-panes.sh {}' \
              --preview-window 'right:60%')
        [[ -n $session ]] && tmux switch-client -t "$session"
      }

      # tmux session killer (fzf) - セッションを選択して削除
      tsd() {
        local session
        session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -v "^$(tmux display-message -p '#S')$" | \
          fzf --prompt="Kill> " \
              --preview '~/.dotfiles/scripts/tmux-preview-panes.sh {}' \
              --preview-window 'right:60%')
        [[ -n $session ]] && tmux kill-session -t "$session" && echo "Killed session: $session"
      }

      # ======================
      # Tmux auto-start
      # ======================
      if [[ -z "$TMUX" ]] && [[ $- == *i* ]] && [[ "$TERM_PROGRAM" != "vscode" ]]; then
        tmux attach 2>/dev/null || tmux new-session -s main
      fi
    '';
  };
}
