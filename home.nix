{ config, pkgs, ... }:

{
  imports = [
    ./modules/packages.nix
    ./modules/git.nix
    ./modules/starship.nix
    ./modules/lazygit.nix
    ./modules/neovim.nix
    ./modules/zsh.nix
  ];

  # Home Managerのバージョン
  home.stateVersion = "24.05";

  # ユーザー名とホームディレクトリ
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  # Home Manager自身でHome Managerを管理
  programs.home-manager.enable = true;
}
