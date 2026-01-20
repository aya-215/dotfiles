# Nix学習計画

## 概要
WSL + zsh環境でNixを学習し、段階的にdotfilesをNix/Home Managerで管理できるようになるための計画。

---

## Phase 1: Nixの基礎理解（1-2日）

### 目標
Nixパッケージマネージャーの基本操作を習得する

### タスク
1. **Nixのインストール**
   ```bash
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```
   - インストール後、シェルを再起動

2. **基本コマンドを試す**
   ```bash
   # 一時的にパッケージを使う（nix-shell）
   nix-shell -p cowsay lolcat
   cowsay "Hello Nix" | lolcat
   exit  # 抜けるとパッケージは消える

   # パッケージ検索
   nix-env -qaP | grep ripgrep

   # パッケージインストール
   nix-env -iA nixpkgs.hello

   # インストール済み一覧
   nix-env -q

   # アンインストール
   nix-env -e hello
   ```

3. **チャネルの理解**
   ```bash
   # 現在のチャネル確認
   nix-channel --list

   # チャネル更新
   nix-channel --update
   ```

### 確認ポイント
- [ ] `nix-shell`で一時的な環境を作れる
- [ ] パッケージのインストール/アンインストールができる

---

## Phase 2: Home Managerの導入（1-2日）

### 目標
Home Managerをセットアップし、最初の設定を書く

### タスク
1. **Home Managerのインストール**
   ```bash
   # チャネル追加
   nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
   nix-channel --update

   # インストール
   nix-shell '<home-manager>' -A install
   ```

2. **初期設定ファイルの編集**
   `~/.config/home-manager/home.nix`:
   ```nix
   { config, pkgs, ... }:

   {
     home.username = "aya";
     home.homeDirectory = "/home/aya";
     home.stateVersion = "24.05";

     # 最初は少数のパッケージから
     home.packages = with pkgs; [
       ripgrep
       fd
       bat
     ];

     programs.home-manager.enable = true;
   }
   ```

3. **設定の適用**
   ```bash
   home-manager switch
   ```

### 確認ポイント
- [ ] `home-manager switch`が成功する
- [ ] 宣言したパッケージが使える

---

## Phase 3: 簡単なdotfilesの移行（2-3日）

### 目標
既存のシンプルな設定をHome Managerに移行する

### タスク
1. **Gitの設定を移行**
   ```nix
   programs.git = {
     enable = true;
     userName = "Your Name";
     userEmail = "your@email.com";
     extraConfig = {
       init.defaultBranch = "main";
       pull.rebase = true;
     };
   };
   ```

2. **Zshの基本設定を移行**
   ```nix
   programs.zsh = {
     enable = true;
     shellAliases = {
       ll = "ls -la";
       vim = "nvim";
       # 既存のエイリアスを追加
     };
     initExtra = ''
       # 既存の.zshrcから必要な設定をコピー
     '';
   };
   ```

3. **home.fileで既存dotfilesをリンク**
   まだHome Manager対応していない設定は直接リンク：
   ```nix
   home.file = {
     ".config/starship.toml".source = ./dotfiles/starship.toml;
   };
   ```

### 確認ポイント
- [ ] `git config --list`で設定が反映されている
- [ ] zshのエイリアスが動作する

---

## Phase 4: 複雑な設定の移行（1週間〜）

### 目標
Neovim等の複雑な設定をNixで管理する

### タスク
1. **Neovimの設定を検討**
   - オプションA: `home.file`で既存設定をそのまま使う（簡単）
   - オプションB: `programs.neovim`で宣言的に管理（学習コスト高）

   オプションAの例：
   ```nix
   programs.neovim = {
     enable = true;
     defaultEditor = true;
   };

   # 既存の設定をそのまま使う
   home.file.".config/nvim" = {
     source = ./nvim;
     recursive = true;
   };
   ```

2. **その他のツール設定を移行**
   - lazygit
   - wezterm
   - etc.

### 確認ポイント
- [ ] Neovimが正常に起動する
- [ ] プラグインが動作する

---

## Phase 5: Flakesへの移行（オプション・上級）

### 目標
より再現性の高いFlakesベースの管理に移行

### タスク
1. **flake.nixの作成**
2. **バージョン固定**
3. **複数マシン対応**

※ Phase 4まで完了してから検討

---

## 学習リソース

| リソース | 用途 |
|---------|------|
| [Nix Pills](https://nixos.org/guides/nix-pills/) | Nixの深い理解 |
| [Home Manager Options](https://home-manager-options.extranix.com/) | オプション検索 |
| [MyNixOS](https://mynixos.com/) | 設定例の検索 |
| [Zero to Nix](https://zero-to-nix.com/) | インタラクティブ学習 |

---

## 注意事項

- **既存環境を壊さない**: 最初は並行運用し、動作確認後に既存設定を削除
- **バックアップを取る**: 移行前に現在のdotfilesをコミット
- **少しずつ進める**: 一度に全部移行しようとしない
- **エラーを恐れない**: `home-manager generations`で過去の状態に戻せる

---

## 現在の環境との統合案

現在の`.dotfiles`構造を活かしつつNixを導入：

```
.dotfiles/
├── .config/
│   ├── home-manager/     # 新規: Nix設定
│   │   └── home.nix
│   ├── nvim/             # 既存: そのまま維持
│   └── ...
└── ...
```

最初は`home.file`で既存設定をリンクし、徐々にNix nativeな設定に移行する戦略を推奨。
