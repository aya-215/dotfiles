# 既存dotfilesの移行

## 概要

このセクションでは、既存のdotfilesをHome Managerに段階的に移行する戦略を学びます。一度にすべてを移行するのではなく、段階的に進めることで安全に移行できます。

## 移行戦略

### 段階的アプローチ

1. **Phase 1**: 基本的なパッケージインストール
2. **Phase 2**: シンプルな設定（Git、Starship）
3. **Phase 3**: シェル設定（zsh）
4. **Phase 4**: 複雑な設定（Neovim、tmux）
5. **Phase 5**: スクリプトと補助ツール

### 共存戦略

移行中は、Nix管理の設定と従来の設定を共存させます。

```
~/.dotfiles/
├── .gitconfig           # 既存（将来的に削除）
├── .zshrc               # 既存（将来的に削除）
├── flake.nix            # Nix（新規）
├── home.nix             # Nix（新規）
└── modules/             # Nix（新規）
    ├── git.nix
    └── zsh.nix
```

## Phase 1: 基本的なパッケージインストール

### 現在のパッケージを確認

```bash
# インストール済みパッケージを確認
which git vim curl jq ripgrep fd

# aptでインストールしたパッケージ（Ubuntuの場合）
apt list --installed | grep -E 'git|vim|curl'
```

### `home.nix`に追加

```nix
{ config, pkgs, ... }:

{
  home.stateVersion = "24.05";
  home.username = "aya";
  home.homeDirectory = "/home/aya";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # 既存環境で使っているツール
    git
    vim
    curl
    jq
    ripgrep
    fd
    bat
    htop
  ];
}
```

### 適用と確認

```bash
home-manager switch --flake ~/.dotfiles

# Nix管理のパッケージを確認
which git
# /home/aya/.nix-profile/bin/git

git --version
```

## Phase 2: Git設定の移行

### 既存の設定を確認

```bash
cat ~/.gitconfig
```

出力例:
```ini
[user]
    name = Aya
    email = aya@example.com
[core]
    editor = nvim
[init]
    defaultBranch = main
[alias]
    st = status
    co = checkout
```

### Home Managerで再現

`modules/git.nix`を作成:

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

`home.nix`でインポート:

```nix
{
  imports = [ ./modules/git.nix ];
  # ...
}
```

### 既存ファイルのバックアップと削除

```bash
# バックアップ
mv ~/.gitconfig ~/.gitconfig.backup

# 適用
home-manager switch --flake ~/.dotfiles

# 確認
git config --list
```

## Phase 3: zsh設定の移行

### 既存の設定を確認

```bash
cat ~/.zshrc
```

### 移行手順

#### 1. エイリアスの移行

既存の`.zshrc`:
```bash
alias ll='ls -la'
alias g='git'
alias vim='nvim'
```

Home Manager:
```nix
programs.zsh = {
  enable = true;

  shellAliases = {
    ll = "ls -la";
    g = "git";
    vim = "nvim";
  };
};
```

#### 2. 環境変数の移行

既存の`.zshrc`:
```bash
export EDITOR=nvim
export PATH=$HOME/.local/bin:$PATH
```

Home Manager:
```nix
programs.zsh = {
  enable = true;

  initExtra = ''
    export PATH=$HOME/.local/bin:$PATH
  '';
};

home.sessionVariables = {
  EDITOR = "nvim";
};
```

#### 3. プラグインの移行

既存の`.zshrc`（Oh My Zsh使用）:
```bash
plugins=(git docker npm)
ZSH_THEME="robbyrussell"
```

Home Manager:
```nix
programs.zsh = {
  enable = true;

  oh-my-zsh = {
    enable = true;
    theme = "robbyrussell";
    plugins = [ "git" "docker" "npm" ];
  };
};
```

#### 完成形: `modules/zsh.nix`

```nix
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

      # カスタム関数
      mkcd() {
        mkdir -p "$1" && cd "$1"
      }
    '';

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" "docker" ];
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

### 適用

```bash
# 既存の.zshrcをバックアップ
mv ~/.zshrc ~/.zshrc.backup

# 適用
home-manager switch --flake ~/.dotfiles

