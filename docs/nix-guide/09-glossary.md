# 用語集

## A

### Attribute Set（属性セット）

Nix言語の基本的なデータ構造。他の言語でいうオブジェクトや辞書に相当します。

```nix
{ name = "Alice"; age = 25; }
```

## D

### Derivation（デリベーション）

パッケージのビルド方法を記述したもの。Nixの最も基本的な構成要素です。

```nix
derivation {
  name = "hello";
  builder = "/bin/sh";
  # ...
}
```

### Dev Shell（開発シェル）

特定のプロジェクトに必要なツールが揃った一時的な環境。`nix develop`で起動します。

## F

### Flake

Nixプロジェクトの依存関係を明示的に管理するための仕組み。`flake.nix`ファイルで定義します。

### `flake.lock`

Flakeの依存関係の正確なバージョン（コミットハッシュ）を記録するファイル。再現性の要です。

### `flake.nix`

Flakeの定義ファイル。`inputs`（依存関係）と`outputs`（成果物）を記述します。

## G

### Generation（ジェネレーション/世代）

環境の各バージョン。Home Managerは各適用時に新しい世代を作成します。簡単にロールバック可能です。

## H

### Home Manager

ユーザー環境とdotfilesをNixで宣言的に管理するためのツール。

## I

### `inputs`

Flakeの依存関係を宣言するセクション。他のFlakeやパッケージリポジトリを指定します。

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
};
```

## L

### `let-in`式

ローカル変数を定義するための構文。

```nix
let
  x = 5;
  y = 10;
in
  x + y
```

## M

### Module（モジュール）

設定を構造化して再利用可能にするための仕組み。`imports`で他のモジュールを読み込めます。

## N

### Nix

- **言語**: 純粋関数型の設定記述言語
- **パッケージマネージャ**: 宣言的にパッケージを管理
- **ビルドシステム**: 再現可能なビルド

### Nix Store（Nixストア）

すべてのパッケージとビルド成果物が格納される場所（`/nix/store`）。

### nixpkgs

Nixパッケージの巨大なコレクション。80,000以上のパッケージが含まれています。

## O

### `outputs`

Flakeが提供する成果物を定義するセクション。パッケージ、開発環境、設定などを含みます。

```nix
outputs = { nixpkgs, ... }: {
  packages.x86_64-linux.myapp = ...;
};
```

## P

### Package（パッケージ）

ソフトウェアとその依存関係を含むビルド成果物。

### Profile（プロファイル）

ユーザー環境の現在の状態を指すシンボリックリンク（`~/.nix-profile`）。

### Pure（純粋）

副作用がなく、同じ入力に対して常に同じ出力を返す性質。Nixビルドは純粋です。

## R

### Reproducibility（再現性）

同じ入力から常に同じ結果を得られる性質。Nixの核心的な特徴です。

## S

### Substituter（代替元/バイナリキャッシュ）

ビルド済みパッケージを配信するサーバー。ローカルでビルドする代わりにダウンロードできます。

```
https://cache.nixos.org
```

## 日本語対応表

| 英語 | 日本語 |
|------|--------|
| Attribute Set | 属性セット |
| Declarative | 宣言的 |
| Derivation | デリベーション |
| Flake | フレーク |
| Generation | 世代 |
| Imperative | 命令的 |
| Module | モジュール |
| Package | パッケージ |
| Pure | 純粋 |
| Reproducibility | 再現性 |
| Store | ストア |

## 次のステップ

用語を確認したら、学習リソースをチェックして理解を深めましょう。

→ [10. 学習リソース](./10-resources.md)
