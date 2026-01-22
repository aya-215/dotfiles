# Flakes入門

## 概要

Flakesは、Nixプロジェクトの依存関係を明示的に管理し、再現性を向上させる仕組みです。このセクションでは、Flakesの基本概念と使い方を学びます。

## Flakesが解決する問題

### 従来の問題点

1. **依存関係の不透明性**: `<nixpkgs>`が何を指すのか不明確
2. **再現性の低さ**: 実行環境によって異なる結果
3. **NIX_PATH依存**: 環境変数に依存した動作

### Flakesの利点

1. **明示的な依存関係**: すべての入力を`flake.nix`で宣言
2. **ロックファイル**: `flake.lock`で依存関係のバージョンを固定
3. **標準化されたインターフェース**: `nix develop`、`nix build`などの統一されたコマンド

## Flakesの有効化

Flakesは実験的機能なので、明示的に有効化する必要があります。

```bash
# 一時的に有効化
nix --experimental-features 'nix-command flakes' <command>

# 恒久的に有効化（推奨）
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

## `flake.nix`の基本構造

最小限の`flake.nix`は以下のような構造です。

```nix
{
  description = "プロジェクトの説明";

  inputs = {
    # 依存関係を宣言
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    # 出力を定義
  };
}
```

### 各セクションの説明

#### `description`

プロジェクトの簡潔な説明です。省略可能ですが、記述を推奨します。

```nix
description = "My personal dotfiles managed with Nix";
```

#### `inputs`

プロジェクトが依存する外部リソースを宣言します。

```nix
inputs = {
  # GitHub リポジトリから取得
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # 別のFlakeから取得
  home-manager = {
    url = "github:nix-community/home-manager";
    # nixpkgsをこのflakeのものと揃える
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

**URL形式:**
- `github:owner/repo` - GitHubリポジトリ
- `github:owner/repo/branch` - 特定のブランチ
- `path:/path/to/dir` - ローカルパス
- `git+https://example.com/repo` - 任意のGitリポジトリ

#### `outputs`

Flakeが提供する成果物を定義します。

```nix
outputs = { self, nixpkgs }: {
  # devシェル
  devShells.x86_64-linux.default = ...;

  # パッケージ
  packages.x86_64-linux.myapp = ...;

  # Home Manager設定
  homeConfigurations."username" = ...;
};
```

**一般的な出力:**
- `packages.<system>.<name>` - ビルド可能なパッケージ
- `devShells.<system>.<name>` - 開発環境
- `apps.<system>.<name>` - 実行可能なアプリケーション
- `homeConfigurations.<name>` - Home Manager設定

## `flake.lock`の役割

`flake.lock`は、依存関係の正確なバージョン（コミットハッシュ）を記録します。

```json
{
  "nodes": {
    "nixpkgs": {
      "locked": {
        "lastModified": 1234567890,
        "narHash": "sha256-...",
        "owner": "NixOS",
        "repo": "nixpkgs",
        "rev": "abc123...",
        "type": "github"
      }
    }
  }
}
```

### 重要なポイント

- **自動生成**: `nix flake update`で更新
- **Gitにコミット**: チーム全体で同じバージョンを共有
- **再現性の要**: ロックファイルがあれば、いつでも同じ環境を再現できる

## 主要なFlakesコマンド

### `nix flake update`

依存関係を最新版に更新し、`flake.lock`を更新します。

```bash
# すべての依存関係を更新
nix flake update

# 特定の入力だけ更新
nix flake update nixpkgs
```

### `nix flake show`

Flakeが提供する出力を表示します。

```bash
nix flake show

# 出力例:
# github:owner/repo
# ├───devShells
# │   └───x86_64-linux
# │       └───default: development environment
# └───packages
#     └───x86_64-linux
#         └───myapp: package 'myapp'
```

### `nix flake metadata`

Flakeのメタデータを表示します。

```bash
nix flake metadata

# 出力例:
# Resolved URL:  github:owner/repo
# Locked URL:    github:owner/repo?rev=abc123...
# Description:   My project
# Last modified: 2024-01-01 12:00:00
```

### `nix develop`

開発環境に入ります。

```bash
# デフォルトのdevシェルに入る
nix develop

# 特定のdevシェルに入る
nix develop .#myshell
```

### `nix build`

パッケージをビルドします。

```bash
# デフォルトパッケージをビルド
nix build

# 特定のパッケージをビルド
nix build .#mypackage

# 結果はresultシンボリックリンクに配置される
ls -l result
```

### `nix run`

アプリケーションを実行します。

```bash
# デフォルトアプリを実行
nix run

# 特定のアプリを実行
nix run .#myapp
```

## 実践: 最初のFlakeを作る

### ステップ1: プロジェクトディレクトリ作成

```bash
mkdir -p ~/nix-practice
cd ~/nix-practice
```

### ステップ2: `flake.nix`を作成

```nix
{
  description = "My first Nix flake";

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
          vim
          curl
        ];

        shellHook = ''
          echo "Welcome to my Nix development environment!"
          echo "Available tools: git, vim, curl"
        '';
      };
    };
}
```

### ステップ3: Gitリポジトリ初期化

Flakesはデフォルトで追跡されていないファイルを無視するため、Gitリポジトリが必要です。

```bash
git init
git add flake.nix
```

### ステップ4: 開発環境に入る

```bash
nix develop
```

初回は依存関係をダウンロードするため時間がかかります。成功すると以下のように表示されます。

```
Welcome to my Nix development environment!
Available tools: git, vim, curl
```

### ステップ5: 環境を確認

```bash
# gitのバージョンを確認
git --version

# 環境から出る
exit
```

### ステップ6: `flake.lock`を確認

```bash
cat flake.lock
```

`flake.lock`が生成され、依存関係が記録されています。

```bash
git add flake.lock
git commit -m "feat: add first flake"
```

## `inputs.nixpkgs.follows`の意味

複数の依存関係が同じnixpkgsを使うように揃える仕組みです。

### 問題: 依存関係の重複

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  home-manager.url = "github:nix-community/home-manager";
  # home-managerも内部でnixpkgsを参照している
  # → 2つのnixpkgsがダウンロードされる
};
```

### 解決: `follows`で揃える

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";  # このflakeのnixpkgsを使う
  };
};
```

**利点:**
- ダウンロード量の削減
- ビルド時間の短縮
- 依存関係の一貫性

## 複数システムへの対応

異なるアーキテクチャ（x86_64-linux、aarch64-darwin等）に対応する方法。

### 方法1: 手動で列挙

```nix
outputs = { self, nixpkgs }: {
  devShells.x86_64-linux.default = ...;
  devShells.aarch64-linux.default = ...;
  devShells.x86_64-darwin.default = ...;
};
```

### 方法2: `flake-utils`を使う（推奨）

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.git ];
        };
      }
    );
}
```

## よくあるパターン

### パターン1: 開発環境のみ

```nix
{
  description = "Development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [ nodejs python3 ];
      };
    };
}
```

### パターン2: パッケージのビルド

```nix
{
  description = "My application";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        name = "myapp";
        src = ./.;
        buildInputs = [ pkgs.gcc ];
      };
    };
}
```

## トラブルシューティング

### エラー: `error: getting status of '/nix/store/...': No such file or directory`

**原因**: Gitで追跡されていないファイルを参照している

**解決策**:
```bash
git add <ファイル名>
```

### エラー: `error: experimental Nix feature 'flakes' is disabled`

**原因**: Flakesが有効化されていない

**解決策**:
```bash
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### エラー: `error: cannot find flake 'flake:nixpkgs' in the flake registries`

