# Nix学習ガイド - Flakesベース

## 概要

このガイドは、Nix初学者がFlakesを使ってHome Managerでdotfilesを宣言的に管理できるようになるための学習パスです。

### 対象読者

- Nix基本コマンド習得済み（Phase 1完了）
- WSL + zsh環境
- 目標: Home Managerでdotfilesを宣言的に管理

### 前提条件

- Nixインストール済み
- `nix --version`で動作確認済み
- 基本的なシェル操作の理解

## 学習の進め方

各セクションを順番に進めることを推奨します。各セクション末尾の「確認ポイント」を使って理解度をチェックしてください。

## 目次

### Phase 2: Nix言語の基礎
- [02. Nix言語の基礎](./02-nix-language.md)
  - データ型（文字列、数値、ブール、リスト、属性セット）
  - 関数（ラムダ、カリー化、属性セット引数）
  - let-in式、with式、inherit
  - `nix repl`での実践演習

### Phase 3: 核心概念の理解
- [03. 核心概念](./03-core-concepts.md)
  - 宣言的 vs 命令的
  - 純粋性と再現性
  - Nixストアとハッシュベースのパス
  - derivationの概念

### Phase 4: Flakes入門
- [04. Flakes](./04-flakes.md)
  - Flakesが解決する問題
  - `flake.nix`の構造（inputs/outputs）
  - `flake.lock`の役割
  - 主要コマンド（`nix develop`、`nix build`等）
  - 実践: 最初のflakeを作る

### Phase 5: Home Manager導入
- [05. Home Manager](./05-home-manager.md)
  - Home Managerが管理するもの
  - Flake経由でのセットアップ
  - `flake.nix`と`home.nix`の書き方
  - `programs.*` vs `home.file`の使い分け
  - 実践: 最初の設定適用

### Phase 6: モジュールシステム
- [06. モジュールシステム](./06-module-system.md)
  - モジュールの構造（imports、options、config）
  - ファイル分割の戦略
  - `mkOption`、`mkIf`、`mkMerge`
  - 実践: Git設定をモジュール化

### Phase 7: 既存dotfilesの移行
- [07. 既存dotfilesの移行](./07-migration.md)
  - 移行戦略（段階的アプローチ）
  - zsh設定の移行
  - Neovim設定の移行
  - Starship、lazygitの移行

### トラブルシューティング
- [08. トラブルシューティング](./08-troubleshooting.md)
  - よくあるエラーと対処法
  - デバッグ方法
  - アンチパターン

### リファレンス
- [09. 用語集](./09-glossary.md)
- [10. 学習リソース](./10-resources.md)
- [Appendix: コマンドリファレンス](./appendix/commands.md)
- [Appendix: 設定例集](./appendix/examples.md)

## イントロダクション

Nix学習の全体像と環境確認については以下を参照してください。

- [01. はじめに](./01-introduction.md)

## 進捗チェックリスト

### Phase 2: Nix言語の基礎
- [ ] `nix repl`で基本的なデータ型を扱える
- [ ] 関数定義と関数適用ができる
- [ ] `let-in`式を理解している
- [ ] 属性セットの操作ができる
- [ ] `inherit`の使い方を理解している

### Phase 3: 核心概念
- [ ] 宣言的アプローチの利点を説明できる
- [ ] 純粋性が再現性に与える影響を理解している
- [ ] Nixストアの役割を説明できる
- [ ] derivationの概念を理解している

### Phase 4: Flakes
- [ ] `flake.nix`の基本構造を理解している
- [ ] `inputs`と`outputs`の役割を説明できる
- [ ] `flake.lock`の目的を理解している
- [ ] `nix develop`でdevシェルに入れる
- [ ] シンプルなflakeを自作できる

### Phase 5: Home Manager
- [ ] Home Managerのセットアップができた
- [ ] `home.nix`で基本的な設定ができる
- [ ] `programs.*`オプションを使える
- [ ] `home-manager switch`で設定を適用できる
- [ ] 世代管理の仕組みを理解している

### Phase 6: モジュールシステム
- [ ] モジュールの構造を理解している
- [ ] 設定ファイルを複数に分割できる
- [ ] `mkIf`で条件分岐ができる
- [ ] `imports`で他のモジュールを読み込める

### Phase 7: 移行
- [ ] Git設定をHome Managerで管理している
- [ ] zsh設定をHome Managerで管理している
- [ ] Neovim設定の配置方法を決定している
- [ ] 既存dotfilesとの共存方法を理解している

## 現在のステータス

**Phase 1完了**: Nixの基本コマンド習得済み

次のステップ: [02. Nix言語の基礎](./02-nix-language.md)から開始してください。

## 学習のヒント

1. **段階的に進める**: 一度にすべてを理解しようとせず、1つずつ確実に
2. **実際に試す**: `nix repl`やflakeを使って手を動かす
3. **エラーを恐れない**: エラーメッセージは学習の機会
4. **公式ドキュメントを参照**: このガイドは入門、詳細は公式ドキュメントへ
5. **コミュニティを活用**: NixOS Discourse、GitHub Discussionsなど

## フィードバック

このガイドに関する改善提案や質問があれば、dotfilesリポジトリのIssueで報告してください。