# 新しいシェルを起動して確認
exec zsh
```

## Phase 4: Neovim設定の移行

Neovim設定は複雑なため、2つのアプローチがあります。

### アプローチ1: `home.file`で丸ごとコピー（推奨）

既存の設定をそのまま使い続ける方法。

```nix
{
  programs.neovim.enable = true;

  home.file.".config/nvim" = {
    source = ./config/nvim;
    recursive = true;
  };
}
```

ディレクトリ構造:
```
~/.dotfiles/
├── flake.nix
├── home.nix
└── config/
    └── nvim/          # 既存のNeovim設定をコピー
        ├── init.lua
        └── lua/
```

### アプローチ2: `programs.neovim`で管理

Nix経由でプラグインを管理する方法。学習コストが高いため、慣れてから挑戦を推奨。

```nix
{
  programs.neovim = {
    enable = true;

    plugins = with pkgs.vimPlugins; [
      nvim-treesitter
      telescope-nvim
      lualine-nvim
    ];

    extraLuaConfig = ''
      -- Neovim設定をここに記述
      vim.opt.number = true
    '';
  };
}
```

## Phase 5: その他の設定ファイル

### tmux

```nix
{
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    keyMode = "vi";
    prefix = "C-a";

    extraConfig = ''
      # マウス有効化
      set -g mouse on

      # ペイン分割
      bind | split-window -h
      bind - split-window -v
    '';
  };
}
```

### lazygit

```nix
{
  programs.lazygit = {
    enable = true;
    settings = {
      gui.theme = {
        activeBorderColor = [ "green" "bold" ];
      };
    };
  };
}
```

## 移行のチェックリスト

### Git
- [ ] `~/.gitconfig`の内容を`modules/git.nix`に移行
- [ ] `git config --list`で確認
- [ ] 既存の`.gitconfig`をバックアップ・削除

### zsh
- [ ] エイリアスを`programs.zsh.shellAliases`に移行
- [ ] 環境変数を`home.sessionVariables`に移行
- [ ] プラグインを`programs.zsh.oh-my-zsh.plugins`に移行
- [ ] カスタム関数を`initExtra`に移行
- [ ] 新しいシェルで動作確認
- [ ] 既存の`.zshrc`をバックアップ・削除

### Neovim
- [ ] アプローチを決定（`home.file` or `programs.neovim`）
- [ ] 設定ファイルを配置
- [ ] Neovimを起動して動作確認

### その他
- [ ] tmux設定を移行
- [ ] lazygit設定を移行
- [ ] Starship設定を移行

## トラブルシューティング

### 問題: 既存の設定ファイルとの競合

**症状:**
```
error: collision between `/nix/store/...-home-manager-files/.gitconfig'
       and `/home/aya/.gitconfig'
```

**解決策:**

既存ファイルを削除またはバックアップ:
```bash
mv ~/.gitconfig ~/.gitconfig.backup
home-manager switch --flake ~/.dotfiles
```

### 問題: パスが通らない

**症状:**

Nix管理のパッケージが見つからない。

**解決策:**

シェルを再起動:
```bash
exec zsh
# または
source ~/.zshrc
```

### 問題: 設定が反映されない

**症状:**

`home-manager switch`後も設定が変わらない。

**確認:**

```bash
# 世代を確認
home-manager generations

# 現在のプロファイルを確認
ls -l ~/.local/state/home-manager/gcroots/current-home
```

## 移行後の管理

### 日常的な更新フロー

```bash
cd ~/.dotfiles

# 設定ファイルを編集
vim modules/git.nix

# 変更を適用
home-manager switch --flake .

# Gitにコミット
git add modules/git.nix
git commit -m "feat: update git aliases"
git push
```

### 依存関係の更新

```bash
# flake.lockを更新
nix flake update

# 適用
home-manager switch --flake .
```

## 確認ポイント

以下を確認してください。

- [ ] 既存のGit設定をHome Managerで管理していますか？
- [ ] zsh設定をHome Managerで管理していますか？
- [ ] Neovim設定の配置方法を決定しましたか？
- [ ] 既存dotfilesとNix設定の共存方法を理解していますか？
- [ ] 移行後の日常的な更新フローを理解していますか？

## 次のステップ

移行が完了したら、トラブルシューティングセクションを参照して、よくある問題の対処法を学びましょう。

→ [08. トラブルシューティング](./08-troubleshooting.md)

## 参考資料

- [Home Manager Manual - Usage](https://nix-community.github.io/home-manager/index.xhtml#ch-usage)
- [Nix Flakes - Practical Tutorial](https://serokell.io/blog/practical-nix-flakes)
