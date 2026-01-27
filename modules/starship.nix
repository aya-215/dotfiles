{ config, pkgs, ... }:

{
  programs.starship = {
    enable = true;
  };

  home.file.".config/starship.toml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/starship/starship.toml";
}
