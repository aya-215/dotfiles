{ config, pkgs, ... }:

{
  # 環境変数（shell.nixから移行）
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    LANG = "ja_JP.UTF-8";
    BROWSER = "wslview";
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

    # Oh My Zsh設定
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];  # 組み込みプラグインのみ
      theme = "";  # Starshipを使用するため無効化
    };

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

    # エイリアス
    shellAliases = {
      # エディタ
      vim = "nvim";
      vi = "nvim";
      v = "nvim";
      c = "claude";
      cw = "claude-watch";

      # バックアップ
      bak = "~/.dotfiles/scripts/backup/backup-wsl-to-windows.sh";

      # eza (ls replacement)
      ls = "eza --icons --group-directories-first";
      l = "eza --icons --group-directories-first";
      ll = "eza -l --icons --group-directories-first --git";
      la = "eza -la --icons --group-directories-first --git";
      tree = "eza --tree --level=2 --icons";
      treea = "eza --tree --level=2 --icons -a";
      lg = "eza -l --icons --group-directories-first --git --git-ignore";

      # npm
      npmd = "npm run dev -- -H 0.0.0.0";
      npms = "npm run storybook -- --host 0.0.0.0";

      # 勤怠打刻（Windows Python経由）
      ki = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command \"python 'D:\\個人用\\script\\kintai\\kintai_auto_checkin.py'\"";
      ko = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command \"python 'D:\\個人用\\script\\kintai\\kintai_auto_checkout.py'\"";
    };

    # 履歴設定
    history = {
      size = 10000;
      save = 10000;
      path = "$HOME/.zsh_history";
    };

    # .zshrcに追加（メイン部分）
    initContent = ''
      # compauditスキップ（起動高速化）
      export ZSH_DISABLE_COMPFIX=true

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
        bindkey '^ ' zeno-auto-snippet            # Ctrl+Space: スニペット展開
        bindkey '^i' zeno-completion              # Tab: 補完
        bindkey '^r' zeno-history-selection       # Ctrl-R: 履歴検索
        bindkey '^x^s' zeno-insert-snippet        # Ctrl-X Ctrl-S: スニペット挿入
      fi

      # fast-syntax-highlighting（zeno.zshの後に読み込む）
      source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

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

      # falias - エイリアス閲覧
      falias() {
        alias | fzf --prompt="Alias> "
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

      # nb関数（タスク管理）
      [[ -f ~/.config/nb/functions.zsh ]] && source ~/.config/nb/functions.zsh

      # lt-functions（GitHub Issueベースのタスク管理）
      [[ -f ~/src/github.com/aya-215/life/scripts/lt-functions.zsh ]] && source ~/src/github.com/aya-215/life/scripts/lt-functions.zsh

      # ======================
      # Tmux aliases & functions
      # ======================
      alias ta='tmux attach -t'
      alias tl='tmux list-sessions'
      alias tks='tmux kill-session -t'
      alias tkss='tmux kill-server'

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
        session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | fzf --prompt="Switch> " --preview 'tmux list-windows -t {}')
        [[ -n $session ]] && tmux switch-client -t "$session"
      }

      # tmux session killer (fzf) - セッションを選択して削除
      tsd() {
        local session
        session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -v "^$(tmux display-message -p '#S')$" | fzf --prompt="Kill> " --preview 'tmux list-windows -t {}')
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
