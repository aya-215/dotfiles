# Home Manager

## 概要

Home Managerは、ユーザー環境とdotfilesをNixで宣言的に管理するためのツールです。このセクションでは、FlakesベースのHome Managerのセットアップと基本的な使い方を学びます。

## Home Managerが管理するもの

### 管理できるもの

- **プログラム設定**: Git、zsh、Neovim、tmuxなど
- **パッケージインストール**: CLIツール、エディタ、ユーティリティ
- **環境変数**: `PATH`、`EDITOR`など
- **設定ファイル**: `~/.config/`以下のファイル
- **サービス**: systemdユーザーサービス（Linux）

### 管理できないもの

- システムレベルの設定（NixOS設定が必要）
- ルート権限が必要な操作
- カーネルモジュール

## Flake経由でのセットアップ

### ステップ1: `flake.nix`の作成

dotfilesリポジトリのルートに`flake.nix`を作成します。

```nix
{
  description = "Personal dotfiles configuration";

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
      homeConfigurations."yourusername" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          ./home.nix
        ];
      };
    };
}
```

**重要ポイント:**
- `"yourusername"`は実際のユーザー名に置き換える
- `system`を環境に合わせて調整（WSLは`x86_64-linux`）
- `inputs.nixpkgs.follows`でnixpkgsを揃える

### ステップ2: `home.nix`の作成

同じディレクトリに`home.nix`を作成します。

```nix
{ config, pkgs, ... }:

{
  # Home Managerのバージョン
  home.stateVersion = "24.05";

  # ユーザー名とホームディレクトリ
  home.username = "yourusername";
  home.homeDirectory = "/home/yourusername";

  # Home Manager自身でHome Managerを管理
  programs.home-manager.enable = true;

  # インストールするパッケージ
  home.packages = with pkgs; [
    git
    vim
    curl
  ];
}
```

**重要ポイント:**
- `home.stateVersion`は最初の設定時点のHome Managerバージョン（変更不要）
- `home.username`と`home.homeDirectory`は環境に合わせる

### ステップ3: Gitリポジトリの準備

```bash
git init  # まだの場合
git add flake.nix home.nix
```

### ステップ4: 初回ビルド

```bash
nix build .#homeConfigurations.yourusername.activationPackage
```

成功すると`result`シンボリックリンクが作成されます。

### ステップ5: 適用

```bash
./result/activate
```

初回適用後、`home-manager`コマンドが利用可能になります。

### ステップ6: 以降の更新

```bash
# 設定を変更したら
home-manager switch --flake .#yourusername

# または短縮形（カレントディレクトリのflake使用）
home-manager switch --flake .
```

## `home.nix`の基本構造

### 必須セクション

```nix
{ config, pkgs, ... }:

{
  # バージョン（変更しない）
  home.stateVersion = "24.05";

  # ユーザー情報
  home.username = "yourusername";
  home.homeDirectory = "/home/yourusername";

  # Home Manager自体の有効化
  programs.home-manager.enable = true;
}
```

### よく使うオプション

#### パッケージインストール

```nix
home.packages = with pkgs; [
  # CLIツール
  git
  vim
  curl
  jq
  ripgrep
  fd

  # 開発ツール
  nodejs
  python3
  go

  # ユーティリティ
  htop
  tree
  lazygit
];
```

#### 環境変数

```nix
home.sessionVariables = {
  EDITOR = "nvim";
  VISUAL = "nvim";
  LANG = "ja_JP.UTF-8";
};
```

#### シェルエイリアス

```nix
home.shellAliases = {
  ll = "ls -la";
  g = "git";
  hm = "home-manager";
};
```

## `programs.*`の使い方

Home Managerは主要なプログラム向けに専用のオプションを提供しています。

### Git設定

```nix
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
  };
};
```

### zsh設定

```nix
programs.zsh = {
  enable = true;

  shellAliases = {
    ll = "ls -la";
    update = "home-manager switch --flake ~/.dotfiles";
  };

  initExtra = ''
    # カスタムシェル設定
    export PATH=$HOME/.local/bin:$PATH

    # 履歴設定
    HISTSIZE=10000
    SAVEHIST=10000
  '';

  oh-my-zsh = {
    enable = true;
    theme = "robbyrussell";
    plugins = [ "git" "docker" ];
  };
};
```

### Starship（プロンプト）

```nix
programs.starship = {
  enable = true;

  settings = {
    add_newline = false;
    character = {
      success_symbol = "[➜](bold green)";
      error_symbol = "[➜](bold red)";
    };
  };
};
```

### tmux

```nix
programs.tmux = {
  enable = true;
  terminal = "screen-256color";
  keyMode = "vi";
  prefix = "C-a";

  extraConfig = ''
    # マウス有効化
    set -g mouse on

    # ペイン分割キーバインド
    bind | split-window -h
    bind - split-window -v
  '';
};
```

## `programs.*` vs `home.file` vs `xdg.configFile`の使い分け

### `programs.*`（推奨）

専用オプションがある場合は優先的に使用します。

**利点:**
- 型チェック
- 補完が効く
- オプション間の整合性が保証される

**使用例:**
```nix
programs.git.enable = true;
programs.zsh.enable = true;
```

### `home.file`

ホームディレクトリ直下にファイルを配置する場合に使用します。

```nix
home.file = {
  ".vimrc".source = ./vimrc;
  ".bashrc".text = ''
    export EDITOR=vim
  '';
};
```

### `xdg.configFile`

`~/.config/`以下にファイルを配置する場合に使用します。

