{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    curl

    # CLIツール
    ripgrep    # rg (高速grep)
    fd         # 高速find
    fzf        # ファジーファインダー
    bat        # cat代替（シンタックスハイライト）
    eza        # ls代替（モダン）
    jq         # JSON処理
    lazygit    # Git TUI
    yazi       # ターミナルファイルマネージャー
    poppler-utils  # PDFプレビュー用 (pdftoppm)
    zoxide     # スマートcd
    nb         # ノート管理
    delta      # Git diff viewer
    ghq        # リポジトリ管理
    gh         # GitHub CLI
    gcalcli    # Googleカレンダー
    wslu       # WSL utilities (wslview等)
    sshfs      # リモートファイルシステムのマウント

    # ランタイム・バージョン管理
    fnm        # Node.jsバージョン管理
    deno       # Deno JavaScript runtime
    bun        # Bun JavaScript runtime

    # Python
    (python3.withPackages (ps: with ps; [
      requests
      playwright
    ]))

    # Oh My Zsh プラグイン
    zsh-you-should-use
    zsh-autosuggestions

    # ビルドツール
    cmake          # telescope-fzf-native.nvim のビルドに必要

    # Nix開発ツール
    nixpkgs-fmt    # フォーマッタ
    statix         # Linter
    nil            # LSP
  ];
}
