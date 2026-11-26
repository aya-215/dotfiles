---
name: git-index-lock
description: git コマンドが「fatal: Unable to create '.../.git/index.lock': File exists.」「Another git process seems to be running in this repository」で失敗したときに使う。主に /mnt/ 配下（Windows 側のドライブ）のリポジトリで、エディタの git 統合がロックを断続的に掴むために起きる。ロックを消してリトライする手順。
---

# git-index-lock

## なぜ起きるか

エディタ（Neovim 等）の git 統合がバックグラウンドで `git status` 等を頻繁に実行し、`index.lock` を断続的に掴むことが主因。
競合相手は読み取り専用の `git status` であり書き換えるインデックスが無いため、ロックを消すリスクは原則低い。

## 手順

1. **削除して即リトライ**: `rm -f /path/to/.git/index.lock && git ...`
2. **単発で通らなければリトライループ**: ロックの再生成が頻繁な場合、「削除→実行→失敗なら `sleep 1`」を最大10回ループする

```bash
for i in $(seq 1 10); do
  rm -f /path/to/.git/index.lock
  git -C /path/to commit -m "..." && break
  sleep 1
done
```

## 注意

- 複合コマンドでは、本処理が成功した後に走る確認用の git 呼び出し（`git status` 等）もロックに当たる。各 git 呼び出しの前に `rm -f .git/index.lock` を挟む
- worktree では `.git` がファイルなので、ロックは `<本体>/.git/worktrees/<名前>/index.lock` にある。`git rev-parse --git-dir` で場所を確かめてから消す
