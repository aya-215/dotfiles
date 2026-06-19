---
name: wsl-unc-access
description: Use when accessing files on a Windows host's UNC admin share (\\IP\d$) from WSL — reading logs/CSV/.chk, listing directories, searching contents, or deploying files to the host. Typically a verification environment such as the hankyu shimebi-master host 192.168.161.90. Triggers include "90のログを見て", "検証環境のCSVを読んで", "WSLからWindows共有のファイルを見て", "\\IP\d$ にアクセス".
version: 1.0.0
---

# wsl-unc-access

## Overview

検証環境（既定 `192.168.161.90`）の Windows 共有 `\\IP\d$`（D ドライブの管理共有）配下のファイルを、WSL から読み書きするためのレシピ集。ローカルマシンには eBASE-Server 実体が無く、締め日マスタ等の登録経路が完結するのは検証環境のみ。そのため「コードはローカル(/mnt/d)で編集 → 実行・確認は検証環境で」という構成上、共有越しのファイルアクセスが定期的に必要になる。

**Core principle: WSL には smbclient/cifs が無く、drvfs マウントは sudo パスワードを毎回要求する。Windows の `powershell.exe` をフルパスで呼び、既存ログオンセッションの資格情報で `\\IP\d$` に到達する。これは追加権限ゼロで動く（2026-06-19 実測）。**

## When to Use

- 検証環境のログ/CSV/.chk の中身を確認したい（`shimebi_*.csv`, `*_debug.log`, `*.chk` など）。
- 共有配下のディレクトリ一覧・ファイル存在確認をしたい。
- ファイル内容を検索したい（`.chk` から `LineCount=` を抽出する等）。
- ローカル(/mnt/d)で編集した JSP/CSV/バッチを検証環境へ設置（コピー）したい。

**Not for:** ローカル(/mnt/d, /mnt/c)のファイル操作（普通の Bash ツールを使う）。drvfs マウントや cifs を新規に張ること（不採用）。`net use` での資格情報投入（手動で行う前提）。

## レシピ

各レシピは Bash ツールにそのまま貼れる。まず毎回この共通冒頭を置く:

```bash
PS='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
TARGET='192.168.161.90'   # 接続先。他の \\IP\d$ 環境はここを差し替え
```

### 1. 接続確認（最初に / 失敗が疑わしい時）

`$TARGET` は Bash が展開し、`\$` で `d$` のドル記号を PowerShell に渡す:

```bash
"$PS" -NoProfile -Command "if (Test-Path '\\\\$TARGET\\d\$') {'REACHABLE'} else {'UNREACHABLE'}" 2>&1
```
→ `REACHABLE` が期待値。`UNREACHABLE` の場合は資格情報切れか net use 未接続。**Windows 側で `net use \\$TARGET\d$` 済みかユーザーに確認を依頼する**（資格情報投入は手動が安全）。

### 2. 一覧（ディレクトリの中身・最新ファイル確認）

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-ChildItem '\\\\$TARGET\\d\$\\<DIR>' | Sort-Object LastWriteTime | Select-Object -Last 10 | Format-Table Name,Length,LastWriteTime -AutoSize" 2>&1
```
`<DIR>` 例: `Application\DeliveryCutOff\output\logs\20260617`
> `OutputEncoding=UTF8` で日本語ファイル名の化けを防ぐ。

### 3. 読み取り（CSV/.chk/log の中身。主用途）

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Content '\\\\$TARGET\\d\$\\<REL_PATH>' -Encoding default" 2>&1
```
`<REL_PATH>` 例: `Application\DeliveryCutOff\output\logs\20260617\shimebi_20260617153450_1_1100.csv.chk`
> 中身が Shift-JIS なので `-Encoding default`（＝CP932）。これと出力の `OutputEncoding=UTF8` は別軸で両方必要。

### 4. 検索（ファイル内のパターン抽出）

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Select-String -Path '\\\\$TARGET\\d\$\\<FILE>' -Pattern '<PAT>' -Encoding default | ForEach-Object { \$_.Line }" 2>&1
```
`<FILE>` 例: `Application\DeliveryCutOff\output\logs\20260617\shimebi_20260617153450_1_1100.csv.chk`
`<PAT>` 例: `Count`（→ `LineCount=1` / `ErrorCount=0` を抽出）
> 複数ファイルを横断するならワイルドカード可: `...\\20260617\\*.chk`。

### 5. 設置（WSL → 検証環境へコピー）

コピー元は **必ず `/mnt` 配下**（`/tmp` は Windows から見えない）。`/mnt/d/...` は `D:\...` に対応。

```bash
# 例: リポジトリの JSP を検証環境の ebase-web 配下へ
SRC='D:\tomcat\webapps\hankyu\add-on\eb-MDM-DBP\support\executeShimebiMaster.jsp'
DST="\\\\$TARGET\\d\$\\tomcat9\\webapps\\ebase-web\\add-on\\eb-MDM-DBP\\support\\executeShimebiMaster.jsp"
"$PS" -NoProfile -Command "Copy-Item '$SRC' '$DST' -Force; if (Test-Path '$DST') {'COPY-OK'} else {'COPY-FAILED'}" 2>&1
```
→ `COPY-OK` が期待値。
> `SRC` は `wslpath -w /mnt/d/.../foo.jsp` でも得られる。`DST` は `$TARGET` を二重引用符内で展開し、`\\`(共有先頭) と `\$`(d$ のドル) をエスケープする。
> 検証用の捨てファイルは後始末する: `"$PS" -NoProfile -Command "Remove-Item '$DST' -Force"`。

## 既知の地雷

- **エンコードは2軸**: 出力化け対策 `OutputEncoding=UTF8` と、ファイル中身の Shift-JIS 読み `-Encoding default` は別物。両方必要な場面が多い。
- **WEB コンテキストは `ebase-web`**（ローカルの `hankyu` ではない）。検証環境の URL は `http://<TARGET>/ebase-web`。
- **`\\IP\d$` は管理共有**で既存 Windows ログオンセッション依存。`net use` が切れていると失敗 → 接続確認レシピ(1)で切り分け、復旧はユーザーに依頼。
- **設置元は `/mnt` 配下限定**（`/tmp` 不可）。
- **`powershell.exe` は PATH に無い**ためフルパス必須。pwsh7（`/mnt/c/Program Files/PowerShell/7/pwsh.exe`）も存在するが既定は WindowsPowerShell を使う。