**原因**: インターネット接続の問題またはレジストリの問題

**解決策**:
```bash
# URLを完全に指定
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
```

## 実践演習

以下の演習を通して理解を深めてください。

### 演習1: 基本的なFlake

Node.js開発環境を提供するFlakeを作成してください。

<details>
<summary>解答例</summary>

```nix
{
  description = "Node.js development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nodejs
          nodePackages.npm
        ];

        shellHook = ''
          echo "Node.js $(node --version)"
          echo "npm $(npm --version)"
        '';
      };
    };
}
```
</details>

### 演習2: 複数のdevシェル

Python環境とRust環境、両方を提供するFlakeを作成してください。

<details>
<summary>解答例</summary>

```nix
{
  description = "Multiple development environments";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system} = {
        python = pkgs.mkShell {
          buildInputs = with pkgs; [ python3 python3Packages.pip ];
        };

        rust = pkgs.mkShell {
          buildInputs = with pkgs; [ rustc cargo ];
        };
      };
    };
}
```

使い方:
```bash
nix develop .#python
nix develop .#rust
```
</details>

## 確認ポイント

以下の質問に答えられるか確認してください。

- [ ] Flakesが解決する問題を説明できますか？
- [ ] `flake.nix`の基本構造（description、inputs、outputs）を理解していますか？
- [ ] `flake.lock`の役割を説明できますか？
- [ ] `inputs.nixpkgs.follows`の意味を理解していますか？
- [ ] `nix develop`で開発環境に入れますか？
- [ ] `nix flake update`で依存関係を更新できますか？
- [ ] シンプルなFlakeを自作できますか？

## 次のステップ

Flakesの基本を理解したら、次はHome Managerの導入に進みましょう。

→ [05. Home Manager](./05-home-manager.md)

## 参考資料

- [Nix Flakes - Official Manual](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html)
- [Practical Nix Flakes](https://serokell.io/blog/practical-nix-flakes)
- [Zero to Nix - Flakes](https://zero-to-nix.com/concepts/flakes)
