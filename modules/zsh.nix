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

    shellAliases = {
      ki = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command \"python 'D:\\\\個人用\\\\script\\\\kintai\\\\kintai_auto_checkin.py'\"";
      ko = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command \"python 'D:\\\\個人用\\\\script\\\\kintai\\\\kintai_auto_checkout.py'\"";
      ls = "eza --icons --group-directories-first";
      la = "eza -a --icons --group-directories-first";
      lt = "eza -l --sort=time --icons --group-directories-first";
      lz = "eza -l --sort=size --icons --group-directories-first";
      lg = "eza -l --icons --group-directories-first --git --git-ignore";
      tree = "eza --tree --level=2 --icons";
      treea = "eza --tree --level=2 --icons -a";
    };

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

      # zeno.zsh（スニペット/補完）
      if [[ -f ~/src/github.com/yuki-yano/zeno.zsh/zeno.zsh ]]; then
        export ZENO_HOME="$HOME/.config/zeno"
        export ZENO_ENABLE_SOCK=1
        export ZENO_GIT_CAT="bat --color=always"
        export ZENO_GIT_TREE="eza --tree"
        source ~/src/github.com/yuki-yano/zeno.zsh/zeno.zsh
        # zeno の Enter ウィジェットをサジェストクリア対象に登録（表示バグ防止）
        ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(zeno-auto-snippet-and-accept-line)
        bindkey ' '    zeno-auto-snippet                 # Space: abbr展開
        bindkey '^m'   zeno-auto-snippet-and-accept-line  # Enter: abbr展開+実行
        bindkey '^x '  zeno-insert-space                  # Ctrl-X Space: 展開せずスペース挿入
        bindkey '^x^m' accept-line                        # Ctrl-X Enter: 展開せず実行
        bindkey '^x^z' zeno-toggle-auto-snippet           # Ctrl-X Ctrl-Z: 自動展開on/off切替
        bindkey '^i'   zeno-completion                    # Tab: 補完
        bindkey '^r'   zeno-history-selection             # Ctrl-R: 履歴検索
        bindkey '^xx'  zeno-insert-snippet                # Ctrl-X X: スニペット選択挿入
        bindkey '^xn'  zeno-snippet-next-placeholder     # Ctrl-X N: 次のプレースホルダーへジャンプ
      fi

      # fast-syntax-highlighting（zeno.zshの後に読み込む）
      source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

      # カスタム関数（config/zsh/functions.zshに分離）
      [[ -f ~/.dotfiles/config/zsh/functions.zsh ]] && source ~/.dotfiles/config/zsh/functions.zsh

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
      # Tmux auto-start
      # ======================
      if [[ -z "$TMUX" ]] && [[ $- == *i* ]] && [[ "$TERM_PROGRAM" != "vscode" ]]; then
        tmux attach 2>/dev/null || tmux new-session -s main
      fi
    '';
  };
}
