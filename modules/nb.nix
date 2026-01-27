{ config, ... }:

{
  home.file.".config/nb/functions.zsh".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/nb/functions.zsh";
}
