# コマンドリファレンス

## Nixコマンド

### `nix flake`

Flakeを管理するコマンド群。

```bash
# flakeの情報を表示
nix flake show [flake-url]

# flakeのメタデータを表示
nix flake metadata [flake-url]

# 依存関係を更新
nix flake update

# 特定の入力のみ更新
nix flake update nixpkgs

# 新しいflakeを初期化
nix flake init

# テンプレートから初期化
nix flake init -t templates#simple
```

### `nix develop`

開発環境に入る。

```bash
# デフォルトのdevシェルに入る
nix develop

# 特定のdevシェルに入る
nix develop .#myshell

# コマンドを実行して終了
nix develop --command bash -c "echo hello"

# 環境変数を確認
nix develop --print-build-logs
```

### `nix build`

パッケージをビルドする。

```bash
# デフォルトパッケージをビルド
nix build

# 特定のパッケージをビルド
nix build .#mypackage

# 結果をシンボリックリンク名を指定
nix build --out-link result-myapp

# ビルドログを表示
nix build --print-build-logs

# 詳細なエラー情報
nix build --show-trace
```

### `nix run`

アプリケーションを実行する。

```bash
# デフォルトアプリを実行
nix run

# 特定のアプリを実行
nix run .#myapp

# nixpkgsから直接実行
nix run nixpkgs#hello
```

### `nix search`

パッケージを検索する。

```bash
# nixpkgsからパッケージを検索
nix search nixpkgs <package-name>

# 正規表現で検索
nix search nixpkgs "^node"

# 詳細情報を表示
nix search nixpkgs nodejs --json
```

### `nix eval`

Nix式を評価する。

```bash
# 簡単な式を評価
nix eval --expr '1 + 1'

# flakeの属性を評価
nix eval .#homeConfigurations.username.config.programs.git.userName

# JSON形式で出力
nix eval --json .#packages.x86_64-linux
```

### `nix repl`

対話的REPLを起動する。

```bash
# REPLを起動
nix repl

# flakeを読み込んで起動
nix repl .

# nixpkgsを読み込んで起動
nix repl '<nixpkgs>'
```

**REPLコマンド:**
```nix
# flakeを読み込む
:lf .

# 型を表示
:t <expression>

# 終了
:q
```

### `nix log`

ビルドログを表示する。

```bash
# 最後のビルドのログ
nix log

# 特定のパスのログ
nix log /nix/store/...-package
```

### `nix store`

Nixストアを管理する。

```bash
# 2つのクロージャーの差分を表示
nix store diff-closures <path1> <path2>

# ストアパスの情報を表示
nix store info /nix/store/...

# ガベージコレクション
nix store gc

# ストアの最適化（重複ファイルを削除）
nix store optimise
```

### `nix-collect-garbage`

ガベージコレクションを実行する。

```bash
# 未使用のストアパスを削除
nix-collect-garbage

# 指定日数より古い世代を削除
nix-collect-garbage --delete-older-than 7d

# すべての古い世代を削除
nix-collect-garbage -d

# Home Manager特化
home-manager expire-generations "-7 days"
```

## Home Managerコマンド

### `home-manager switch`

設定を適用する。

```bash
# カレントディレクトリのflakeから適用
home-manager switch --flake .

# 特定のflakeから適用
home-manager switch --flake /path/to/dotfiles

# 特定の設定名を指定
home-manager switch --flake .#username

# 詳細なログを表示
home-manager switch --flake . --show-trace
```

### `home-manager build`

ビルドのみ行う（適用しない）。

```bash
# ビルドのみ
home-manager build --flake .

# 結果を確認
ls -l result
```

### `home-manager generations`

世代一覧を表示する。

```bash
# 世代一覧
home-manager generations

# 出力例:
# 2024-01-22 14:30 : id 3 -> /nix/store/...-home-manager-generation
```

### `home-manager packages`

インストール済みパッケージを表示する。

```bash
home-manager packages
```

### `home-manager news`

Home Managerのニュースを表示する。

```bash
home-manager news
```

### `home-manager expire-generations`

古い世代を削除する。

```bash
# 7日以上前の世代を削除
home-manager expire-generations "-7 days"

# 特定の世代IDを保持して他を削除
home-manager expire-generations +5
```

### `home-manager option`

オプションを検索する。

```bash
# オプションを検索
home-manager option programs.git

# すべてのオプションを表示
home-manager option
```

## よく使うコマンド組み合わせ

### 設定変更から適用まで

```bash
# 1. 設定ファイルを編集
vim ~/.dotfiles/modules/git.nix

# 2. ビルドして確認
home-manager build --flake ~/.dotfiles

# 3. 問題なければ適用
home-manager switch --flake ~/.dotfiles

# 4. Gitにコミット
cd ~/.dotfiles
git add modules/git.nix
git commit -m "feat: update git config"
git push
```

### 依存関係の更新

```bash
cd ~/.dotfiles

# flake.lockを更新
nix flake update

# ビルドして確認
home-manager build --flake .

# 適用
home-manager switch --flake .

# コミット
git add flake.lock
git commit -m "chore: update flake dependencies"
git push
```

### 世代のロールバック

```bash
# 世代一覧を表示
home-manager generations

# 前の世代に戻す（例: id 2）
/nix/store/...-home-manager-generation-2/activate

# または
home-manager generations | grep "id 2" | awk '{print $NF "/activate"}' | sh
```

### ディスク使用量の削減

```bash
# 古い世代を削除
nix-collect-garbage --delete-older-than 7d

# ストアを最適化
nix store optimise

# ディスク使用量を確認
du -sh /nix/store
```

### デバッグ

```bash
# 詳細なエラー情報を表示
home-manager switch --flake . --show-trace

# ビルドログを確認
nix log

# replで設定を確認
nix repl .
# :lf .
# outputs.homeConfigurations."username".config.programs.git
```

## 便利なエイリアス

`~/.zshrc`や`home.nix`に追加すると便利なエイリアス。

### Bash/Zsh用

```bash
alias hm="home-manager switch --flake ~/.dotfiles"
alias hmb="home-manager build --flake ~/.dotfiles"
alias hmg="home-manager generations"
alias nfu="nix flake update"
alias ngc="nix-collect-garbage -d"
```

### Home Manager用

```nix
programs.zsh.shellAliases = {
  hm = "home-manager switch --flake ~/.dotfiles";
  hmb = "home-manager build --flake ~/.dotfiles";
  hmg = "home-manager generations";
  nfu = "nix flake update";
  ngc = "nix-collect-garbage -d";
};
```

## その他の便利なコマンド

### パッケージ情報の確認

```bash
# パッケージの依存関係を表示
nix-store --query --references $(which git)

# パッケージサイズを確認
nix path-info -Sh nixpkgs#git

# パッケージの詳細情報
nix search nixpkgs git --json | jq
```

### flakeのテンプレート

```bash
# 利用可能なテンプレート一覧
nix flake show templates

# テンプレートから初期化
nix flake init -t templates#simpleContainer
```

## 参考資料

- [Nix Command Reference](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix.html)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
