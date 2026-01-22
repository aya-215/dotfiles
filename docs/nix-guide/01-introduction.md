# はじめに

## このガイドについて

このガイドは、Nixの基本コマンドを習得した方が、Flakesを使ってHome Managerでdotfilesを宣言的に管理できるようになるための学習パスです。

## 学習の目標

このガイドを完了すると、以下ができるようになります。

- Nix言語の基本を理解し、設定ファイルを読み書きできる
- Flakesを使ってプロジェクトの依存関係を管理できる
- Home Managerでdotfilesを宣言的に管理できる
- 既存のdotfilesをNixに段階的に移行できる

## 前提条件

### 必須

- **Nixインストール済み**
  ```bash
  nix --version
  # nix (Nix) 2.x.x が表示されればOK
  ```

- **基本的なシェル操作の理解**
  - ファイル操作（`cd`, `ls`, `mkdir`）
  - テキストエディタの使用（vim、nanoなど）
  - Git の基本操作

### 推奨

- Phase 1（基本コマンド習得）完了
- Gitリポジトリの基本的な理解

## 環境確認

以下のコマンドで環境を確認してください。

### 1. Nixのバージョン確認

```bash
nix --version
```

**期待される出力:**
```
nix (Nix) 2.18.1
```

バージョンが2.4以上であることを確認してください。

### 2. Flakesの有効化確認

```bash
nix flake --version
```

**エラーが出る場合:**

Flakesが有効化されていません。以下で有効化してください。

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

再度確認:
```bash
nix flake --version
```

### 3. ホームディレクトリの確認

```bash
echo $HOME
```

**期待される出力（WSL環境の例）:**
```
/home/yourusername
```

### 4. システムアーキテクチャの確認

```bash
nix eval --expr 'builtins.currentSystem'
```

**期待される出力（WSL環境）:**
```
"x86_64-linux"
```

このシステム識別子は、後で`flake.nix`で使用します。

### 5. Git設定の確認

```bash
git config --get user.name
git config --get user.email
```

Gitがセットアップされていることを確認してください。未設定の場合:

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## 学習環境のセットアップ

### 練習用ディレクトリの作成

```bash
mkdir -p ~/nix-practice
cd ~/nix-practice
```

このディレクトリで、各セクションの演習を行います。

### dotfilesリポジトリの準備（オプション）

既存のdotfilesリポジトリがある場合:

```bash
cd ~/.dotfiles  # または自分のdotfilesディレクトリ

# Nixファイル用のディレクトリを作成
mkdir -p nix

# バックアップブランチを作成（念のため）
git checkout -b pre-nix-backup
git checkout main
```

## 学習の進め方

### 1. 順番に進める

各セクションは前のセクションの知識を前提としています。順番に進めることを推奨します。

1. Nix言語の基礎（Phase 2）
2. 核心概念（Phase 3）
3. Flakes（Phase 4）
4. Home Manager（Phase 5）
5. モジュールシステム（Phase 6）
6. 既存dotfilesの移行（Phase 7）

### 2. 手を動かす

各セクションの「実践演習」を必ず実施してください。読むだけでは身につきません。

### 3. エラーを恐れない

- エラーメッセージは学習の機会
- 失敗しても環境は壊れません（Nixは安全）
- 世代管理で簡単にロールバック可能

### 4. 確認ポイントをチェック

各セクション末尾の「確認ポイント」で理解度を確認してください。

### 5. 必要に応じて戻る

理解が曖昧な部分があれば、前のセクションに戻って復習してください。

## このガイドの構成

### Phase 2: Nix言語の基礎

Nix言語の基本的な構文とデータ型を学びます。`nix repl`を使った実践演習を通して、関数や属性セットの扱い方を身につけます。

→ [02. Nix言語の基礎](./02-nix-language.md)

### Phase 3: 核心概念

Nixの哲学（宣言的、純粋性、再現性）を理解します。Nixストアやderivationなどの核心概念を学びます。

→ [03. 核心概念](./03-core-concepts.md)

### Phase 4: Flakes

Nixプロジェクトの依存関係を管理する新しい方法であるFlakesを学びます。`flake.nix`の書き方と主要なコマンドを習得します。

→ [04. Flakes](./04-flakes.md)

### Phase 5: Home Manager

Home Managerをセットアップし、dotfilesを宣言的に管理する方法を学びます。

→ [05. Home Manager](./05-home-manager.md)

### Phase 6: モジュールシステム

設定をモジュールに分割して整理する方法を学びます。

→ [06. モジュールシステム](./06-module-system.md)

### Phase 7: 既存dotfilesの移行

既存のdotfilesをHome Managerに段階的に移行する戦略を学びます。

→ [07. 既存dotfilesの移行](./07-migration.md)

## 学習時間の目安

- **Phase 2 (Nix言語)**: 2-3時間
- **Phase 3 (核心概念)**: 1-2時間
- **Phase 4 (Flakes)**: 2-3時間
- **Phase 5 (Home Manager)**: 2-3時間
- **Phase 6 (モジュールシステム)**: 2-3時間
- **Phase 7 (移行)**: 実際のdotfilesの規模による

**合計**: 10-15時間程度

一度にすべてを学ぶ必要はありません。1日1セクションずつ進めるのも良いでしょう。

## トラブル時の対処

### 問題が発生したら

1. **エラーメッセージを読む**: Nixのエラーメッセージは比較的わかりやすい
2. **`--show-trace`を使う**: より詳細なエラー情報を表示
   ```bash
   nix build --show-trace
   ```
3. **トラブルシューティングセクションを確認**: [08. トラブルシューティング](./08-troubleshooting.md)
4. **公式ドキュメントを参照**: [10. 学習リソース](./10-resources.md)

### 環境をリセットしたい場合

```bash
# 練習用ディレクトリを削除
rm -rf ~/nix-practice

# 再作成
mkdir -p ~/nix-practice
cd ~/nix-practice
```

## 次のステップ

環境確認が完了したら、Nix言語の基礎から学習を開始しましょう。

→ [02. Nix言語の基礎](./02-nix-language.md)

## 参考資料

このガイドは入門用です。詳細は以下の公式ドキュメントを参照してください。

- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Zero to Nix](https://zero-to-nix.com/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)

→ [10. 学習リソース](./10-resources.md)で詳しく紹介しています。
