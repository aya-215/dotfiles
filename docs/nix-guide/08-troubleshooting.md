# トラブルシューティング

## 概要

このセクションでは、Nix/Home Managerを使う際によく遭遇するエラーと対処法をまとめています。

## よくあるエラー

### 1. infinite recursion

**エラーメッセージ:**
```
error: infinite recursion encountered
```

**原因:**

自己参照による無限ループが発生している。

**よくあるケース:**

```nix
# ❌ 間違い
let
  x = x + 1;  # xが自分自身を参照
in x

# ❌ 間違い（属性セットでの循環参照）
rec {
  a = b;
  b = a;
}
```

**解決策:**

- `rec`の使用を避ける
- 参照関係を見直す
- `let-in`で明示的に依存関係を定義

```nix
# ✅ 正しい
let
  x = 5;
  y = x + 1;
in y
```

### 2. attribute missing

**エラーメッセージ:**
```
error: attribute 'packageName' missing
```

**原因:**

存在しない属性を参照している。

**解決策:**

```bash
# パッケージ名を検索
nix search nixpkgs packagename

# 属性パスを確認
nix eval nixpkgs#packageName
```

### 3. undefined variable

**エラーメッセージ:**
```
error: undefined variable 'variableName'
```

**原因:**

変数が定義されていないか、スコープ外。

**解決策:**

```nix
# ❌ 間違い
{
  x = 5;
  y = z + 1;  # zが未定義
}

# ✅ 正しい
let
  z = 10;
in {
  x = 5;
  y = z + 1;
}
```

### 4. collision between files

**エラーメッセージ:**
```
error: collision between `/nix/store/...' and `/home/user/.config/...'
```

**原因:**

Home Managerが管理しようとしているファイルが既に存在している。

**解決策:**

既存ファイルをバックアップして削除:

```bash
mv ~/.gitconfig ~/.gitconfig.backup
home-manager switch --flake ~/.dotfiles
```

### 5. experimental feature 'flakes' is disabled

**エラーメッセージ:**
```
error: experimental Nix feature 'flakes' is disabled
```

**原因:**

Flakesが有効化されていない。

**解決策:**

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 6. getting status of ... : No such file or directory

**エラーメッセージ:**
```
error: getting status of '/nix/store/...': No such file or directory
```

**原因:**

Gitで追跡されていないファイルを参照している。

**解決策:**

```bash
# ファイルをGitに追加
git add <ファイル名>

# または.gitignoreに追加して意図的に除外
```

### 7. builder for ... failed with exit code 1

**エラーメッセージ:**
```
error: builder for '/nix/store/...' failed with exit code 1
```

**原因:**

ビルドプロセスが失敗している。

**デバッグ方法:**

```bash
# 詳細なエラー情報を表示
nix build --show-trace

# ビルドログを確認
nix log /nix/store/...

# 失敗したビルド環境に入る
nix develop /nix/store/...
```

## デバッグ方法

### `--show-trace`

詳細なスタックトレースを表示します。

```bash
home-manager switch --flake . --show-trace
```

### `nix repl`でのデバッグ

```bash
nix repl
```

```nix
# flakeを読み込む
:lf .

# 出力を確認
outputs.homeConfigurations."username".config.programs.git.userName

# 属性を探索
:t outputs.homeConfigurations
```

### `nix eval`

式を評価します。

```bash
# flakeの出力を評価
nix eval .#homeConfigurations.username.config.programs.git.userName

# デバッグ情報を表示
nix eval --show-trace .#homeConfigurations.username.config
```

### `nix log`

ビルドログを確認します。

```bash
# 最後のビルドのログ
nix log

# 特定のパスのログ
nix log /nix/store/...-package
```

### `nix store diff-closures`

世代間の差分を確認します。

```bash
nix store diff-closures \
  ~/.local/state/home-manager/gcroots/previous-home \
  ~/.local/state/home-manager/gcroots/current-home
