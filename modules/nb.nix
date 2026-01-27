{ config, ... }:

{
  home.file.".config/nb/functions.zsh".source =
    config.lib.file.mkOutOfStoreSymlink
      "/home/aya/.dotfiles/config/nb/functions.zsh";
}
