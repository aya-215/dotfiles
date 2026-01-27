{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink
      "/home/aya/.dotfiles/config/nvim";
}
