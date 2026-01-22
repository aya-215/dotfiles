# モジュールシステム

## 概要

設定ファイルが大きくなってきたら、モジュールシステムを使って整理しましょう。このセクションでは、設定をモジュールに分割する方法と、条件分岐などの高度な機能を学びます。

## モジュールとは

Nixのモジュールは、設定を構造化して再利用可能にする仕組みです。

### 基本的なモジュール

```nix
# module.nix
{ config, pkgs, ... }:

{
  # 設定内容
  programs.git.enable = true;
}
```

## モジュールの構造

完全な形式のモジュールは以下の要素を持ちます。

```nix
{ config, pkgs, lib, ... }:

{
  imports = [
    # 他のモジュールをインポート
  ];

  options = {
    # 新しいオプションを定義
  };

  config = {
    # 設定内容
  };
}
```

### 簡略形式

`options`を定義しない場合は、`config`を省略できます。

```nix
{ config, pkgs, ... }:

{
  # これは自動的にconfigセクションとして扱われる
  programs.git.enable = true;
}
```

## ファイル分割の戦略

### 分割前（`home.nix`）

```nix
{ config, pkgs, ... }:

{
  home.stateVersion = "24.05";
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  programs.home-manager.enable = true;

  # Git設定
  programs.git = {
    enable = true;
    userName = "Aya";
    userEmail = "aya@example.com";
    # ... 多数の設定
  };

  # zsh設定
  programs.zsh = {
    enable = true;
    # ... 多数の設定
  };

  # Neovim設定
  programs.neovim = {
    enable = true;
    # ... 多数の設定
  };

  # パッケージ
  home.packages = with pkgs; [
    # ... 多数のパッケージ
  ];
}
```

### 分割後のディレクトリ構造

```
~/.dotfiles/
├── flake.nix
├── home.nix          # エントリーポイント
└── modules/
    ├── git.nix
    ├── zsh.nix
    ├── neovim.nix
    └── packages.nix
```

### 分割後（`home.nix`）

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./modules/git.nix
    ./modules/zsh.nix
    ./modules/neovim.nix
    ./modules/packages.nix
  ];

  home.stateVersion = "24.05";
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  programs.home-manager.enable = true;
}
```

### 各モジュールファイル

#### `modules/git.nix`

```nix
{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Aya";
    userEmail = "aya@example.com";

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
    };
  };
}
```

#### `modules/zsh.nix`

```nix
{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;

    shellAliases = {
      ll = "ls -la";
      g = "git";
      hm = "home-manager switch --flake ~/.dotfiles";
    };

    initExtra = ''
      export PATH=$HOME/.local/bin:$PATH
    '';
  };
}
```

#### `modules/packages.nix`

```nix
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # CLI tools
    curl
    jq
    ripgrep
    fd
    bat

    # Development
    git
    lazygit
    nodejs

    # Utilities
    htop
    tree
  ];
}
```

## 条件分岐: `mkIf`

特定の条件下でのみ設定を有効化する場合に使用します。

### 基本的な使い方

```nix
{ config, pkgs, lib, ... }:

{
  programs.git.enable = lib.mkIf config.programs.git.enable {
    # gitが有効な場合のみこの設定を適用
    extraConfig.core.editor = "nvim";
  };
}
```

### カスタムオプションとの組み合わせ

```nix
{ config, pkgs, lib, ... }:

{
  options.myModules.development.enable = lib.mkEnableOption "development tools";

  config = lib.mkIf config.myModules.development.enable {
    home.packages = with pkgs; [
      nodejs
      python3
      go
      rustc
    ];

    programs.git.enable = true;
  };
}
```

## カスタムオプションの定義

### `mkEnableOption`

有効/無効のフラグを作成します。

```nix
{ config, pkgs, lib, ... }:

