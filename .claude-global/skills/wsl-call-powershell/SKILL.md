---
name: wsl-call-powershell
description: Use when calling Windows PowerShell from WSL — running any powershell.exe one-liner via its full path with the existing logon session's credentials, with correct quoting/escaping and Japanese-safe encoding. General-purpose foundation, not tied to network shares. Triggers include "WSLからPowerShellを呼びたい", "powershell.exeで〜したい", "WSLからWindowsコマンドを実行", "文字化けする/エンコードがおかしい".
version: 1.0.0
---

# wsl-call-powershell

## Overview

WSL から Windows の `powershell.exe` を**外部プロセスとしてフルパスで呼ぶ**ための作法集。`powershell.exe` は WSL の `PATH` に無く、Bash のクォート・PowerShell のクォート・Windows のパス区切り・文字エンコードが何重にも噛み合うため、素朴に書くと化ける/通らない。ここでは「Bash ツールにそのまま貼って動く」形に正規化したテンプレを置く。

**Core principle: `powershell.exe` をフルパスで呼び、`-NoProfile -Command "…"` に PowerShell スクリプトを渡す。Bash の二重引用符の中で書くので、(1) PowerShell に渡す `$` は `\$` でエスケープ、(2) Windows パスの `\` は文字列内で必要なだけ重ねる、(3) 出力エンコードと入力（ファイル中身）エンコードは別軸で両方指定する、の3点を常に意識する。**

UNC 管理共有（`\\IP\d$`）越しのファイル読み書き・設置といった具体ユースケースは別スキル `wsl-unc-access` を参照。本スキルはその土台となる「PowerShell の呼び方そのもの」を扱う。

## When to Use

- WSL から Windows 側の処理を `powershell.exe` 経由で1回叩きたい（コマンド実行・存在確認・情報取得など）。
- PowerShell の出力やファイル中身が**文字化け**する／`$`・`\`・引用符まわりで**コマンドが通らない**。
- 出力を Bash 側で受けて後続処理したい（パイプ・変数代入）。
- pwsh7 と WindowsPowerShell のどちらを呼ぶか迷っている。

**Not for:** WSL/Linux 側のファイル操作（普通の Bash ツールを使う）。UNC 共有越しの read/list/search/deploy（→ `wsl-unc-access`）。GUI を要する Windows 操作。

## 共通の足場

まず毎回この冒頭を置く。`PS` をフルパスで固定するのが肝（PATH に無い）:

```bash
PS='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
```

最小形:

```bash
"$PS" -NoProfile -Command "<PowerShell式>" 2>&1
```
- `-NoProfile`: プロファイル読込を飛ばして速く・副作用なく。
- `2>&1`: PowerShell のエラーストリームも Bash 側で拾う。

## 3つの軸（ここがハマりどころ）

### 軸1: クォート / エスケープ

Bash の二重引用符 `"…"` の中に PowerShell スクリプトを書く。すると:

| 渡したいもの | Bash内での書き方 | 理由 |
|---|---|---|
| PowerShell の変数 `$_` 等 | `\$_` | `$` を Bash 展開から守って PS に渡す |
| Bash 側の変数（IP等）を埋める | `$TARGET`（エスケープしない） | Bash に展開させたいので素のまま |
| PowerShell 文字列リテラル | `'…'`（単一引用符） | Bash二重引用符内で安全。PS側で変数展開もされない |
| Windows パス区切り `\` | `\\`（リテラル1個につき2文字） | Bash の二重引用符内で `\` をエスケープ |

例（PowerShell の `$_` を使いつつ Bash 変数 `$DIR` を埋める）:

```bash
DIR='C:\temp'
"$PS" -NoProfile -Command "Get-ChildItem '$DIR' | ForEach-Object { \$_.Name }" 2>&1
```

### 軸2: 出力エンコード（化け対策）

PowerShell の標準出力を UTF-8 にして Bash 側へ渡す。日本語のファイル名・中身が化けるのを防ぐ:

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; <本体>" 2>&1
```

### 軸3: 入力（ファイル中身）エンコード

`Get-Content` / `Select-String` で**読むファイルが Shift-JIS（CP932）**なら `-Encoding default` を付ける。これは軸2（出力）とは**別物で、両方必要な場面が多い**:

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Content '<PATH>' -Encoding default" 2>&1
```
- UTF-8 のファイルなら `-Encoding utf8`、未指定だと PS のバージョン依存で揺れるので明示が安全。

## レシピ（汎用）

各レシピは Bash ツールにそのまま貼れる。

### 1. 単発実行 + 結果判定（存在確認の型）

```bash
"$PS" -NoProfile -Command "if (Test-Path 'C:\Windows\notepad.exe') {'OK'} else {'NG'}" 2>&1
```
→ `OK` / `NG` のような**機械判定しやすい文字列を返させる**のがコツ。

### 2. 一覧を整形して受け取る

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-ChildItem 'C:\temp' | Sort-Object LastWriteTime | Select-Object -Last 10 | Format-Table Name,Length,LastWriteTime -AutoSize" 2>&1
```

### 3. ファイル中身を読む（Shift-JIS）

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Content 'C:\temp\foo.csv' -Encoding default" 2>&1
```

### 4. ファイル内検索（パターン抽出）

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Select-String -Path 'C:\temp\*.log' -Pattern 'ERROR' -Encoding default | ForEach-Object { \$_.Line }" 2>&1
```

### 5. WSL パス ⇄ Windows パスの変換

`/mnt/c/...` ⇄ `C:\...` は `wslpath` で確実に変換できる（手書きで `\\` を数えるよりミスが少ない）:

```bash
wslpath -w /mnt/c/temp/foo.txt   # → C:\temp\foo.txt
wslpath -u 'C:\temp\foo.txt'     # → /mnt/c/temp/foo.txt
```
Windows から見えるのは `/mnt` 配下のみ。`/tmp` 等の Linux 専用領域は Windows プロセスから見えない。

## 既知の地雷

- **`powershell.exe` は PATH に無い** → フルパス必須。pwsh7（`/mnt/c/Program Files/PowerShell/7/pwsh.exe`）も存在するが、既定は WindowsPowerShell v1.0 を使う（環境差が少なく無難）。
- **エンコードは2軸**: 出力化け対策 `[Console]::OutputEncoding=UTF8`（軸2）と、読むファイルの `-Encoding default`（軸3）は別物。両方要る場面が多い。
- **`$` の二重の意味**: Bash も PowerShell も `$` を使う。PS の変数は `\$`、Bash 変数は素のまま。混ぜると静かに空文字になって誤動作する。
- **`\` の数え間違い**: 二重引用符内で Windows パスを直書きすると `\` を重ねる必要があり、UNC（`\\…`）だと特に間違いやすい → 迷ったら `wslpath -w` で生成する。
- **`/tmp` は Windows から不可視**: Windows プロセスに渡すパスは必ず `/mnt` 配下（= Windows ドライブ）にする。
