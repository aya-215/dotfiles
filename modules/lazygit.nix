{ config, pkgs, ... }:

{
  home.file.".config/lazygit/config.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      "/home/aya/.dotfiles/config/lazygit/config.yml";
}
