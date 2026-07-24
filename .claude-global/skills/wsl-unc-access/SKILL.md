---
name: wsl-unc-access
description: Use when accessing files on a Windows host's UNC share from WSL — reading logs/CSV/config, listing directories, searching contents, or deploying files to a remote Windows host over \\host\share. Covers both admin shares (d$, c$) and normal shares (\\host\projects), addressed by IP or hostname. Triggers include "WSLからWindows共有のファイルを見て", "リモートWindowsのログを読んで", "\\IP\d$ にアクセス", "検証環境のCSVを読んで". PowerShell呼び出しの基礎は wsl-call-powershell スキルに集約。
version: 1.2.0
---

# wsl-unc-access

## Overview

任意の Windows ホストの UNC 共有 `\\host\share`（管理共有 `d$`/`c$` でも、通常共有 `\\host\projects` でも）配下のファイルを、WSL から読み書きするためのレシピ集。用途は read（ログ/CSV/config の中身確認）・list（一覧・存在確認）・search（内容のパターン抽出）・deploy（WSL → リモートへコピー）の4つ。

**Core principle: WSL には smbclient/cifs が無く、drvfs マウントは sudo パスワードを毎回要求する。Windows の `powershell.exe` をフルパスで呼び、既存ログオンセッションの資格情報で `\\host\share` に到達する。これは追加権限ゼロで動く（2026-06-19 実測）。**

> PowerShell の呼び出し作法そのもの（フルパス必須・クォート/エスケープ・エンコード2軸・`wslpath`）は汎用スキル **`wsl-call-powershell`** に集約済み。本スキルはその応用（UNC 共有越しの read/list/search/deploy）に絞る。基礎で迷ったら `wsl-call-powershell` を参照。

## When to Use

- リモート Windows ホストの共有配下のファイル（ログ/CSV/config/バイナリ）の中身を確認したい。
- 共有配下のディレクトリ一覧・ファイル存在確認をしたい。
- ファイル内容をパターン検索したい。
- ローカル(/mnt/...)で編集したファイルをリモート Windows へ設置（コピー）したい。

**Not for:** ローカル(/mnt/d, /mnt/c)のファイル操作（普通の Bash ツールを使う）。drvfs マウントや cifs を新規に張ること（不採用）。`net use` での資格情報投入（手動で行う前提）。

## 接続先の指定（重要 — ここでエスケープを消す）

各レシピは Bash ツールにそのまま貼れる。まず毎回この共通冒頭を置く。**接続先の `\\host\share` 全体を `BASE` に、シングルクォートで代入する**のがコツ:

```bash
PS='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
BASE='\\192.168.161.90\d$'   # ← 接続先。ここだけ差し替える
```

`BASE` をシングルクォートで囲むと、末尾の `$`（`d$`/`c$` の管理共有記号）も `\` もすべてリテラルになる。二重引用符内で `"$BASE\..."` と参照しても bash は `$BASE` を**再スキャンせず素通し**するので、PowerShell には `\\192.168.161.90\d$\...` がそのまま届く。**結果、各レシピで `\$` エスケープも `\\` の二重化も一切不要**（`printf '%s' "$BASE"` で実際に届く文字列を確認済み）。

`BASE` の差し替え例（レシピ側は一切変えなくてよい）:

| 接続先 | BASE の値 |
|---|---|
| IP の D ドライブ管理共有 | `'\\192.168.161.90\d$'` |
| ホスト名の C ドライブ管理共有 | `'\\fileserver01\c$'` |
| 通常の公開共有（末尾 `$` なし） | `'\\fileserver01\projects'` |

> IP でもホスト名でも、名前解決さえ通れば同じ。ホスト名の場合は Windows 側で名前解決できることが前提。

## レシピ

### 1. 接続確認（最初に / 失敗が疑わしい時）

```bash
"$PS" -NoProfile -Command "if (Test-Path '$BASE') {'REACHABLE'} else {'UNREACHABLE'}" 2>&1
```
→ `REACHABLE` が期待値。`UNREACHABLE` の場合は資格情報切れか net use 未接続。**Windows 側で `net use \\host\share` 済みかユーザーに確認を依頼する**（資格情報投入は手動が安全）。

### 2. 一覧（ディレクトリの中身・最新ファイル確認）

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-ChildItem '$BASE\<DIR>' | Sort-Object LastWriteTime | Select-Object -Last 10 | Format-Table Name,Length,LastWriteTime -AutoSize" 2>&1
```
`<DIR>` 例: `Application\logs\20260617`
> `OutputEncoding=UTF8` で日本語ファイル名の化けを防ぐ。

