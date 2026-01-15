# Claude Code to nb Sync

Claude Codeの会話を自動的にnbノートブックに保存するツールです。

## 概要

このツールは以下を実行します：

1. Claude Codeのセッションファイル（`~/.claude/projects/*/` 以下のJSONL）を監視
2. 会話内容（userとassistantメッセージ）をMarkdown形式に変換
3. `~/.nb/claude/` ディレクトリに日付別ファイルとして保存

## 特徴

- **自動同期**: cronで5分ごとに実行され、新しい会話を自動保存
- **増分更新**: 状態ファイルで最終同期位置を管理し、新しいメッセージのみを処理
- **ノイズ除外**: システムメッセージやツール呼び出しを除外し、会話内容のみを保存
- **プロジェクト別整理**: プロジェクトごとにセクションを分けて見やすく整理
- **nb連携**: nbコマンドで簡単にアクセス・編集可能

## 必要な環境

- WSL2 (Ubuntu)
- Python 3.x
- [nb](https://github.com/xwmx/nb) - ノートブック管理ツール
- cron

## インストール

### 1. nbのインストール（未インストールの場合）

```bash
# Homebrewを使う場合
brew install nb

# または直接インストール
git clone https://github.com/xwmx/nb.git
cd nb
sudo make install
```

### 2. セットアップスクリプトの実行

```bash
cd ~/.dotfiles/scripts/claude-sync
./install.sh
```

セットアップスクリプトは以下を実行します：
- nbノートブック `claude` の作成
- crontabの設定
- `/etc/wsl.conf` の設定（オプション）
- テスト実行

## 使い方

### 同期されたファイルを確認

```bash
# ファイル一覧
nb claude:list

# または
ls ~/.nb/claude/
```

### 特定の日の会話を閲覧

```bash
# nbで開く
nb claude:show 2026-01-14.md

# または直接開く
cat ~/.nb/claude/2026-01-14.md
```

### 会話を編集

```bash
nb claude:edit 2026-01-14.md
```

### 手動で同期を実行

```bash
~/.dotfiles/scripts/claude-sync/claude-nb-sync.py
```

### ログを確認

```bash
tail -f /tmp/claude-nb-sync.log
```

## ファイル構成

```
~/.dotfiles/scripts/claude-sync/
├── claude-nb-sync.py      # メイン同期スクリプト
├── install.sh             # セットアップスクリプト
└── README.md              # このファイル

~/.claude/
└── nb-sync-state.json     # 同期状態ファイル

~/.nb/claude/              # 同期先ノートブック
└── YYYY-MM-DD.md          # 日付別の会話ファイル
```

## 保存形式

会話は以下のMarkdown形式で保存されます：

```markdown
# Claude Code Conversations - 2026年1月14日

## dotfiles
### 09:30

**User:**
ユーザーの質問

**Claude:**
Claudeの応答

---

## ebase-portal-chat
### 10:15

**User:**
別のプロジェクトの会話

**Claude:**
応答

---
```

## 除外されるメッセージ

以下のメッセージは自動的に除外されます：

- `<system-reminder>` を含むメッセージ
- `<local-command>` を含むメッセージ
- `<command-name>` を含むメッセージ
- `<task-notification>` を含むメッセージ
- ツール呼び出しのみのメッセージ
- "Warmup" のみのメッセージ

## cron設定の詳細

デフォルトでは5分ごとに実行されます：

```bash
*/5 * * * * ~/.dotfiles/scripts/claude-sync/claude-nb-sync.py >> /tmp/claude-nb-sync.log 2>&1
```

実行間隔を変更する場合：

```bash
crontab -e
# 例：10分ごとに変更
*/10 * * * * ~/.dotfiles/scripts/claude-sync/claude-nb-sync.py >> /tmp/claude-nb-sync.log 2>&1
```

## WSL起動時のcron自動起動

`/etc/wsl.conf` に以下を追加すると、WSL起動時に自動でcronが起動します：

```ini
[boot]
command = service cron start
```

設定後、WSLを再起動してください：

```powershell
# Windowsから実行
wsl.exe --shutdown
```

## トラブルシューティング

### cronが動作しない

```bash
# cronサービスの確認
sudo service cron status

# 起動していない場合
sudo service cron start

# crontabの確認
crontab -l
```

### 同期されない

```bash
# 手動実行でエラーを確認
python3 ~/.dotfiles/scripts/claude-sync/claude-nb-sync.py

# ログファイルを確認
tail -n 50 /tmp/claude-nb-sync.log

# 状態ファイルをリセット（最初から同期したい場合）
rm ~/.claude/nb-sync-state.json
```

### Pythonのエラー

```bash
# Python3のバージョン確認
python3 --version

# 必要なら最新版にアップデート
sudo apt update
sudo apt install python3
```

## 参考

このツールは以下の記事を参考に、WSL + nb環境に適応させています：

- [Claude Codeとの会話をObsidianに自動記録する仕組み](https://zenn.dev/pepabo/articles/ffb79b5279f6ee)

## ライセンス

MIT License
