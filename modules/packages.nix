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
    zoxide     # スマートcd
    nb         # ノート管理
    delta      # Git diff viewer
    ghq        # リポジトリ管理
    gh         # GitHub CLI
    gcalcli    # Googleカレンダー
    wslu       # WSL utilities (wslview等)

    # ランタイム・バージョン管理
    fnm        # Node.jsバージョン管理
    deno       # Deno JavaScript runtime
    bun        # Bun JavaScript runtime
    go         # Go言語

    # Python
    python3    # Python 3.x
    pipx       # Pythonツール管理

    # Oh My Zsh プラグイン
    zsh-you-should-use
    zsh-autosuggestions

    # Nix開発ツール
    nixpkgs-fmt    # フォーマッタ
    statix         # Linter
    nil            # LSP
  ];
}
