{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "eBASE-Mori";
        email = "mori.a@ebase.co.jp";
      };
      init.defaultBranch = "main";
      core = {
        pager = "delta";
        excludesfile = "~/.config/git/ignore";
      };
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        side-by-side = false;
        line-numbers = true;
        syntax-theme = "Monokai Extended";
        features = "decorations";
      };
      "delta \"decorations\"" = {
        commit-decoration-style = "bold yellow box ul";
        file-style = "bold yellow ul";
        file-decoration-style = "none";
        hunk-header-decoration-style = "cyan box ul";
      };
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
      credential."https://github.com".helper = "!/usr/bin/gh auth git-credential";
      credential."https://gist.github.com".helper = "!/usr/bin/gh auth git-credential";
      coderabbit.machineId = "cli/96c13c10b3db406c9ed1d8b2fb783b2c";
      ghq.root = "~/src";
    };
  };
}