{
  options.myModules.git.enable = lib.mkEnableOption "Git configuration";

  config = lib.mkIf config.myModules.git.enable {
    programs.git = {
      enable = true;
      userName = "Aya";
      userEmail = "aya@example.com";
    };
  };
}
```

### `mkOption`

より詳細なオプションを定義します。

```nix
{ config, pkgs, lib, ... }:

{
  options.myModules.git = {
    enable = lib.mkEnableOption "Git configuration";

    userName = lib.mkOption {
      type = lib.types.str;
      default = "User";
      description = "Git user name";
    };

    userEmail = lib.mkOption {
      type = lib.types.str;
      default = "user@example.com";
      description = "Git user email";
    };
  };

  config = lib.mkIf config.myModules.git.enable {
    programs.git = {
      enable = true;
      userName = config.myModules.git.userName;
      userEmail = config.myModules.git.userEmail;
    };
  };
}
```

使用例:

```nix
# home.nix
{
  imports = [ ./modules/git.nix ];

  myModules.git = {
    enable = true;
    userName = "Aya";
    userEmail = "aya@example.com";
  };
}
```

## `mkMerge`

複数の設定をマージします。

```nix
{ config, pkgs, lib, ... }:

{
  config = lib.mkMerge [
    # 基本設定
    {
      programs.git.enable = true;
    }

    # 条件付き設定1
    (lib.mkIf config.myModules.development.enable {
      programs.git.aliases.dev = "log --oneline";
    })

    # 条件付き設定2
    (lib.mkIf config.myModules.work.enable {
      programs.git.extraConfig.user.email = "work@company.com";
    })
  ];
}
```

## `mkDefault`と`mkForce`

### `mkDefault`

デフォルト値を設定（他で上書き可能）。

```nix
{
  programs.git.userName = lib.mkDefault "DefaultUser";
  # 他のモジュールで上書き可能
}
```

### `mkForce`

強制的に値を設定（他で上書き不可）。

```nix
{
  programs.git.userName = lib.mkForce "ForcedUser";
  # 他のモジュールでも上書きできない
}
```

## 実践: Git設定をモジュール化

### ステップ1: ディレクトリ構造を作成

```bash
cd ~/.dotfiles
mkdir -p modules
```

### ステップ2: Git設定を分離

`modules/git.nix`を作成:

```nix
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
        pull.rebase = false;
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

### ステップ3: `home.nix`で使用

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./modules/git.nix
  ];

  home.stateVersion = "24.05";
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  programs.home-manager.enable = true;

  myConfig.git = {
    enable = true;
    userName = "Aya";
    userEmail = "aya@example.com";
    enableAliases = true;
  };
}
```

### ステップ4: 適用

```bash
home-manager switch --flake ~/.dotfiles
```

## モジュール分割のベストプラクティス

### 1. 関心事ごとに分割

```
modules/
├── programs/
│   ├── git.nix
│   ├── zsh.nix
│   └── neovim.nix
├── shell/
│   ├── aliases.nix
│   └── environment.nix
└── packages/
    ├── development.nix
    └── utilities.nix
```

### 2. 再利用可能に設計

オプションを通じてカスタマイズ可能にする。

### 3. デフォルト値を提供

すぐに使える状態にする。

### 4. ドキュメントを記述

各オプションに`description`を付ける。

## 確認ポイント

以下の質問に答えられるか確認してください。

- [ ] モジュールの基本構造を理解していますか？
- [ ] `imports`で他のモジュールを読み込めますか？
- [ ] `mkIf`で条件分岐ができますか？
- [ ] `mkOption`でカスタムオプションを定義できますか？
- [ ] 設定をファイルごとに分割できますか？

## 次のステップ

モジュールシステムを理解したら、次は既存のdotfilesをNixに移行する方法を学びましょう。

→ [07. 既存dotfilesの移行](./07-migration.md)

## 参考資料

- [NixOS Wiki - Modules](https://nixos.wiki/wiki/Module)
- [Home Manager Manual - Writing Custom Modules](https://nix-community.github.io/home-manager/index.xhtml#sec-writing-modules)
