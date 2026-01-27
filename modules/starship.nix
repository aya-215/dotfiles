{ config, pkgs, ... }:

{
  programs.starship = {
    enable = true;
  };

  home.file.".config/starship.toml".source =
    config.lib.file.mkOutOfStoreSymlink
      "/home/aya/.dotfiles/config/starship/starship.toml";
}
