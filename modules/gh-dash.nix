{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    gh-dash
  ];

  home.file.".config/gh-dash/config.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/gh-dash/config.yml";
}
