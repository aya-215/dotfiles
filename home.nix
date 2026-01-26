{ config, pkgs, ... }:

{
  # Home Managerのバージョン
  home.stateVersion = "24.05";

  # ユーザー名とホームディレクトリ
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  # Home Manager自身でHome Managerを管理
  programs.home-manager.enable = true;

  # インストールするパッケージ
  home.packages = with pkgs; [
    git
    vim
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
  ];
}
