{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    neovim
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.shellAliases = {
    vi = "nvim";
    vim = "nvim";
  };

  home.activation.nvimSymlink = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    if [ ! -L "$HOME/.config/nvim" ] || [ "$(readlink "$HOME/.config/nvim")" != "$HOME/.dotfiles/config/nvim" ]; then
      rm -rf "$HOME/.config/nvim"
      ln -s "$HOME/.dotfiles/config/nvim" "$HOME/.config/nvim"
    fi
  '';
}
