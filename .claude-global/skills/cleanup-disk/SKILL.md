---
name: cleanup-disk
description: Cドライブの定期クリーンアップと一度きり削除を実行する
allowed-tools: Bash(powershell.exe:*), Bash(ls:*), Bash(df:*), AskUserQuestion
version: 1.0.0
---

# Cドライブ ディスククリーンアップ

Windows Cドライブのキャッシュ・ログ・一時ファイルを安全に削除するスキル。

## スクリプト

| スクリプト | 用途 | パス |
|-----------|------|------|
| `cleanup-disk.ps1` | 定期削除（週1回推奨） | `C:\Users\368\scripts\cleanup-disk.ps1` |
| `cleanup-once.ps1` | 一度きりの旧バージョン削除 | `C:\Users\368\scripts\cleanup-once.ps1` |

## 引数

- `$1`: 操作（省略可）
  - `periodic` — 定期削除を実行
  - `once` — 一度きり削除を実行
  - `status` — 現在のディスク使用状況を表示
  - 省略時 — AskUserQuestion で選択

## 実行フロー

### 1. 操作の決定

引数が指定されていない場合、AskUserQuestion で操作を選択させる:
- 定期クリーンアップ（キャッシュ・ログ・Temp）
- 一度きり削除（旧バージョン・残骸）
- ディスク使用状況の確認のみ

### 2. DryRun の実行

**必ず DryRun を先に実行**して結果をユーザーに表示する。

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\cleanup-disk.ps1' -DryRun
```

または:

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\cleanup-once.ps1' -DryRun
```

### 3. ユーザー確認

DryRun の結果を表示し、以下を AskUserQuestion で確認:
- 実行してよいか
- Chrome/Office/Neovim などロック要因のアプリを閉じたか

### 4. 本実行

承認を得たら `-DryRun` なしで実行:

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\cleanup-disk.ps1'
```

### 5. 結果報告

実行後に以下を表示:
- 各項目の削減量
- 合計削減量
- 実行前後の空き容量

## status 操作

ディスクの現状を確認するだけの場合:

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "
\$drive = Get-PSDrive C
\$totalGB = [math]::Round((\$drive.Used + \$drive.Free) / 1GB, 2)
\$usedGB = [math]::Round(\$drive.Used / 1GB, 2)
\$freeGB = [math]::Round(\$drive.Free / 1GB, 2)
\$usePct = [math]::Round(\$drive.Used / (\$drive.Used + \$drive.Free) * 100, 1)
Write-Output \"C: \$usedGB / \$totalGB GB (使用率: \$usePct%, 空き: \$freeGB GB)\"
"
```

## 削除対象一覧

### 定期削除 (cleanup-disk.ps1)

| 対象 | 内容 |
|------|------|
| RdClientAutoTrace | リモートデスクトップのトレースログ (.etl) |
| Temp | Windows一時ファイル（ロック中はスキップ） |
| npm-cache | npm パッケージキャッシュ |
| pip cache | pip パッケージキャッシュ |
| uv cache | uv パッケージキャッシュ（uv-receipt.json は温存） |
| telescope.log | Neovim telescope.nvim のログ |
| Chrome Cache | Cache_Data, Code Cache, Service Worker（Chrome終了が前提） |
| rocketchat-updater | Rocket.Chat 更新残骸 |
| obsidian-updater | Obsidian 更新残骸 |
| notion-updater | Notion 更新残骸 |

### 一度きり削除 (cleanup-once.ps1)

| 対象 | 内容 |
|------|------|
| AnthropicClaude 旧版 | app-1.1.2685, app-1.1.2998 |
| SquirrelTemp | アプリ更新一時ファイル |
| nvim-data.bak | Neovim データバックアップ |
| Puppeteer 旧 Chrome | 131.x, 138.x（最新 144 を残す） |
| Playwright 旧版 | chromium-1181（最新 1194 を残す） |

## 注意事項

- Chrome が起動中の場合、キャッシュ削除は自動スキップされる
- Temp 内のロック中ファイルは自動スキップされる
- DryRun なしの実行は必ずユーザー確認を取ること
- PowerShell のパスは `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`
