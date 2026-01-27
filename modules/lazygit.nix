{ config, pkgs, ... }:

{
  home.file.".config/lazygit/config.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/lazygit/config.yml";
}
