{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    prefix = "C-q";
    baseIndex = 1;
    escapeTime = 10;
    mouse = true;
    keyMode = "vi";
    terminal = "tmux-256color";
    historyLimit = 50000;

    plugins = with pkgs.tmuxPlugins; [
      yank
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-nvim 'session'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
      {
        plugin = catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor 'mocha'
          set -g @catppuccin_window_status_style 'rounded'
        '';
      }
    ];

    extraConfig = ''
      # vim-tmux-navigatorの残骸バインド除去 (resurrectセッション対策)
      unbind -T root C-h
      unbind -T root C-j
      unbind -T root C-k
      unbind -T root C-l

      # True Color対応 (WezTerm + WSL)
      set -ag terminal-overrides ",xterm-256color:RGB"

      # Undercurl対応 (Neovim LSP診断等)
      set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'
      set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

      # Focus events (Neovim autoread, FocusGained/FocusLost)
      set -g focus-events on

      # OSC 52 クリップボード (WezTerm経由で透過的に動作)
      set -g set-clipboard on

      # ウィンドウ番号を詰める
      set -g renumber-windows on

      # prefix + r で設定リロード
      bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"

      # 新しいウィンドウをカレントディレクトリで開く
      bind c new-window -c "#{pane_current_path}"

      # ペイン分割 (vim風)
      bind v split-window -h -c "#{pane_current_path}"
      bind s split-window -v -c "#{pane_current_path}"

      # ペイン移動 (prefix + hjkl)
      bind-key h select-pane -L
      bind-key j select-pane -D
      bind-key k select-pane -U
      bind-key l select-pane -R

      # コピーモード (vi風)
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel

      # ステータスバー更新間隔
      set -g status-interval 5

      # 複数クライアント接続時にウィンドウサイズを積極的にリサイズ
      set -g aggressive-resize on

      # メッセージ表示時間
      set -g display-time 4000

      # ペインボーダーの色
      set -g pane-border-style 'fg=#3b4261'
      set -g pane-active-border-style 'fg=#7aa2f7'

      # ウィンドウ入れ替え
      bind -r "<" swap-window -d -t -1
      bind -r ">" swap-window -d -t +1

      # ペインを別ウィンドウに分離
      bind b break-pane -d

      # セッション切替のポップアップ (C-q g)
      bind g display-popup -E -h 80% -w 80% "$SHELL -ic tms"
      # 既存セッション切替 (C-q f: fzf, C-q F: tree)
      bind f display-popup -E -h 80% -w 80% "$SHELL -ic tsw"
      bind F choose-tree -s

      # 確認なしでペイン/ウィンドウを閉じる
      bind x kill-pane
      bind X kill-window

      # ウィンドウタブのフォーマット
      set -g @catppuccin_window_text " #W #{b:pane_current_path}"
      set -g @catppuccin_window_current_text " #W #{b:pane_current_path}"
      set -g @catppuccin_window_flags "icon"

      # ステータスライン (catppuccin modules)
      set -g status-left "#{E:@catppuccin_status_session}"
      set -g status-right "#{E:@catppuccin_status_application}#{E:@catppuccin_status_directory}#{E:@catppuccin_status_date_time}"
      set -g status-right-length 150
      set -g status-left-length 100
    '';
  };
}
