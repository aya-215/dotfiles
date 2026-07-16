{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;

    # グローバルignore設定
    ignores = [
      # Claude Code
      ".claude/plans/"

      # Serena MCP
      ".serena/"

      # Neovim
      "*.swp"
      "*.swo"
      "*~"

      # テストフォルダを除外
      "test/"

      # Nix
      "result"
    ];

    settings = {
      # hunk（review-first diff TUI）用エイリアス。
      # core.pager は delta のまま維持し、レビューしたいときだけ hunk を明示的に呼ぶ。
      #   git hdiff        → 作業ツリーの変更を hunk でレビュー
      #   git hshow <ref>  → 特定コミットを hunk でレビュー
      alias = {
        hdiff = "-c core.pager=\"hunk pager\" diff";
        hshow = "-c core.pager=\"hunk pager\" show";
      };
      user = {
        name = "eBASE-Mori";
        email = "mori.a@ebase.co.jp";
      };
      init.defaultBranch = "main";
      core.pager = "delta";
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
      credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
      credential."https://gist.github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
      # 社内GitBucket: 初回push時の認証情報を~/.git-credentialsに平文保存し、以降の入力を省略
      credential."http://192.168.208.80:8080".helper = "store";
      coderabbit.machineId = "cli/96c13c10b3db406c9ed1d8b2fb783b2c";
      push.autoSetupRemote = true;
      pull.rebase = true;
      ghq.root = "~/src";
      # aya-215アカウント用SSHエイリアスへの自動書き換え
      "url \"git@github-aya215:aya-215/\"".insteadOf = "git@github.com:aya-215/";
    };

    # /mnt/ 配下（Windows側リポジトリ）のみCRLFチェックアウトを有効化
    # WSLネイティブのリポジトリはLFのまま（シェルスクリプト等の改行破壊を防ぐ）
    includes = [
      {
        condition = "gitdir:/mnt/";
        contents.core.autocrlf = true;
      }
    ];
  };
}
