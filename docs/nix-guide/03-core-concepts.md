# 核心概念

## 概要

このセクションでは、Nixを理解する上で重要な核心概念を学びます。これらの概念を理解することで、Nixの設計思想と利点がわかります。

## 宣言的 vs 命令的

### 命令的アプローチ（従来の方法）

**何をするか**を記述します。

```bash
# シェルスクリプト例
sudo apt update
sudo apt install git
git config --global user.name "Alice"
git config --global user.email "alice@example.com"
echo 'export EDITOR=vim' >> ~/.bashrc
```

**問題点:**
- 実行順序に依存
- べき等性がない（2回実行すると異なる結果）
- 現在の状態を把握しにくい
- ロールバックが困難

### 宣言的アプローチ（Nixの方法）

**どうあるべきか**を記述します。

```nix
# home.nix
{
  programs.git = {
    enable = true;
    userName = "Alice";
    userEmail = "alice@example.com";
  };

  home.sessionVariables = {
    EDITOR = "vim";
  };
}
```

**利点:**
- 実行順序に依存しない
- べき等性がある（何度実行しても同じ結果）
- 現在の状態が一目でわかる
- ロールバックが容易

## 純粋性と再現性

### 純粋性

Nixのビルドは**純粋関数**です。

- 同じ入力 → 常に同じ出力
- 副作用なし
- 外部の状態に依存しない

### 具体例

**従来の方法（非純粋）:**
```bash
# ビルド時にインターネットから最新版をダウンロード
npm install
# → 実行時期によって異なるバージョンがインストールされる
```

**Nixの方法（純粋）:**
```nix
# 依存関係のハッシュを固定
{
  nodejs = pkgs.nodejs-18_x;  # バージョン固定
  # flake.lockで正確なコミットハッシュを記録
}
```

### 再現性

純粋性により、再現性が保証されます。

- **マシンAでビルド** → ハッシュ `abc123...`
- **マシンBでビルド** → ハッシュ `abc123...`（同じ）

これにより「私の環境では動くけど、あなたの環境では動かない」問題が解消されます。

## Nixストア

### `/nix/store`とは

Nixが管理するすべてのパッケージとビルド成果物が格納される場所です。

```bash
ls /nix/store | head -5
```

**出力例:**
```
0a1b2c3d4e5f-glibc-2.38
1b2c3d4e5f6a-bash-5.2-p15
2c3d4e5f6a7b-git-2.42.0
...
```

### ハッシュベースのパス

各パッケージは一意のハッシュを持ちます。

```
/nix/store/<hash>-<name>-<version>
           ^^^^^^
           ハッシュ（入力から計算）
```

**ハッシュに含まれるもの:**
- ソースコード
- ビルドスクリプト
- 依存関係
- ビルド環境

**重要な特性:**
- 入力が同じ → ハッシュが同じ
- 入力が異なる → ハッシュが異なる

### 利点

#### 1. 複数バージョンの共存

```
/nix/store/abc123-python-3.10.0
/nix/store/def456-python-3.11.0
/nix/store/ghi789-python-3.12.0
```

すべて同時にインストール可能。環境ごとに異なるバージョンを使用できます。

#### 2. 依存関係の競合解消

```
アプリA → libfoo-1.0
アプリB → libfoo-2.0
```

両方とも問題なく動作します（別々のハッシュで保存）。

#### 3. 原子的なアップグレード

```bash
# アップグレード中にクラッシュしても問題なし
home-manager switch --flake .
```

新しい環境が完全にビルドされるまで、古い環境は影響を受けません。

## derivation（デリベーション）

### derivationとは

パッケージのビルド方法を記述したものです。Nixの最も基本的な構成要素です。

### 簡単な例

```nix
derivation {
  name = "hello";
  system = "x86_64-linux";
  builder = "/bin/sh";
  args = [ "-c" "echo 'Hello, Nix!' > $out" ];
}
```

### derivationの要素

1. **name**: パッケージ名
2. **system**: ビルド対象システム
3. **builder**: ビルドを実行するプログラム
4. **args**: builderに渡す引数
5. **outputs**: ビルド結果の出力先（デフォルトは`$out`）

### ビルドプロセス

```
入力（derivation）
  ↓
ハッシュ計算
  ↓
/nix/store/<hash>-<name> に出力
  ↓
結果をキャッシュ
```

### 実際の使用

通常は`stdenv.mkDerivation`などのヘルパー関数を使います。

```nix
pkgs.stdenv.mkDerivation {
  name = "myapp";
  src = ./src;

  buildInputs = [ pkgs.gcc ];

  buildPhase = ''
    gcc -o myapp main.c
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp myapp $out/bin/
  '';
}
```

