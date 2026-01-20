---
name: sync-dotfiles
description: dotfilesをgitと同期
invocation:
  slash_command: sync
  requires_user_invocation: true
---

# Sync Dotfiles Skill

dotfilesリポジトリの同期を行います。

## 処理フロー

1. `git status` で状態確認
2. 未コミットの変更があれば報告
3. `git fetch origin` でリモート取得
4. `git pull --rebase` でマージ
5. 結果を報告

## 使用方法

```
/sync
```
