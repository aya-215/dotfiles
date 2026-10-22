{ pkgs, glauncher, ... }:

{
  home.packages = [
    glauncher.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
