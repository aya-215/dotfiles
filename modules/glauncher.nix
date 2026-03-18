{ pkgs, glauncher, ... }:

{
  home.packages = [
    glauncher.packages.${pkgs.system}.default
  ];
}
