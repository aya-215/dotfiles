{ config, ... }:

{
  home.file.".config/zeno/config.yml".source =
    config.lib.file.mkOutOfStoreSymlink
      "/home/aya/.dotfiles/config/zeno/config.yml";
}
