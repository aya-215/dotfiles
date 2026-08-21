# Claude Code statusline 導入手順（Windows）

カレントディレクトリ・gitブランチ・モデル名・コンテキスト使用率を1行で表示する。
Claude.ai のサブスクリプションを使っている場合は、5時間 / 7日のレートリミットが
2〜3行目に追加される（APIキー利用時は表示されない）。

```
DIR myproject | git: main* | AI Opus 5 (high) | ctx 8%
[####------]  42% | 5h reset: 21:40
[#########-]  91% | 7d reset: 水 27日
```

## 前提

| 必要なもの | 確認方法 | 備考 |
|---|---|---|
| Git for Windows | `where bash` | **必須**。Claude Code に bash は同梱されないので別途インストールが必要 |
| jq | `jq --version` | 任意。無い場合もディレクトリ・ブランチ・モデル・コンテキスト率までは表示される（モデル名の後の `(high)` とレートリミット行が出なくなる） |

どちらも winget で入る。

```powershell
winget install Git.Git
winget install jqlang.jq
```

## 導入

1. `.claude-global/statusline-simple.sh` を
   `%USERPROFILE%\.claude\statusline-command.sh` にコピーする

2. `%USERPROFILE%\.claude\settings.json` に以下を追加する。
   Git Bash 経由で呼ぶ必要があるのでフルパスで指定する。

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" \"%USERPROFILE%\\.claude\\statusline-command.sh\""
  }
}
```

3. Claude Code を再起動する

環境変数の設定は不要。そのまま動く。

## 表示内容

| 表示 | 意味 |
|---|---|
| `DIR myproject` | カレントディレクトリ名 |
| `git: main*` | gitブランチ。`*` は未コミットの変更あり |
| `AI Opus 5 (high)` | モデル名と reasoning effort（`/effort` で変更した値） |
| `ctx 8%` | コンテキスト使用率 |
| `TODO 3` | 未完了タスク数。1件以上のときだけ表示 |
| `[####------] 42%` | レートリミット消費率。50%以上で黄、80%以上で赤 |

## トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| statusline が何も表示されない | bash のパスが違う。`where bash` で確認して settings.json を修正する |
| `[38;2;...m` のような文字列が見える | 端末が24bitカラー非対応。Windows Terminal を使う |
| モデル名の後の `(high)` が出ない | jq が未インストール。`winget install jqlang.jq` |
| レートリミットの2〜3行目が出ない | APIキー利用時は表示されない（仕様）。サブスクリプション利用時は最初の応答後から表示される |

## 見た目を変えたい場合

このスクリプトは環境設定なしで動くことを優先し、アイコンを使わず ASCII 文字
（`DIR` / `git:` / `AI` / `ctx`）で表示している。

Nerd Font をインストールしていて、かつ端末のフォントに設定している場合は、
アイコン表示版に差し替えられる。リポジトリの
`.claude-global/statusline-command.sh`（作者が使っているもの）が該当する。

```
󰉋 myproject | ⑂ main* | 󰚩 Opus 5 (high) | 󰆼 10% (35K/775K)
```

**フォントが入っていない状態でこちらを使うと、アイコンが全て豆腐（□）になる。**
フォントの有無はスクリプト側から判定できないため、既定では ASCII 版を配布している。
