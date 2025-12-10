# WSL バックアップスクリプト

## 概要

WSL内の `/home/aya` 配下のファイルを Windows の `D:\WSL\backup\` に増分バックアップするスクリプトです。

## 特徴

- **増分バックアップ**: 初回は全ファイルをコピー、2回目以降は変更されたファイルのみをコピー
- **高速**: rsyncによる効率的な同期
- **除外設定**: キャッシュや一時ファイルを除外してバックアップサイズを削減
- **ログ記録**: バックアップの詳細ログを自動保存
- **カラー出力**: 視認性の高いコンソール出力

## ファイル構成

```
scripts/backup/
├── backup-wsl-to-windows.sh  # メインのバックアップスクリプト
├── backup-exclude.txt         # 除外ファイル・ディレクトリの定義
└── README.md                  # このファイル
```

## 使用方法

### 基本的な使い方

```bash
# スクリプトディレクトリに移動
cd ~/.dotfiles/scripts/backup

# バックアップ実行
./backup-wsl-to-windows.sh
```

### エイリアスを設定して簡単に実行

`~/.bashrc` または `~/.zshrc` に以下を追加：

```bash
alias backup-wsl='~/.dotfiles/scripts/backup/backup-wsl-to-windows.sh'
```

設定後、どこからでも以下のコマンドで実行可能：

```bash
backup-wsl
```

## バックアップ先

- Windows側: `D:\WSL\backup\home\aya\`
- WSL側からのパス: `/mnt/d/WSL/backup/home/aya/`

## 除外されるファイル

以下のファイル・ディレクトリはバックアップから除外されます（`backup-exclude.txt` で定義）：

- **キャッシュ**: `.cache/`, `.npm/`, `.yarn/`, `.cargo/registry/` など
- **一時ファイル**: `*.tmp`, `*.log`, `*.swp`, `.bash_history` など
- **ブラウザキャッシュ**: `.mozilla/firefox/*/cache*/`, `.config/google-chrome/*/Cache/` など
- **VS Code Server キャッシュ**: `.vscode-server/data/logs/` など

### カスタマイズ

`backup-exclude.txt` を編集して除外設定を変更できます：

```bash
# node_modules も除外したい場合
echo "node_modules/" >> ~/.dotfiles/scripts/backup/backup-exclude.txt
```

## ログファイル

- 保存場所: `~/.backup-logs/`
- ファイル名形式: `backup-YYYYMMDD-HHMMSS.log`
- 古いログの自動削除: 30日以上前のログは自動削除されます

## 定期実行の設定（推奨）

### 方法1: PowerShellスクリプトで自動設定（推奨・最も簡単）

対話的にタスクスケジューラを設定できる高機能スクリプトを用意しています：

```powershell
# Windows PowerShell（管理者として実行）
cd D:\
wsl.exe -- cat /home/aya/.dotfiles/scripts/backup/Setup-BackupScheduler.ps1 > Setup-BackupScheduler.ps1
.\Setup-BackupScheduler.ps1
```

**機能:**
- 対話的な設定（実行時刻、頻度、通知など）
- 失敗時のトースト通知（BurntToast使用）
- 複数スケジュール対応（毎日、毎週、カスタム）
- 即座にテスト実行可能

### 方法2: Windowsタスクスケジューラで手動設定

WSLのcronは常時起動していない場合があるため、Windowsタスクスケジューラの方が確実です：

**GUI設定手順:**
1. タスクスケジューラを開く (`Win + R` → `taskschd.msc`)
2. 「基本タスクの作成」を選択
3. トリガー: 任意の時刻・頻度を設定
4. 操作: プログラムの開始
   - プログラム: `wsl.exe`
   - 引数: `-d Ubuntu-22.04 -u aya -- /home/aya/.dotfiles/scripts/backup/backup-wsl-to-windows.sh`

**PowerShellコマンドで一発設定:**
```powershell
$Action = New-ScheduledTaskAction -Program "wsl.exe" -Argument '-d Ubuntu-22.04 -u aya -- /home/aya/.dotfiles/scripts/backup/backup-wsl-to-windows.sh'
$Trigger = New-ScheduledTaskTrigger -Daily -At 2:00am
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "WSL-Daily-Backup" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Description "WSL /home/aya の定期バックアップ"
```

### 方法3: cronで自動実行（WSL常時起動の場合のみ）

**注意**: WSLが常時起動していない環境では動作しません。

```bash
# crontabを編集
crontab -e

# 以下を追加（毎日午前2時にバックアップ）
0 2 * * * /home/aya/.dotfiles/scripts/backup/backup-wsl-to-windows.sh >> ~/.backup-logs/cron.log 2>&1
```

### タスク管理コマンド

```powershell
# タスクの状態確認
Get-ScheduledTask -TaskName "WSL-Daily-Backup" | Get-ScheduledTaskInfo

# 今すぐ実行
Start-ScheduledTask -TaskName "WSL-Daily-Backup"

# タスクの削除
Unregister-ScheduledTask -TaskName "WSL-Daily-Backup" -Confirm:$false

# 実行履歴の確認
Get-ScheduledTask -TaskName "WSL-Daily-Backup" | Get-ScheduledTaskInfo | Select-Object LastRunTime, LastTaskResult, NextRunTime
```

## トラブルシューティング

### D:ドライブにアクセスできない

```bash
# マウントされているか確認
ls /mnt/d

# マウントされていない場合、再マウント
sudo mkdir -p /mnt/d
sudo mount -t drvfs D: /mnt/d
```

### 権限エラーが出る

```bash
# スクリプトに実行権限を付与
chmod +x ~/.dotfiles/scripts/backup/backup-wsl-to-windows.sh
```

### バックアップが遅い

- `backup-exclude.txt` で除外するファイルを増やす
- 特に `node_modules/`, `.venv/`, `.docker/` などの大きなディレクトリを除外すると高速化します

## 注意事項

- **削除の同期**: バックアップスクリプトは `--delete` オプションを使用しているため、ソースから削除されたファイルはバックアップ先からも削除されます
- **初回実行**: 初回は全ファイルをコピーするため時間がかかります
- **ディスク容量**: D:ドライブに十分な空き容量があることを確認してください

## その他のバックアップ方法

### WSL全体のバックアップ（Windows PowerShell から実行）

```powershell
# エクスポート（完全バックアップ）
wsl --export Ubuntu D:\WSL\backup\ubuntu-backup.tar

# インポート（復元）
wsl --import Ubuntu D:\WSL\Ubuntu D:\WSL\backup\ubuntu-backup.tar
```

この方法はシステム全体のバックアップに適しています。
