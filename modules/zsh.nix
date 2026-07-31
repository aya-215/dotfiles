{ config, pkgs, ... }:

{
  # wslview代替スクリプト（wslu廃止後のWSL→Windowsブラウザ起動用）
  home.file.".local/bin/wslopen" = {
    executable = true;
    text = ''
      #!/bin/bash
      /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command "Start-Process '$1'"
    '';
  };

  # 環境変数（shell.nixから移行）
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    LANG = "ja_JP.UTF-8";
    BROWSER = "wslopen";
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

      # クリップボード (WSL → Windows、UTF-8で文字化けなし)
      wclip = "win32yank.exe -i --crlf";
      wpaste = "win32yank.exe -o --lf";
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
        # flock で直列化する理由:
        #   WezTermが複数ペイン/タブを同時に開くと、複数のzshが同時にここへ来る。
        #   サーバ未起動の一瞬に複数が new-session を叩くと tmux クライアントが
        #   2プロセス並ぶ。tmux-continuum は
        #   another_tmux_server_running_on_startup() でクライアント数を数えており、
        #   2以上だと「別サーバがある」と誤認して自動復元を丸ごと抑止する。
        #   結果 main セッションだけが立ち、復元されたセッションが1つも出ない。
        #   (実測で再現。wsl --shutdown 直後に発生しやすい)
        #
        #   ロックで直列化し、最初の1つがサーバを作り終えてから後続が attach
        #   するようにすれば、起動時点のクライアントは1つだけになる。
        #   -o が必須。tmux サーバはロックfdを継承したまま常駐するため、
        #   -o (close-on-exec) を付けないとロックが永久に解放されず後続の
        #   シェルがハングする(実測で確認)。
        #   サーバ生成だけを直列化し、attach はロック外で行う。
        #
        # 復元を明示的に呼ぶ理由:
        #   tmux-continuum の自動復元は another_tmux_server_running_on_startup()
        #   でtmuxプロセス数を数え、2以上なら「別サーバがある」と判断して
        #   復元を抑止する。しかし `tmux new-session` は常にクライアントと
        #   サーバの2プロセスになり(実測)、さらに他のシェルの `tmux attach` が
        #   同時に生きているため、この数は構造的に2以上になる。
        #   flock で直列化しても attach はロック外なので解決しない。
        #   よってプロセス数による推測に頼らず、サーバを作ったシェル自身が
        #   resurrect の復元スクリプトを直接呼ぶ(@continuum-restore は off)。
        #   復元は run-shell でtmux内から実行する必要がある。
        #   resurrect の restore.sh は tmux_socket() が $TMUX からソケットパスを
        #   取得する実装のため、tmuxの外から直接起動すると $TMUX が空になり
        #   `tmux -S "" new-session ...` となって全セッションの復元が失敗する
        #   (実測: PID に `tmux -S  new-session -d -s ...` が残っていた)。
        #   run-shell 経由なら tmux が $TMUX を設定した状態で実行される。
        #   足場セッションは __bootstrap__ という衝突しない名前で作る。
        #   restore.sh は既存サーバに対してしか動かないため、先にサーバを
        #   起動する必要があり、そのための空セッションが要る。
        #
        #   名前を main にしない理由:
        #   保存内容に main が含まれている場合、足場の main と衝突する。
        #   復元後に足場を削除する処理が、復元された main を消してしまう。
        #   衝突しない名前にすれば、保存された main は通常のセッションとして
        #   復元され、足場の削除は無条件に行える。
        #
        #   復元対象が無かった場合は足場をそのまま main にリネームして残す。
        flock -o "''${XDG_RUNTIME_DIR:-/tmp}/.tmux-autostart-$UID.lock" sh -c '
          tmux has-session 2>/dev/null || {
            tmux new-session -ds __bootstrap__ </dev/null >/dev/null 2>&1
            restore_script=$(tmux show -gv @resurrect-restore-script-path 2>/dev/null)
            [ -n "$restore_script" ] && tmux run-shell "$restore_script" >/dev/null 2>&1
            others=$(tmux list-sessions -F "#{session_name}" 2>/dev/null |
                     grep -cxv __bootstrap__)
            if [ "''${others:-0}" -gt 0 ]; then
              tmux kill-session -t __bootstrap__ 2>/dev/null
            else
              tmux rename-session -t __bootstrap__ main 2>/dev/null
            fi
          }
        '
        exec tmux attach
      fi

      # ======================
      # pr-diffview サーバー自動起動（tmuxペイン0のみ）
      # ======================
      if [[ -n "$TMUX" ]] && [[ "$(tmux display-message -p '#P')" == "0" ]]; then
        if ! curl -sf http://localhost:8765/health &>/dev/null; then
          mkdir -p ~/.local/log
          (cd ~/.dotfiles/scripts/pr-diffview && \
            uv run uvicorn server:app --host 127.0.0.1 --port 8765 \
              --log-level warning >> ~/.local/log/pr-diffview.log 2>&1 &)
        fi
      fi
    '';
  };
}
