# GitBucketのデモをしよう

Gitはコードの変更履歴を管理するツール。GitBucketはそれをチームで共有するための場所（リモート）。
今日は実際にコマンドを打ちながら覚えよう！

**今日やること：**
- 新しいプロジェクトをGitBucketに作る
- 既存プロジェクトを編集してPRを出す

---

## Part 1: 新しいプロジェクトを作るとき

シナリオ：「新しいTODOアプリを一から作ることになった！」

### Step 1: GitBucketでリポジトリを作成（ブラウザ）

1. GitBucketにログイン
2. 右上の `+` → `New repository`
3. Repository name に `todo-app` と入力
4. `Create repository` をクリック

### Step 2: ローカルで初期化して接続

```bash
mkdir todo-app
cd todo-app
git init
git remote add origin http://[GitBucketのURL]/[ユーザー名]/todo-app.git
```

### Step 3: 最初のコミットとpush

```bash
echo "# TODO App" > README.md
git add README.md
git commit -m "first commit"
git push -u origin main
```

ブラウザでGitBucketを確認するとファイルが上がっているはず！

> **つまずきポイント**
> `error: remote origin already exists` → すでにremoteが登録済み。以下で上書きできる：
> ```bash
> git remote set-url origin http://[GitBucketのURL]/[ユーザー名]/todo-app.git
> ```

---

## Part 2: 既存プロジェクトを編集してPRを出すとき

シナリオ：「`kensyu-demo` リポジトリに好きな変更を加えてPRを出してみよう！」

### Step 1: clone（プロジェクトをもらってくる）

```bash
git clone http://192.168.208.80:8080/gitbucket/git/mori.a/kensyu-demo.git
cd kensyu-demo
```

> URLはGitBucketのリポジトリページ右上のコピーボタンでも取得できる

`ls` でファイルが入っているか確認しよう。

### Step 2: branch（作業場所を分ける）

mainには直接触らず、自分の作業用ブランチを作る。
ブランチ名は自分の名前や作業内容にしよう。

```bash
git checkout -b [自分の名前など]
# 例: git checkout -b tanaka
```

今どのブランチにいるか確認：
```bash
git branch
# * tanaka  ← これが現在地
#   main
```

> **つまずきポイント**
> branchを切り忘れてmainで作業してしまった場合：
> ```bash
> git checkout -b [ブランチ名]  # 今の変更ごと新ブランチに移れる
> ```

### Step 3: ファイルを編集する

好きに変更してOK！例えば：

**README.mdに追記する**
```bash
echo "テストメッセージ！" >> README.md
```

**新しいファイルを追加する**
```bash
echo "はじめてのgit" > hello.txt
```

### Step 4: commit（変更を保存する）

まず何が変わったか確認：
```bash
git status
```

変更をステージに追加してコミット：
```bash
git add .
git commit -m "好きなメッセージ"
# 例: git commit -m "READMEにメッセージを追加"
```

> **つまずきポイント**
> - `git add` し忘れると `nothing to commit` になる → `git status` で確認
> - `git add .` で変更したファイルを全部まとめて追加できる

### Step 5: push（リモートに共有する）

```bash
git push origin [自分のブランチ名]
# 例: git push origin tanaka
```

> **つまずきポイント**
> 認証エラーが出たら → GitBucketのユーザー名・パスワードを確認。
> `git push` 時に聞かれることもある。

### Step 6: PR（プルリクエスト）を立てる（ブラウザ）

1. `http://192.168.208.80:8080/gitbucket/mori.a/kensyu-demo` を開く
2. `Pull Requests` タブ → `New pull request`
3. base: `main` ← compare: `自分のブランチ名` を確認
4. タイトルと説明を書く（例：「テストメッセージを追加しました」）
5. `Create pull request` をクリック

これでレビューを依頼できる！レビュアーが確認してmainにマージしてくれる。

---

## まとめ：よく使うコマンド早見表

| コマンド | 何をする？ |
|---|---|
| `git clone [URL]` | リモートのプロジェクトをローカルにコピー |
| `git checkout -b [ブランチ名]` | 新しいブランチを作って移動 |
| `git status` | 現在の変更状況を確認 |
| `git add [ファイル]` | 変更をステージに追加 |
| `git commit -m "メッセージ"` | 変更を保存 |
| `git push origin [ブランチ名]` | リモートに送る |
