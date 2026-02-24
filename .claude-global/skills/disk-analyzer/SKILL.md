---
name: disk-analyzer
description: Use when the user mentions disk space, storage, C drive capacity, or asks to investigate what's consuming space. Triggers on keywords like ディスク容量, Cドライブ, ストレージ, 空き容量, 容量調査, disk space.
allowed-tools: Bash(powershell.exe:*), Bash(df:*), Bash(ls:*), AskUserQuestion
---

# Cドライブ容量分析

Windows Cドライブの使用状況を段階的に分析し、削減候補を特定するスキル。

## スクリプト

| スクリプト | 用途 | パス |
|-----------|------|------|
| `analyze-disk.ps1` | 段階的容量分析 | `C:\Users\368\scripts\analyze-disk.ps1` |

## 引数

- `$1`: 操作（省略可）
  - `quick` — Phase 1のみ（全体概況）
  - `full` — 全フェーズ実行
  - 省略時 — AskUserQuestion で選択

## PowerShell実行パス

```
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
```

## 実行フロー

### Phase 1: 全体概況

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\analyze-disk.ps1' -Phase 1
```

使用率90%超 → 即座にクリーンアップ推奨、80%超 → 監視継続。

### Phase 2: トップレベル内訳

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\analyze-disk.ps1' -Phase 2
```

`C:\` 直下の主要フォルダサイズ（降順）。WSL仮想ディスクが大きい場合はWSL内調査を別途提案。

### Phase 3: AppData詳細

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\analyze-disk.ps1' -Phase 3
```

`AppData\Local` 内の50MB超フォルダ一覧。

### Phase 4: キャッシュ・旧バージョン検出

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File 'C:\Users\368\scripts\analyze-disk.ps1' -Phase 4
```

既知のキャッシュ場所の個別サイズ + 旧バージョン自動検出（Claude Desktop, Playwright, Puppeteer）。

## レポート形式

Phase 4完了後、以下の形式でユーザーに報告する:

```markdown
## 分析結果

| サイズ | 場所 | 分類 |
|--------|------|------|
| X GB   | ...  | 定期削除 / 一度きり / 対応不要 |

### 削減提案
- 定期削除対象: 合計 X GB（cleanup-disk で対応）
- 一度きり削除: 合計 X GB（cleanup-once で対応）
- 要調査: ...
```

## 肥大化しやすい場所（ベストプラクティス）

### 定期的に増える（週次クリーンアップ対象）

| 場所 | 理由 |
|------|------|
| `AppData\Local\Temp` | あらゆるアプリの一時ファイル |
| `Temp\DiagOutputDir\RdClientAutoTrace` | RDP接続ログ (.etl)、際限なく増える |
| `AppData\Local\npm-cache` | npm install の度に蓄積 |
| `AppData\Local\pip\cache` | pip install の度に蓄積 |
| `AppData\Local\uv\cache` | Python uv パッケージキャッシュ |
| `AppData\Local\pnpm` | pnpm ストアキャッシュ |
| Chrome/Edge Cache系 | Service Worker, Code Cache, Cache_Data |
| `nvim-data\telescope.log` | Telescope使用で肥大化 |
| `*-updater` フォルダ群 | Electron系アプリ更新残骸 |

### バージョン管理（旧版削除対象）

| 場所 | 方針 |
|------|------|
| `AnthropicClaude\app-*` | 最新1バージョン以外を削除 |
| `ms-playwright\chromium-*` | 最新1バージョン以外を削除 |
| `.cache\puppeteer\chrome\*` | 最新1バージョン以外を削除 |

### 大きいが削除非推奨

| 場所 | 理由 |
|------|------|
| `C:\Windows` (~34GB) | OS本体、Disk Cleanup に任せる |
| `C:\Program Files` | インストール済みアプリ。不要アプリはコントロールパネルから |
| `nvim-data\mason` | LSPサーバー群、必要なもの |
| `AppData\Local\Programs` | ユーザーインストールアプリ本体 |

## 推奨運用サイクル

- **Storage Sense** を有効化 → 自動Temp削除
- **週1回**: `cleanup-disk` スキルで定期クリーンアップ
- **月1回**: このスキルでフル調査 → 新たな肥大化を早期発見
- **目標**: 空き容量15-20%以上を維持（238GBなら36-48GB）

## cleanup-disk との連携

分析完了後、削減が必要な場合:

1. 定期削除対象 → `/cleanup-disk periodic`
2. 一度きり削除対象 → `/cleanup-disk once`
3. 新発見の肥大化 → cleanup-disk スクリプトに追加を提案

## 実行記録の保存

分析実行後は `agent-memory` に結果サマリーを保存する:

```
memories/disk-analysis/YYYY-MM-DD.md
```

過去の記録と比較して増減傾向を報告する。
