# dotfiles

個人用dotfiles管理リポジトリ

## 構成

```
dotfiles/
├── .config/
│   ├── wezterm/    # WezTerm設定
│   └── nvim/       # Neovim設定
├── .gitignore
└── README.md
```

## セットアップ手順

### Windows

**前提条件**: 開発者モードを有効化（シンボリックリンクに管理者権限不要にするため）

1. リポジトリをクローン
```powershell
cd D:\git
git clone git@github.com:aya-215/dotfiles.git
```

2. シンボリックリンクを作成
```powershell
# WezTerm
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.config\wezterm" -Target "D:\git\dotfiles\.config\wezterm"

# Neovim
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.config\nvim" -Target "D:\git\dotfiles\.config\nvim"
```

### macOS / Linux

1. リポジトリをクローン
```bash
cd ~
git clone git@github.com:aya-215/dotfiles.git
```

2. シンボリックリンクを作成
```bash
# WezTerm
ln -s ~/dotfiles/.config/wezterm ~/.config/wezterm

# Neovim
ln -s ~/dotfiles/.config/nvim ~/.config/nvim
```

## 日常の使い方

### 設定を編集

どちらの場所で編集してもOK:
```bash
# パターン1: 実環境側で編集
nvim ~/.config/nvim/init.lua

# パターン2: dotfiles側で編集
cd ~/dotfiles
nvim .config/nvim/init.lua
```

### 変更をコミット

```bash
cd ~/dotfiles  # Windows: D:\git\dotfiles
git add .
git commit -m "設定を更新"
git push
```

## 注意事項

- `.claude/settings.local.json`は`.gitignore`で除外しています
- シンボリックリンクは双方向で動作します（どちらから編集しても同じファイル）
- シンボリックリンク削除時は`Remove-Item`（Windows）または`rm`（Mac/Linux）で安全に削除できます
