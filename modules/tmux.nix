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
          set -g @catppuccin_window_text " #{b:pane_current_path}"
          set -g @catppuccin_window_current_text " #{b:pane_current_path}"
          set -g @catppuccin_window_flags "icon"
        '';
      }
      # fingers: URL/パス/ハッシュ等をラベル表示してコピー
      {
        plugin = fingers;
        extraConfig = ''
          set -g @fingers-key 'u'
          set -g @fingers-patterns 'url sha path ip uuid'
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

      # OSC 8 ハイパーリンク対応 (tmux 3.4+)
      set -as terminal-features ",*:hyperlinks"

      # ウィンドウ番号を詰める
      set -g renumber-windows on

      # WezTermのタブタイトルにtmux内プロセス名を伝える
      set -g set-titles on
      set -g set-titles-string '#T'

      # prefix + r で設定リロード
      bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"
      bind R command-prompt -I "#S" "rename-session '%%'"

      # 新しいウィンドウをカレントディレクトリで開く
      bind c new-window -c "#{pane_current_path}"

      # ペイン分割 (vim風)
      bind v split-window -h -c "#{pane_current_path}"
      bind s split-window -v -c "#{pane_current_path}"

      # ペイン移動 (prefix + hjkl / smart-splits.nvim連携)
      bind-key h if-shell -F "#{@pane-is-vim}" 'send-keys C-h' 'select-pane -L'
      bind-key j if-shell -F "#{@pane-is-vim}" 'send-keys C-j' 'select-pane -D'
      bind-key k if-shell -F "#{@pane-is-vim}" 'send-keys C-k' 'select-pane -U'
      bind-key l if-shell -F "#{@pane-is-vim}" 'send-keys C-l' 'select-pane -R'

      # コピーモードへ入る (Spaceで)
      bind Space copy-mode

      # コピーモード (vi風)
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind-key -T copy-mode-vi Y send-keys -X begin-selection \; send-keys -X end-of-line \; send-keys -X cursor-left \; send-keys -X copy-selection-and-cancel
      bind-key -T copy-mode-vi V send-keys -X select-line
      bind-key -T copy-mode-vi r send-keys -X rectangle-toggle

      # インクリメンタル検索
      bind-key -T copy-mode-vi / command-prompt -i -p "(search down)" "send -X search-forward-incremental \"%%%\""
      bind-key -T copy-mode-vi ? command-prompt -i -p "(search up)" "send -X search-backward-incremental \"%%%\""

      # ステータスバー更新間隔
      set -g status-interval 5

      # 複数クライアント接続時にウィンドウサイズを積極的にリサイズ
      set -g aggressive-resize on

      # メッセージ表示時間
      set -g display-time 4000

      # ペインボーダーの色
      set -g pane-border-style 'fg=#3b4261'
      set -g pane-active-border-style 'fg=#7aa2f7'

      # 非アクティブペインのテキストを薄くする（透過維持）
      set -g window-style 'fg=#a6adc8'
      set -g window-active-style 'fg=#cdd6f4'

      # Popup透過設定
      set -g popup-style 'bg=default'
      set -g popup-border-style 'fg=#7aa2f7'

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
      bind D display-popup -E -h 80% -w 80% "$SHELL -ic tsd"

      # 確認なしでペイン/ウィンドウを閉じる
      bind x kill-pane
      bind X kill-window

      # ステータスライン (catppuccin modules)
      set -g status-left "#{E:@catppuccin_status_session}"
      set -g status-right "#{E:@catppuccin_status_application}#{E:@catppuccin_status_directory}#{E:@catppuccin_status_date_time}"
      set -g status-right-length 150
      set -g status-left-length 100

    '';
  };
}
