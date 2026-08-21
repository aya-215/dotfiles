# Claude Code statusline 導入手順（Windows）

配布用スクリプト: `.claude-global/statusline-simple.sh`

ディレクトリ・ブランチ・モデル・コンテキスト使用率を1行で表示する。
Claude.ai のサブスクリプションを使っている場合は、5時間 / 7日のレート
リミットが2〜3行目に追加で出る（APIキー利用時は出ない）。

```
DIR myproject | git: main* | AI Opus 5 (high) | ctx 8%
[####------]  42% | 5h reset: 21:40
[#########-]  91% | 7d reset: 水 27日
```

## 前提

| 必要なもの | 確認方法 | 備考 |
|---|---|---|
| Git for Windows | `where bash` | **必須**。Claude Code には bash は同梱されないので別途インストールが必要 |
| jq | `jq --version` | 任意。無い場合はコンテキスト率までは出るが、effort とレートリミットは表示されない |

Git for Windows も jq も winget で入る。

```powershell
winget install Git.Git
winget install jqlang.jq
```

## 導入

1. `statusline-simple.sh` を `%USERPROFILE%\.claude\statusline-command.sh` に置く

2. `%USERPROFILE%\.claude\settings.json` に以下を追加する。
   Git Bash 経由で呼ぶ必要があるのでフルパス指定にする。

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"C:\\Program Files\\Git\\bin\\bash.exe\" \"%USERPROFILE%\\.claude\\statusline-command.sh\""
  }
}
```

3. Claude Code を再起動する

## 表示のカスタマイズ

環境変数で2点だけ切り替えられる。既定のままでもどの端末でも読める。

### アイコン（既定: OFF）

`CC_STATUSLINE_ICONS=1` で Nerd Font のアイコン表示になる
（`DIR` → 󰉋、`git:` → 、バーが `#` → `█`）。

**Nerd Font をインストールし、かつ端末のフォントに設定している場合のみ**有効にすること。
フォントが無い状態で有効にすると、アイコンが全て豆腐（□）になって壊れて見える。
スクリプト側からフォントの有無は判定できないため、既定は OFF にしてある。

### 配色（既定: 自動判定）

`CC_STATUSLINE_COLOR` に `truecolor` / `basic` / `none` を指定できる。

自動判定は次の順で行う。

1. `COLORTERM` が `truecolor` / `24bit` → truecolor
2. `WT_SESSION` か `TERM_PROGRAM` がセットされている → truecolor
3. どちらでもない → basic（16色）

Git Bash は `COLORTERM` を設定しないため、素の Git Bash 単体では basic に、
Windows Terminal 経由なら truecolor になる。色が生のエスケープ文字
（`[38;2;...m` のような文字列）として表示される場合は `CC_STATUSLINE_COLOR=basic`
を、色を出したくない場合は `none` を指定する。

## トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| statusline が何も出ない | bash のパスが違う。`where bash` で確認して settings.json を修正する |
| `□□□` と表示される | Nerd Font が無いのに `CC_STATUSLINE_ICONS=1` になっている。この変数を外す |
| `[38;2;...m` が文字として出る | 端末が truecolor 非対応。`CC_STATUSLINE_COLOR=basic` を設定する |
| モデル名の後の `(high)` が出ない | jq が入っていない。`winget install jqlang.jq` |
| レートリミットの2〜3行目が出ない | APIキー利用時は出ない（仕様）。サブスクリプション利用時は最初の応答後に出る |
