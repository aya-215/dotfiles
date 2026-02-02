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

      # vim-tmux-navigator連携 (C-hjklでNeovim/tmuxペイン間をシームレス移動)
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
      bind-key -n C-h if-shell "$is_vim" "send-keys C-h" "select-pane -L"
      bind-key -n C-j if-shell "$is_vim" "send-keys C-j" "select-pane -D"
      bind-key -n C-k if-shell "$is_vim" "send-keys C-k" "select-pane -U"
      bind-key -n C-l if-shell "$is_vim" "send-keys C-l" "select-pane -R"

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

      # 確認なしでペイン/ウィンドウを閉じる
      bind x kill-pane
      bind X kill-window
    '';
  };
}
