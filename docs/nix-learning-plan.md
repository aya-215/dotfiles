# Nix学習計画

## 📌 Phase 1完了記録

**完了日**: 2024年頃
**達成内容**:
- ✅ Nixパッケージマネージャーのインストール完了
- ✅ 基本コマンドの理解（`nix-shell`、パッケージ管理）
- ✅ チャネルの理解

## 次のステップ: Flakesベース学習

**Phase 1を完了した方へ**: このドキュメントの内容は古い学習パスです。

**新しい包括的なガイドを作成しました。以下から学習を続けてください。**

→ **[Nix学習ガイド（Flakesベース）](./nix-guide/README.md)**

### 新ガイドの特徴

- **Flakesベース**: 最初からFlakesを使った現代的なアプローチ
- **詳細な解説**: 各概念を段階的に丁寧に説明
- **実践演習**: 手を動かして学べる演習問題
- **トラブルシューティング**: よくあるエラーと対処法
- **設定例集**: すぐに使える実例

### 推奨学習パス

1. [はじめに](./nix-guide/01-introduction.md) - 環境確認
2. [Nix言語の基礎](./nix-guide/02-nix-language.md) - 言語の基本
3. [核心概念](./nix-guide/03-core-concepts.md) - Nixの哲学
4. [Flakes](./nix-guide/04-flakes.md) - Flakesの使い方
5. [Home Manager](./nix-guide/05-home-manager.md) - dotfiles管理
6. [モジュールシステム](./nix-guide/06-module-system.md) - 設定の整理
7. [既存dotfilesの移行](./nix-guide/07-migration.md) - 実践的な移行戦略

---

## 以下は参考用（旧学習パス）

<details>
<summary>Phase 1の内容（完了済み・参考用）</summary>

### Phase 1: Nixの基礎理解

#### タスク
1. **Nixのインストール**
   ```bash
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```

2. **基本コマンド**
   ```bash
   nix-shell -p cowsay lolcat
   nix-env -qaP | grep ripgrep
   nix-env -iA nixpkgs.hello
   ```

3. **チャネルの理解**
   ```bash
   nix-channel --list
   nix-channel --update
   ```

</details>

<details>
<summary>Phase 2-5の内容（参考用・Flakesガイドを推奨）</summary>

### Phase 2-5の概要

これらのフェーズは、旧来のチャネルベースのアプローチです。

**現在は [Nix学習ガイド](./nix-guide/README.md) のFlakesベースアプローチを推奨します。**

- Phase 2: Home Managerの導入（チャネル経由）
- Phase 3: 簡単なdotfilesの移行
- Phase 4: 複雑な設定の移行
- Phase 5: Flakesへの移行

詳細な手順は新ガイドで、より体系的に学習できます。

</details>

---

## 学習リソース

より詳しい学習リソースは新ガイドをご覧ください。

→ [学習リソース](./nix-guide/10-resources.md)
