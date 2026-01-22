# 学習リソース

## 公式ドキュメント

### Nix

- [Nix Manual](https://nixos.org/manual/nix/stable/)
  - 公式マニュアル。リファレンスとして活用
- [Nix Reference](https://nixos.org/manual/nix/stable/language/)
  - 言語仕様の詳細
- [Nix Command Reference](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix)
  - コマンドリファレンス

### Home Manager

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
  - Home Managerの公式マニュアル
- [Home Manager Options Search](https://home-manager-options.extranix.com/)
  - 利用可能なオプションを検索
- [Home Manager GitHub](https://github.com/nix-community/home-manager)
  - ソースコードと Issue

### nixpkgs

- [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/)
  - パッケージの使い方とカスタマイズ
- [Package Search](https://search.nixos.org/packages)
  - パッケージ検索

## 学習サイト

### Zero to Nix

- URL: https://zero-to-nix.com/
- **おすすめ度**: ★★★★★
- **対象**: 初学者
- **特徴**: 実践的なチュートリアル、わかりやすい説明

### Nix Pills

- URL: https://nixos.org/guides/nix-pills/
- **おすすめ度**: ★★★★☆
- **対象**: 中級者
- **特徴**: Nixの内部動作を深く理解できる

### nix.dev

- URL: https://nix.dev/
- **おすすめ度**: ★★★★★
- **対象**: 初学者〜中級者
- **特徴**: 公式の学習サイト、チュートリアルとガイドが充実

## ブログ記事・チュートリアル

### 英語

- [Practical Nix Flakes](https://serokell.io/blog/practical-nix-flakes)
  - Flakesの実践的な使い方
- [Nix Flakes: An Introduction](https://www.tweag.io/blog/2020-05-25-flakes/)
  - Flakesの概要と設計思想
- [NixOS & Flakes Book](https://nixos-and-flakes.thiscute.world/)
  - NixOSとFlakesの包括的なガイド

### 日本語

- [Nix入門](https://zenn.dev/asa1984/articles/nix-introduction)
  - 日本語でのNix入門記事
- [NixOS Wiki（日本語）](https://nixos.wiki/wiki/Main_Page/ja)
  - 日本語のWiki（一部のみ翻訳）

## コミュニティ

### フォーラム・ディスカッション

- [NixOS Discourse](https://discourse.nixos.org/)
  - 公式フォーラム。質問や議論
- [r/NixOS (Reddit)](https://www.reddit.com/r/NixOS/)
  - Reddit コミュニティ

### チャット

- [NixOS Discord](https://discord.gg/nixos)
  - リアルタイムチャット
- [Matrix (Nix)](https://matrix.to/#/#nix:nixos.org)
  - Matrix チャンネル

### GitHub

- [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs)
  - パッケージリポジトリ
- [nix-community](https://github.com/nix-community)
  - コミュニティプロジェクト

## 設定例の探し方

### GitHub検索

```
site:github.com "flake.nix" "home-manager"
site:github.com "modules" "home.nix"
```

### 有名なdotfilesリポジトリ

- [hlissner/dotfiles](https://github.com/hlissner/dotfiles)
  - 大規模で充実したdotfiles
- [Misterio77/nix-config](https://github.com/Misterio77/nix-config)
  - モジュール構成の参考に
- [nmasur/dotfiles](https://github.com/nmasur/dotfiles)
  - Home Managerの実例

### 検索のコツ

1. GitHub検索で `"home-manager" "flake.nix"`
2. Stars数でソート
3. 最近更新されているものを優先
4. 自分の環境に近いもの（WSL、macOSなど）を探す

## YouTube・動画教材

- [Nix - A Deep Dive (Burke Libbey)](https://www.youtube.com/watch?v=2LW8V6WY93s)
  - Nixの深い理解に
- [Vimjoyer - Nix Playlist](https://www.youtube.com/playlist?list=PLko9chwSoP-15ZtZxu64k_CuTzXrFpxPE)
  - Nixの実践的なチュートリアル

## 書籍（英語）

現時点でNixに特化した包括的な書籍は少ないですが、以下が参考になります。

- オンラインドキュメントとコミュニティリソースが主要な学習源

## ツール

### エディタサポート

#### VSCode

- [Nix IDE](https://marketplace.visualstudio.com/items?itemName=jnoortheen.nix-ide)
  - シンタックスハイライト、補完

#### Neovim

- [vim-nix](https://github.com/LnL7/vim-nix)
  - シンタックスハイライト
- [nvim-lspconfig (nil)](https://github.com/neovim/nvim-lspconfig)
  - Language Server Protocol

### フォーマッタ

- [nixpkgs-fmt](https://github.com/nix-community/nixpkgs-fmt)
  - 公式推奨フォーマッタ
- [alejandra](https://github.com/kamadorueda/alejandra)
  - モダンなフォーマッタ

```nix
home.packages = [ pkgs.nixpkgs-fmt ];
```

### 静的解析

- [statix](https://github.com/nerdypepper/statix)
  - Linter

## 最新情報の追い方

### ブログ

- [NixOS Weekly](https://weekly.nixos.org/)
  - 週次ニュースレター
- [Tweag Blog](https://www.tweag.io/blog/)
  - Nixに関する記事が多い

### Twitter/X

- [@NixOS_org](https://twitter.com/NixOS_org)
  - 公式アカウント
- [#NixOS](https://twitter.com/hashtag/NixOS)
  - ハッシュタグ

## よくある質問の調べ方

1. **エラーメッセージで検索**
   ```
   site:discourse.nixos.org "error message"
   ```

2. **GitHub Issuesを検索**
   ```
   site:github.com/nix-community/home-manager "error message"
   ```

3. **公式マニュアルを確認**
   - [Nix Manual](https://nixos.org/manual/nix/stable/)

## 次のステップ

学習リソースを活用しながら、実際に手を動かして学習を進めてください。

コマンドリファレンスや設定例も参照してください。

- [Appendix: コマンドリファレンス](./appendix/commands.md)
- [Appendix: 設定例集](./appendix/examples.md)

## 貢献・フィードバック

このガイドへの改善提案は、dotfilesリポジトリのIssueで受け付けています。