### 3. 読み取り（CSV/.chk/log の中身。主用途）

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Content '$BASE\<REL_PATH>' -Encoding default" 2>&1
```
`<REL_PATH>` 例: `Application\logs\20260617\shimebi_20260617153450_1_1100.csv.chk`
> 中身が Shift-JIS(CP932) なら `-Encoding default`、UTF-8 なら `-Encoding UTF8`。これと出力の `OutputEncoding=UTF8` は別軸で両方必要。

### 4. 検索（ファイル内のパターン抽出）

```bash
"$PS" -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Select-String -Path '$BASE\<FILE>' -Pattern '<PAT>' -Encoding default | ForEach-Object { \$_.Line }" 2>&1
```
`<FILE>` 例: `Application\logs\20260617\shimebi_20260617153450_1_1100.csv.chk`
`<PAT>` 例: `Count`
> 複数ファイルを横断するならワイルドカード可: `...\20260617\*.chk`。`\$_.Line` の `\$` は PowerShell の自動変数 `$_` を bash の変数展開から守るためのエスケープ（BASE のパスとは無関係）。

### 5. 設置（WSL → リモート Windows へコピー）

コピー元は **必ず `/mnt` 配下**（`/tmp` は Windows から見えない）。`/mnt/d/...` は `D:\...` に対応。

```bash
SRC="$(wslpath -w /mnt/d/path/to/foo.jsp)"   # → D:\path\to\foo.jsp
DST="$BASE\add-on\eb-MDM-DBP\support\foo.jsp"
"$PS" -NoProfile -Command "Copy-Item '$SRC' '$DST' -Force; if (Test-Path '$DST') {'COPY-OK'} else {'COPY-FAILED'}" 2>&1
```
→ `COPY-OK` が期待値。
> 検証用の捨てファイルは後始末する: `"$PS" -NoProfile -Command "Remove-Item '$DST' -Force"`。

## 既知の地雷

- **`\\host\d$` は管理共有**で既存 Windows ログオンセッション依存。`net use` が切れていると失敗 → 接続確認レシピ(1)で切り分け、復旧はユーザーに依頼。通常共有（`\\host\projects` 等、末尾 `$` なし）も同様に事前接続が前提。
- **設置元は `/mnt` 配下限定**（`/tmp` 不可）。
- **UNC 特有のエスケープはこれだけ**: 管理共有名 `d$`/`c$` に含まれる `$` は、`BASE` をシングルクォートで代入すれば無害化される（上記「接続先の指定」参照）。通常共有には `$` が無いので、そもそも気にする必要はない。

### 固有環境の例（hankyu 検証環境）

このスキルが生まれた元の用途。参考として残す:
- 接続先: `BASE='\\192.168.161.90\d$'`
- WEB コンテキストは `ebase-web`（ローカルの `hankyu` ではない）。URL は `http://192.168.161.90/ebase-web`。
- ログ配置: `Application\DeliveryCutOff\output\logs\<yyyymmdd>\shimebi_*.csv` / `*.chk`。`.chk` に `LineCount=` / `ErrorCount=` が入る。
- 設置先の一例: `\\192.168.161.90\d$\tomcat9\webapps\ebase-web\add-on\eb-MDM-DBP\support\`。

> 汎用の地雷（エンコード2軸・`powershell.exe` フルパス必須・`$`/`\` の一般的なエスケープ・pwsh7 との使い分け）は `wsl-call-powershell` の「既知の地雷」に集約。
