{ config, ... }:

{
  home.file.".config/zeno/config.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/zeno/config.yml";
}