```

## パフォーマンスの問題

### ビルドが遅い

**原因:**

- バイナリキャッシュが利用されていない
- 大量のパッケージを一度にビルドしている

**解決策:**

```nix
# flake.nixでバイナリキャッシュを設定
{
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };
}
```

### ディスク使用量が多い

**原因:**

古い世代が残っている。

**解決策:**

```bash
# 7日以上前の世代を削除
nix-collect-garbage --delete-older-than 7d

# すべての古い世代を削除
nix-collect-garbage -d

# Home Manager特化
home-manager expire-generations "-7 days"
```

## アンチパターン

### 1. `nix-env`の使用

**❌ 避けるべき:**
```bash
nix-env -iA nixpkgs.git
```

**✅ 推奨:**

Home Managerまたはdevシェルで管理:
```nix
home.packages = [ pkgs.git ];
```

**理由:**

- `nix-env`は宣言的ではない
- Flakesと相性が悪い
- 依存関係の管理が不透明

### 2. `with`の過度な使用

**❌ 避けるべき:**
```nix
with pkgs; with lib; with builtins;
  mkIf enable [ git vim ]
```

**✅ 推奨:**
```nix
lib.mkIf config.myModule.enable [
  pkgs.git
  pkgs.vim
]
```

**理由:**

- どこから来た変数か不明確
- 名前の衝突リスク
- デバッグが困難

### 3. `rec`の多用

**❌ 避けるべき:**
```nix
rec {
  a = 5;
  b = a + 1;
  c = b + 1;
}
```

**✅ 推奨:**
```nix
let
  a = 5;
  b = a + 1;
  c = b + 1;
in {
  inherit a b c;
}
```

**理由:**

- 無限再帰のリスク
- エラーメッセージが不明確
- `let-in`の方が明示的

### 4. 直接的なファイルパス参照

**❌ 避けるべき:**
```nix
home.file.".config/nvim".source = /home/user/dotfiles/nvim;
```

**✅ 推奨:**
```nix
home.file.".config/nvim".source = ./nvim;
```

**理由:**

- 絶対パスは移植性がない
- 相対パスの方が安全

## よくある質問

### Q: Home Manager適用後、既存の設定が消えた

**A:**

Home Managerは明示的に管理しているファイルのみを上書きします。バックアップから復元するか、`home.file`で明示的に管理してください。

### Q: パッケージが見つからない

**A:**

```bash
# パッケージを検索
nix search nixpkgs <package-name>

# または
https://search.nixos.org/packages
```

### Q: 設定変更が反映されない

**A:**

```bash
# シェルを再起動
exec zsh

# または完全にログアウト/ログイン
```

### Q: Flakesの依存関係を更新したい

**A:**

```bash
# すべての依存関係を更新
nix flake update

# 特定の入力のみ更新
nix flake update nixpkgs

# 適用
home-manager switch --flake .
```

## エラーメッセージの読み方

### 構造

```
error: <エラーの種類>

       at /path/to/file.nix:10:5:

            9|   programs.git = {
           10|     usrName = "Alice";  # typo
             |     ^
           11|   };

       Did you mean userName?
```

### 重要な情報

1. **エラーの種類**: `undefined variable`、`infinite recursion`など
2. **ファイルパスと行番号**: エラーの発生箇所
3. **コンテキスト**: 問題のコード周辺
4. **提案**: 修正のヒント

## トラブル時のチェックリスト

1. [ ] エラーメッセージを最後まで読む
2. [ ] `--show-trace`で詳細情報を確認
3. [ ] ファイルパスと行番号を確認
4. [ ] `nix repl`で式を評価してみる
5. [ ] Gitで追跡されているか確認
6. [ ] Flakesが有効化されているか確認
7. [ ] 公式ドキュメントやコミュニティで検索

## 次のステップ

トラブルシューティングの基本を理解したら、用語集で専門用語を確認しましょう。

→ [09. 用語集](./09-glossary.md)

## 参考資料

- [Nix Manual - Troubleshooting](https://nixos.org/manual/nix/stable/troubleshooting.html)
- [NixOS Discourse](https://discourse.nixos.org/)
- [Home Manager Issues](https://github.com/nix-community/home-manager/issues)
