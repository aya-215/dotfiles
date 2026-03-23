# Phase 1: 不要ファイル削除

## 目的

git管理外のバックアップファイル・不要ファイルを削除してリポジトリを整理する。

## 対象ファイル

### 削除対象

| パス | 種別 | 理由 |
|---|---|---|
| `.config/nvim.backup.20251205_165130/` | ディレクトリ（292KB, 12ファイル） | 旧Neovim設定バックアップ。Home Manager管理に統一済みで不要 |
| `.config/starship/original-blue.toml.backup` | ファイル | 旧テーマバックアップ。不要 |

> **注意:** どちらも `.gitignore` でgit管理外になっているため、削除してもgit履歴に影響なし。

## 作業手順

```bash
# 1. 削除前に内容確認
ls -la ~/.dotfiles/.config/nvim.backup.20251205_165130/
ls -la ~/.dotfiles/.config/starship/original-blue.toml.backup

# 2. 削除実施
rm -rf ~/.dotfiles/.config/nvim.backup.20251205_165130/
rm -f ~/.dotfiles/.config/starship/original-blue.toml.backup

# 3. git status で影響なしを確認
git -C ~/.dotfiles status
```

## 検証

- `git status` に変化がないこと（git管理外ファイルの削除のみ）
- Neovimが正常に起動できること（バックアップではなく本番設定が使われていることを確認）

## 完了後

- コミット不要（git管理外ファイルの削除のため）
- Phase 2 に進む
