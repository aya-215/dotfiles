{ config, ... }:

{
  xdg.configFile."zeno/config.yml".source = ../config/zeno/config.yml;
}
