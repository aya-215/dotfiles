{ config, pkgs, ... }:

{
  xdg.configFile."lazygit/config.yml".source = ../config/lazygit/config.yml;
}
