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
  ];
}