## プロファイルとジェネレーション

### プロファイル

ユーザー環境の現在の状態を指すシンボリックリンクです。

```bash
ls -l ~/.nix-profile
# -> /nix/var/nix/profiles/per-user/yourusername/profile
```

### ジェネレーション

環境の各バージョン（変更履歴）です。

```bash
# Home Managerのジェネレーション一覧
home-manager generations
```

**出力例:**
```
2024-01-22 14:30 : id 3 -> /nix/store/...-home-manager-generation
2024-01-22 12:00 : id 2 -> /nix/store/...-home-manager-generation
2024-01-21 18:45 : id 1 -> /nix/store/...-home-manager-generation
```

### 世代管理のメリット

```bash
# 設定を変更
home-manager switch --flake .

# 問題が発生した場合、前の世代に戻す
/nix/store/...-home-manager-generation-2/activate

# または
home-manager generations | grep "id 2" | awk '{print $NF "/activate"}' | sh
```

## Nixの保証

### 1. 再現性

同じ`flake.lock`があれば、どの環境でも同じ結果が得られます。

### 2. 原子性

アップグレードやインストールは原子的（all-or-nothing）です。途中で失敗しても、既存環境は影響を受けません。

### 3. ロールバック可能

すべての変更は世代として記録され、いつでも戻せます。

### 4. 安全性

異なるプロジェクトやユーザーが互いに影響を与えません。

## 実践例: 概念の確認

### 例1: Nixストアの探索

```bash
# 自分の環境で使用しているパッケージを確認
ls -l ~/.nix-profile/bin/git
# -> /nix/store/...-git-2.42.0/bin/git

# Nixストア内のgitを確認
ls /nix/store/*-git-*/bin/git
```

### 例2: 純粋性の確認

```bash
cd ~/nix-practice

# flake.nixを作成
cat > flake.nix << 'EOF'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.${system}.hello = pkgs.writeShellScriptBin "hello" ''
        echo "Hello from $(date)"
      '';
    };
}
EOF

git init
git add flake.nix

# ビルド（2回実行）
nix build .#hello
HASH1=$(readlink result)

nix build .#hello
HASH2=$(readlink result)

# ハッシュが同じことを確認
echo $HASH1
echo $HASH2
# → 同じハッシュが表示される
```

### 例3: 世代の確認

```bash
# Home Managerの世代一覧
home-manager generations

# 各世代の差分を確認
nix store diff-closures \
  $(home-manager generations | tail -2 | head -1 | awk '{print $NF}') \
  $(home-manager generations | tail -1 | awk '{print $NF}')
```

## 他のパッケージマネージャとの比較

| 特徴 | apt/yum | npm/pip | Nix |
|------|---------|---------|-----|
| 宣言的 | ❌ | ❌ | ✅ |
| 再現性 | ❌ | 部分的 | ✅ |
| ロールバック | ❌ | ❌ | ✅ |
| 複数バージョン共存 | ❌ | 部分的 | ✅ |
| 依存関係の競合 | 頻繁 | 頻繁 | なし |
| 原子的アップグレード | ❌ | ❌ | ✅ |

## よくある誤解

### 誤解1: 「Nixは遅い」

**真実**: 初回ビルドは時間がかかるが、以降はキャッシュが効く。バイナリキャッシュ（cache.nixos.org）を使えば、ほとんどビルド不要。

### 誤解2: 「Nixストアが肥大化する」

**真実**: `nix-collect-garbage`で未使用の世代を削除可能。ディスク使用量は制御できます。

```bash
# 7日以上前の世代を削除
nix-collect-garbage --delete-older-than 7d
```

### 誤解3: 「Nixは学習コストが高い」

**真実**: 基本的な使い方は比較的シンプル。このガイドで段階的に学べます。

## 確認ポイント

以下の質問に答えられるか確認してください。

- [ ] 宣言的アプローチと命令的アプローチの違いを説明できますか？
- [ ] 純粋性が再現性にどう寄与するか説明できますか？
- [ ] Nixストア（`/nix/store`）の役割を説明できますか？
- [ ] ハッシュベースのパスの利点を3つ挙げられますか？
- [ ] derivationの概念を理解していますか？
- [ ] プロファイルとジェネレーションの違いを説明できますか？

## 次のステップ

核心概念を理解したら、次はFlakesについて学びましょう。

→ [04. Flakes](./04-flakes.md)

## 参考資料

- [Nix Pills - Chapter 4: The Basics of the Language](https://nixos.org/guides/nix-pills/basics-of-language)
- [Nix Manual - Store](https://nixos.org/manual/nix/stable/store/)
- [Zero to Nix - Concepts](https://zero-to-nix.com/concepts/)
