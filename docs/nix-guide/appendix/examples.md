# 設定例集

## 最小限のFlake

### シンプルな開発環境

```nix
# flake.nix
{
  description = "Simple dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          git
          nodejs
          python3
        ];

        shellHook = ''
          echo "Development environment loaded!"
        '';
      };
    };
}
```

## Home Manager

### 最小限の`flake.nix`

```nix
{
  description = "Personal dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations."aya" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          ./home.nix
        ];
      };
    };
}
```

### 最小限の`home.nix`

```nix
{ config, pkgs, ... }:

{
  home.stateVersion = "24.05";
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    git
    vim
    curl
  ];
}
```

## Git設定

### 基本的な設定

```nix
# modules/git.nix
{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "your.email@example.com";

    extraConfig = {
      core.editor = "nvim";
      init.defaultBranch = "main";
      pull.rebase = false;
    };

    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      df = "diff";
      lg = "log --oneline --graph";
    };
  };
}
```

### 高度な設定（includes使用）

```nix
{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "personal@example.com";

    extraConfig = {
      core = {
        editor = "nvim";
        autocrlf = "input";
      };

      init.defaultBranch = "main";

      pull.rebase = false;

      push.autoSetupRemote = true;

      # 条件付きinclude（仕事用）
      includeIf."gitdir:~/work/".path = "~/.config/git/work.gitconfig";
    };

    ignores = [
      "*.swp"
      "*.swo"
      "*~"
      ".DS_Store"
      "node_modules/"
      ".env"
    ];

    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      visual = "log --graph --oneline --all";
    };
  };

  home.file.".config/git/work.gitconfig".text = ''
    [user]
      email = work@company.com
  '';
}
```

## zsh設定

### 基本的な設定

```nix
# modules/zsh.nix
{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;

    shellAliases = {
      ll = "ls -la";
      g = "git";
      vim = "nvim";
      hm = "home-manager switch --flake ~/.dotfiles";
    };

    initExtra = ''
      export PATH=$HOME/.local/bin:$PATH
      export EDITOR=nvim
    '';
  };
}
```

### 高度な設定（Oh My Zsh + プラグイン）

```nix
{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;

    shellAliases = {
      ll = "ls -la";
      g = "git";
      vim = "nvim";
      cat = "bat";
      hm = "home-manager switch --flake ~/.dotfiles";
      update = "nix flake update ~/.dotfiles && home-manager switch --flake ~/.dotfiles";
    };

    history = {
      size = 10000;
      save = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    initExtra = ''
      # カスタム関数
      mkcd() {
        mkdir -p "$1" && cd "$1"
      }

      # fzf統合
      export FZF_DEFAULT_COMMAND='fd --type f'
      export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    '';

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "docker"
        "kubectl"
        "npm"
      ];
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;

      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };

      git_branch = {
        symbol = " ";
      };

      nodejs = {
        symbol = " ";
      };

      python = {
        symbol = " ";
      };
    };
  };
}
```

## Neovim設定

### アプローチ1: 既存設定をコピー

```nix
# modules/neovim.nix
{ config, pkgs, ... }:

{
  programs.neovim.enable = true;

  home.file.".config/nvim" = {
    source = ../config/nvim;
    recursive = true;
  };

  home.packages = with pkgs; [
    # LSP
    nil  # Nix LSP
    lua-language-server
    nodePackages.typescript-language-server

    # ツール
    ripgrep
    fd
    tree-sitter
  ];
}
```

### アプローチ2: Nix管理のプラグイン

```nix
{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      # 基本
      vim-sensible

      # カラースキーム
      onedark-nvim

      # ファイルエクスプローラ
      nvim-tree-lua

      # ファジーファインダ
      telescope-nvim
      telescope-fzf-native-nvim

      # LSP
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp

      # Treesitter
      nvim-treesitter.withAllGrammars

      # ステータスライン
      lualine-nvim

      # Git統合
      gitsigns-nvim
    ];

    extraLuaConfig = ''
      -- 基本設定
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2

      -- カラースキーム
      require('onedark').setup()
      require('onedark').load()

      -- Lualine
      require('lualine').setup()

      -- Gitsigns
      require('gitsigns').setup()
    '';
  };
}
```

## パッケージ管理

### カテゴリ別に整理

```nix
# modules/packages.nix
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # CLI ツール
    curl
    wget
    jq
    yq
    ripgrep
    fd
    bat
    eza  # ls の代替
    fzf

    # Git関連
    git
    lazygit
    gh  # GitHub CLI
    delta  # git diff の改善

    # 開発ツール
    nodejs
    python3
    go
    rustc
    cargo

    # ユーティリティ
    htop
    tree
    neofetch
    tldr

    # エディタ
    neovim

    # その他
    starship
  ];
}
```

## モジュール化された構成

### ディレクトリ構造

```
~/.dotfiles/
├── flake.nix
├── home.nix
└── modules/
    ├── git.nix
    ├── zsh.nix
    ├── neovim.nix
    ├── packages.nix
    └── starship.nix
```

### `home.nix`（エントリーポイント）

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./modules/git.nix
    ./modules/zsh.nix
    ./modules/neovim.nix
    ./modules/packages.nix
    ./modules/starship.nix
  ];

  home.stateVersion = "24.05";
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
```

## カスタムオプション付きモジュール

```nix
# modules/git.nix
{ config, pkgs, lib, ... }:

{
  options.myConfig.git = {
    enable = lib.mkEnableOption "Git configuration";

    userName = lib.mkOption {
      type = lib.types.str;
      default = "User";
      description = "Git user name";
    };

    userEmail = lib.mkOption {
      type = lib.types.str;
      description = "Git user email";
    };

    enableAliases = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Git aliases";
    };
  };

  config = lib.mkIf config.myConfig.git.enable {
    programs.git = {
      enable = true;
      userName = config.myConfig.git.userName;
      userEmail = config.myConfig.git.userEmail;

      extraConfig = {
        core.editor = "nvim";
        init.defaultBranch = "main";
      };

      aliases = lib.mkIf config.myConfig.git.enableAliases {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
      };
    };
  };
}
```

使用例:

```nix
# home.nix
{
  imports = [ ./modules/git.nix ];

  myConfig.git = {
    enable = true;
    userName = "Aya";
    userEmail = "aya@example.com";
    enableAliases = true;
  };
}
```

## 参考資料

- [Home Manager Options](https://home-manager-options.extranix.com/)
- [NixOS Search](https://search.nixos.org/)
- [GitHub dotfiles examples](https://github.com/search?q=home-manager+flake.nix)
