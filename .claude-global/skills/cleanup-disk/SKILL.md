---
name: cleanup-disk
description: Windows/WSLのディスククリーンアップを実行する
allowed-tools: Bash(powershell.exe:*), Bash(bash:*), Bash(ls:*), Bash(df:*), Bash(du:*), AskUserQuestion
version: 2.0.0
---

# ディスククリーンアップ

Windows（Cドライブ）またはWSLのキャッシュ・ログ・一時ファイルを安全に削除するスキル。

## 引数

- `$1`: ターゲット（省略可）
  - `windows` — Windows（Cドライブ）を対象
  - `wsl` — WSLを対象
  - 省略時 — AskUserQuestion で選択
- `$2`: 操作（省略可）
  - `periodic` — 定期削除を実行
  - `once` — 一度きり削除を実行（Windowsのみ）
  - `status` — 現在のディスク使用状況を表示
  - 省略時 — AskUserQuestion で選択

## 実行フロー

### 1. ターゲットの決定

引数が指定されていない場合、AskUserQuestion で選択させる:
- **Windows** — Cドライブのクリーンアップ
- **WSL** — WSL環境のクリーンアップ

### 2. ターゲット別のフローへ

---

# Windows（Cドライブ）

## スクリプト

| スクリプト | 用途 | パス |
|-----------|------|------|
| `cleanup-disk.ps1` | 定期削除（週1回推奨） | `C:\Users\368\scripts\cleanup-disk.ps1` |
| `cleanup-once.ps1` | 一度きりの旧バージョン削除 | `C:\Users\368\scripts\cleanup-once.ps1` |

## 操作の決定

引数が指定されていない場合、AskUserQuestion で操作を選択させる:
- 定期クリーンアップ（キャッシュ・ログ・Temp）
- 一度きり削除（旧バージョン・残骸）
- ディスク使用状況の確認のみ

## DryRun の実行

**必ず DryRun を先に実行**して結果をユーザーに表示する。

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\cleanup-disk.ps1' -DryRun
```

または:

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\cleanup-once.ps1' -DryRun
```

## ユーザー確認

DryRun の結果を表示し、以下を AskUserQuestion で確認:
- 実行してよいか
- Chrome/Office/Neovim などロック要因のアプリを閉じたか

## 本実行

承認を得たら `-DryRun` なしで実行:

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\cleanup-disk.ps1'
```

## status 操作

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

---

# WSL

## スクリプト

| スクリプト | 用途 | パス |
|-----------|------|------|
| `cleanup-wsl.sh` | 定期削除（月1回推奨） | `~/.dotfiles/scripts/cleanup-wsl.sh` |

## 操作の決定

引数が指定されていない場合、AskUserQuestion で操作を選択させる:
- 定期クリーンアップ（キャッシュ・Nix GC・ログ）
- ディスク使用状況の確認のみ

## DryRun の実行

**必ず DryRun を先に実行**して結果をユーザーに表示する。

```bash
bash ~/.dotfiles/scripts/cleanup-wsl.sh --dry-run
```

## ユーザー確認

DryRun の結果を表示し、以下を AskUserQuestion で確認:
- 実行してよいか
- Nix GC は過去の世代を全て削除するがよいか

## 本実行

承認を得たら `--dry-run` なしで実行:

```bash
bash ~/.dotfiles/scripts/cleanup-wsl.sh
```

## status 操作

```bash
df -h /
echo "---"
du -sh ~/.cache/uv ~/.npm ~/.cache/pip ~/.cache/nix ~/.backup-logs /nix/store 2>/dev/null
```

## 削除対象一覧

### 定期削除 (cleanup-wsl.sh)

| 対象 | コマンド | 備考 |
|------|---------|------|
| uv cache | `uv cache clean` | 月数GB溜まる、最優先 |
| npm cache | `npm cache clean --force` | install毎に増加 |
| pip cache | `pip cache purge` | 低〜中頻度 |
| Nix store | `nix-collect-garbage -d` | 古い世代を削除（ロールバック不可になる） |
| Nix cache | `rm -rf ~/.cache/nix` | GCでは消えないキャッシュ |
| backup-logs | `rm -rf ~/.backup-logs` | 日次バックアップのログファイル |

## 注意事項

- `nix-collect-garbage -d` は過去の全世代を削除する。現在の環境は影響なし
- コマンドが存在しない場合は自動スキップされる
- 実行に数分かかる場合がある（特にNix GC）
