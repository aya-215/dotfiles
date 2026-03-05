{ config, pkgs, ... }:

{
  home.file.".config/yazi/yazi.toml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/yazi/yazi.toml";

  home.file.".config/yazi/keymap.toml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/yazi/keymap.toml";

  home.file.".config/yazi/theme.toml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/yazi/theme.toml";
}
