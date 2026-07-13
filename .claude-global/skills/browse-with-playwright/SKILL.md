---
name: browse-with-playwright
description: WSL環境でログインが必要なWebページをブラウザで開いて読み取り・文章化・操作する。「このページを読んで要約して」「ログインが必要なサイトの内容を抜き出して」「ブラウザで○○を開いて」「Webページの一部を文章化して」等で使用。Playwright CLI(@playwright/cli)を使い、永続プロファイルでログイン状態を保持する。
allowed-tools: Bash(npx:*), Bash(playwright-cli:*), Bash(curl:*), Bash(cat:*), Bash(ls:*), Bash(mkdir:*), AskUserQuestion
version: 1.0.0
---

# WSLでのブラウザ操作 (Playwright CLI)

WSL環境のClaudeがBash経由で `playwright-cli`（`@playwright/cli`）を叩き、ブラウザを操作する。
主用途は**ログインが必要なWebページを開いて、内容を読み取り・文章化すること**。
ターミナル切替やWindows版Claudeへの橋渡しは不要で、今のセッションのまま完結する。

## この環境の前提と確定事項（実機検証済み）

- **OS**: WSL2 + WSLg（`DISPLAY=:0` でブラウザ画面を表示できる＝手動ログインが可能）
- **普段使いのWindows Chromeには接続しない**: Chromeの `--remote-debugging-port` は起動時のみ指定可能で、走行中プロセスへの後付け不可。`attach --extension` はWSL側Linuxの `~/.config/google-chrome` を見るため対象外。→ **Playwright専用ブラウザ + 永続プロファイル方式を採用**
- **ブラウザ指定が必須**: 素の `playwright-cli open` は `/opt/google/chrome` を探して失敗する。**必ず `--browser=chromium` を付ける**
- **コマンド実行は `npx -y @playwright/cli@latest`** で叩く（グローバル未インストールのため）
- **永続プロファイル**: `~/playwright-browsing/profile` に保存。一度ログインすれば次回以降も維持される

## セットアップ（初回のみ）

`chrome-for-testing` ブラウザバイナリが必要（`--browser=chromium` が内部で要求する）。未インストールならエラーになるので、その場合だけ実行する:

```bash
npx -y @playwright/cli@latest install-browser chrome-for-testing
```

作業ディレクトリとプロファイル置き場:

```bash
mkdir -p ~/playwright-browsing
```

## 基本ワークフロー（ログインページの読み取り・文章化）

```bash
cd ~/playwright-browsing

# 1. 永続プロファイルでブラウザを開く（chromium指定・必須）
npx -y @playwright/cli@latest open --browser=chromium --profile=$HOME/playwright-browsing/profile <URL>

# 2. ログインが必要な場合: WSLgで表示されたブラウザ画面で「ユーザーが手動ログイン」する
#    → AskUserQuestion等でユーザーにログイン完了を確認してから次へ進む
#    → プロファイルに保存されるので2回目以降はログイン不要

# 3. ページ構造を取得（YAMLで要素ref e2,e3...とテキストが返る）
npx -y @playwright/cli@latest snapshot

# 4. 狙った箇所のテキストを直接抽出（--rawで値だけ出力）
npx -y @playwright/cli@latest eval "() => document.querySelector('SELECTOR')?.textContent" --raw

# 5. 終わったら閉じる
npx -y @playwright/cli@latest close
```

snapshotは `.playwright-cli/page-<timestamp>.yml` にも保存され、本文テキストを含むため、ここから文章化できる。

## ログイン確認の進め方

ログインが必要なサイトでは、ブラウザを開いた後に必ずユーザーへ手動ログインを依頼する。
`AskUserQuestion` で「ログインが完了したか」を確認してから読み取りに進むこと。画面が見えない状態で
先に進むと未ログインのページを読んでしまう。一度ログインすれば永続プロファイルに保存される。

## テキスト抽出の使い分け

- **ページ全体の構造把握** → `snapshot`（要素refとテキストをYAMLで取得、トークン効率が良い）
- **特定要素のテキスト** → `eval "() => document.querySelector('...').textContent" --raw`
- **複数要素を構造化抽出** → `eval "() => [...document.querySelectorAll('.item')].map(el => el.textContent)" --raw`
- **本文が長い/絞り込みたい** → `snapshot "#main"` や `snapshot --depth=4` で範囲・深さを限定

## よくあるエラーと対処

| エラー | 原因 | 対処 |
|---|---|---|
| `Chromium distribution 'chrome' is not found at /opt/google/chrome/chrome` | `--browser` 未指定 | `--browser=chromium` を付ける |
| `Browser "chrome-for-testing" is not installed` | バイナリ未DL | `install-browser chrome-for-testing` を実行 |
| `Playwright Extension not found` | `attach --extension` を使った | この方式は使わない。`open --browser=chromium` を使う |
| 画面が出ない | WSLg不調 | `echo $DISPLAY` で `:0` を確認、WSL再起動 |

## 詳細リファレンス

全コマンド（クリック/入力/タブ/ネットワーク/トレース/動画/テスト生成等）の網羅的な一覧は
[references/playwright-cli-full.md](references/playwright-cli-full.md) を参照する。
今回の主用途（読み取り・文章化）から外れる操作が必要になったときに開く。
