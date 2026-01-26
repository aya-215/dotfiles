{ config, pkgs, ... }:

{
  imports = [
    ./modules/packages.nix
    ./modules/shell.nix
    ./modules/git.nix
  ];

  # Home Managerのバージョン
  home.stateVersion = "24.05";

  # ユーザー名とホームディレクトリ
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  # Home Manager自身でHome Managerを管理
  programs.home-manager.enable = true;
}
