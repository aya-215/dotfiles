# GitBucketのデモをしよう

Gitはコードの変更履歴を管理するツール。GitBucketはそれをチームで共有するための場所（リモート）。
今日は実際にコマンドを打ちながら覚えよう！

**今日やること：**
- 新しいプロジェクトをGitBucketに作る
- 既存プロジェクトに機能追加してPRを出す

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

## Part 2: 既存プロジェクトに機能追加するとき

シナリオ：「先輩から『このリポジトリに優先度機能を追加してや！』と頼まれた」

### Step 1: clone（プロジェクトをもらってくる）

```bash
git clone http://[GitBucketのURL]/senpai/todo-app.git
cd todo-app
```

`ls` でファイルが入っているか確認しよう。

### Step 2: branch（作業場所を分ける）

mainには直接触らず、自分の作業用ブランチを作る。

```bash
git checkout -b feature/add-priority
```

今どのブランチにいるか確認：
```bash
git branch
# * feature/add-priority  ← これが現在地
#   main
```

> **つまずきポイント**
> branchを切り忘れてmainで作業してしまった場合：
> ```bash
> git checkout -b feature/add-priority  # 今の変更ごと新ブランチに移れる
> ```

### Step 3: ファイルを編集する

エディタでファイルを変更する（今回はREADMEに追記で簡易デモ）。

```bash
echo "- [ ] 優先度: 高" >> README.md
```

### Step 4: commit（変更を保存する）

まず何が変わったか確認：
```bash
git status
```

変更をステージに追加してコミット：
```bash
git add README.md
git commit -m "feat: 優先度機能を追加"
```

> **つまずきポイント**
> - `git add` し忘れると `nothing to commit` になる → `git status` で確認
> - `git add .` で変更したファイルを全部まとめて追加できる

### Step 5: push（リモートに共有する）

```bash
git push origin feature/add-priority
```

> **つまずきポイント**
> 認証エラーが出たら → GitBucketのユーザー名・パスワードを確認。
> `git push` 時に聞かれることもある。

### Step 6: PR（プルリクエスト）を立てる（ブラウザ）

1. GitBucketでリポジトリを開く
2. `Pull Requests` タブ → `New pull request`
3. base: `main` ← compare: `feature/add-priority` を確認
4. タイトルと説明を書く（例：「優先度機能を追加しました」）
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