```nix
xdg.configFile = {
  "nvim/init.lua".source = ./config/nvim/init.lua;

  # ディレクトリごとコピー
  "nvim".source = ./config/nvim;

  # テキスト直接記述
  "myapp/config.toml".text = ''
    [settings]
    theme = "dark"
  '';
};
```

### 使い分けのガイドライン

1. **`programs.*`が存在するか確認** → あれば使う
2. **`~/.config/`以下か？** → `xdg.configFile`を使う
3. **ホームディレクトリ直下か？** → `home.file`を使う

## 実践: 最初の設定適用

### シナリオ: Gitとzshを設定する

#### 1. `home.nix`を編集

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

    extraConfig = {
      core.editor = "nvim";
      init.defaultBranch = "main";
    };

    aliases = {
      st = "status";
      co = "checkout";
    };
  };

  # zsh設定
  programs.zsh = {
    enable = true;

    shellAliases = {
      ll = "ls -la";
      hm = "home-manager switch --flake ~/.dotfiles";
    };

    initExtra = ''
      export EDITOR=nvim
    '';
  };

  # 基本パッケージ
  home.packages = with pkgs; [
    curl
    ripgrep
    fd
    jq
  ];
}
```

#### 2. 変更を適用

```bash
cd ~/.dotfiles
home-manager switch --flake .
```

#### 3. 確認

```bash
# Git設定確認
git config --get user.name

# zsh設定確認
echo $EDITOR

# エイリアス確認
alias ll
```

## 世代管理

Home Managerは設定の変更履歴を「世代（generation）」として保存します。

### 世代一覧を表示

```bash
home-manager generations
```

出力例:
```
2024-01-22 14:30 : id 3 -> /nix/store/...-home-manager-generation
2024-01-22 12:00 : id 2 -> /nix/store/...-home-manager-generation
2024-01-21 18:45 : id 1 -> /nix/store/...-home-manager-generation
```

### 前の世代に戻す

```bash
# 世代IDを指定
/nix/store/...-home-manager-generation/activate

# または、世代一覧から選んで実行
home-manager generations | head -2 | tail -1 | awk '{print $NF "/activate"}' | sh
```

### 古い世代を削除

```bash
# 7日以上前の世代を削除
nix-collect-garbage --delete-older-than 7d

# すべての古い世代を削除（現在の世代のみ残す）
nix-collect-garbage -d
```

## よくあるコマンド

```bash
# 設定を適用（flake使用）
home-manager switch --flake ~/.dotfiles

# ビルドのみ（適用しない）
home-manager build --flake ~/.dotfiles

# 設定の差分を確認
nix store diff-closures ~/.local/state/home-manager/gcroots/current-home ./result

# 世代一覧
home-manager generations

# ヘルプ
home-manager --help
```

## トラブルシューティング

### エラー: `error: collision between ...`

**原因**: 同じファイルを複数の方法で管理しようとしている

**解決策**:
```nix
# home.fileとxdg.configFileで同じファイルを指定していないか確認
# programs.*で管理されているファイルをhome.fileで上書きしていないか確認
```

### エラー: `error: attribute 'homeConfigurations' missing`

**原因**: `flake.nix`の構造が正しくない

**解決策**:
```nix
# outputsの構造を確認
outputs = { self, nixpkgs, home-manager }: {
  homeConfigurations."username" = ...;
};
```

### 既存の設定ファイルとの競合

**原因**: Home Manager適用前から`~/.gitconfig`などが存在している

**解決策**:
```bash
# バックアップを取ってから削除
mv ~/.gitconfig ~/.gitconfig.backup

# 再度適用
home-manager switch --flake ~/.dotfiles
```

## 実践演習

### 演習1: 基本的なHome Manager設定

以下の要件を満たす`home.nix`を作成してください。

- Gitユーザー名とメールアドレスを設定
- `curl`、`jq`、`ripgrep`をインストール
- `EDITOR=nvim`を環境変数に設定

<details>
<summary>解答例</summary>

```nix
{ config, pkgs, ... }:

{
  home.stateVersion = "24.05";
  home.username = "yourusername";
  home.homeDirectory = "/home/yourusername";

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "your@email.com";
  };

  home.packages = with pkgs; [
    curl
    jq
    ripgrep
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
```
</details>

### 演習2: zsh + Starship

zshとStarshipを有効化し、カスタムエイリアスを追加してください。

<details>
<summary>解答例</summary>

```nix
{ config, pkgs, ... }:

{
  home.stateVersion = "24.05";
  home.username = "yourusername";
  home.homeDirectory = "/home/yourusername";

  programs.home-manager.enable = true;

  programs.zsh = {
    enable = true;

    shellAliases = {
      ll = "ls -la";
      g = "git";
      hm = "home-manager switch --flake ~/.dotfiles";
    };
  };

  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;
    };
  };
}
```
</details>

## 確認ポイント

以下の質問に答えられるか確認してください。

- [ ] Home Managerが管理できるものを説明できますか？
- [ ] `flake.nix`と`home.nix`の役割を理解していますか？
- [ ] `programs.*`オプションを使えますか？
- [ ] `home.file`と`xdg.configFile`の違いを説明できますか？
- [ ] `home-manager switch`で設定を適用できますか？
- [ ] 世代管理の仕組みを理解していますか？

## 次のステップ

Home Managerの基本を理解したら、次はモジュールシステムを学んで設定を整理しましょう。

→ [06. モジュールシステム](./06-module-system.md)

## 参考資料

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Home Manager Options Search](https://home-manager-options.extranix.com/)
- [Home Manager GitHub](https://github.com/nix-community/home-manager)
