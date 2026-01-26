{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    curl

    # CLIツール
    ripgrep    # rg (高速grep)
    fd         # 高速find
    fzf        # ファジーファインダー
    bat        # cat代替（シンタックスハイライト）
    eza        # ls代替（モダン）
    jq         # JSON処理
    lazygit    # Git TUI
    zoxide     # スマートcd
    nb         # ノート管理
    delta      # Git diff viewer

    # Oh My Zsh プラグイン
    zsh-you-should-use
    zsh-autosuggestions
  ];
}
