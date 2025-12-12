# Starship プロンプト設定ガイド

## ファイル構成

```
~/.config/starship.toml          # 実際に読み込まれる設定（シンボリックリンク）
~/.dotfiles/.config/starship.toml # 本体
```

## 現在のプロンプト構成

```
 ~/src/ /user/repo   main !   10:55
❯
```

| セクション | 背景色 | 文字色 |
|-----------|--------|--------|
| ディレクトリ | `#3d5a8a` | `#e8ecf2` |
| Git | `#2f4570` | `#c0daf5` |
| 時刻 | `#1d2230` | `#c0daf5` |

## 編集方法

### 色の変更

sedを使用して編集する（Editツールではアイコンが消える場合がある）：

```bash
# 背景色の変更例（ディレクトリ）
sed -i 's/#3d5a8a/#新しい色/g' ~/.dotfiles/.config/starship.toml

# 文字色の変更例（Git）
sed -i 's/fg:#c0daf5 bg:#2f4570/fg:#新しい色 bg:#2f4570/g' ~/.dotfiles/.config/starship.toml
```

### アイコンの変更

Nerd Fontアイコンを挿入する場合はechoを使用：

```bash
# Unicodeエスケープで挿入
echo -e '\uf09b'  # GitHubアイコン

# ファイルに書き込む例
head -25 ~/.dotfiles/.config/starship.toml > /tmp/starship_part1.toml
echo -e '"src/github.com" = "\uf09b "' >> /tmp/starship_part1.toml
tail -n +27 ~/.dotfiles/.config/starship.toml >> /tmp/starship_part1.toml
mv /tmp/starship_part1.toml ~/.dotfiles/.config/starship.toml
```

### よく使うNerd Fontアイコン

| アイコン | Unicode | 用途 |
|---------|---------|------|
|  | `\uf09b` | GitHub |
|  | `\ue702` | Git |
|  | `\ue725` | ブランチ |
|  | `\uf85a` | メモリ |
|  | `\uf017` | 時計 |
|  | `\uf07c` | フォルダ |

アイコン検索: https://www.nerdfonts.com/cheat-sheet

## 設定項目

### format（プロンプト構成）

```toml
format = """
[](fg:#3d5a8a)\           # 左端の丸み
$directory\                # ディレクトリモジュール
[](fg:#3d5a8a bg:#2f4570)\ # 区切り（前景=前の背景、背景=次の背景）
$git_branch\
$git_status\
[](fg:#2f4570 bg:#1d2230)\
$time\
[ ](fg:#1d2230)\          # 右端の丸み
\n$character"""            # 改行 + プロンプト記号
```

### directory（ディレクトリ）

```toml
[directory]
truncation_length = 0       # 0=絶対パス表示
truncate_to_repo = false    # Gitルートで切らない
home_symbol = "~"           # ホームの表示
style = "fg:#e8ecf2 bg:#3d5a8a"
format = "[ $path ]($style)"

[directory.substitutions]
"src/github.com" = " "     # パス置換
```

### character（プロンプト記号）

```toml
[character]
success_symbol = "[❯](bold #3d5a8a)"  # 成功時の色
error_symbol = "[❯](bold red)"         # エラー時の色
```

[time]
disabled = false
time_format = "%T"          # HH:MM:SS形式
style = "bg:#1d2230"
format = '[[  $time ](fg:#c0daf5 bg:#1d2230)]($style)'
```

## 設定反映

```bash
# 新しいターミナルを開く、または
source ~/.zshrc
```

## トラブルシューティング

### 丸みが四角く見える

- Nerd Fontが正しくインストールされているか確認
- WeztTermのフォント設定を確認
- 編集ツールではなくsedを使用する

### アイコンが表示されない

- `echo -e '\uf09b'` でアイコンが表示されるか確認
- 設定ファイルにUnicodeエスケープで書き込む

### 色が反映されない

- 色コードは `#RRGGBB` 形式で指定
- 変更後は新しいターミナルを開く
