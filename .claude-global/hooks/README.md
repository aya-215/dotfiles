# Claude Code 通知フック

入力待ち・完了・エラーを Windows のトーストで通知し、クリックで
その Claude が動いている tmux pane へ移動する。

## 構成

```
notify.sh    Notification/Stop/StopFailure フックの本体。文言を組み立てる
toast.ps1    トースト送信。stdin で 見出し/作業dir/pane ID を受ける
focus-pane.vbs  claude-pane:// のハンドラ(コンソールを出さないためのラッパー)
focus-pane.ps1  WezTerm を前面化し tmux pane へ移動する
```

クリック時の流れ:

```
トースト → claude-pane://%27 → wscript.exe → powershell.exe
  ├ Win32 API で WezTerm を前面化
  └ wsl.exe → tmux switch-client / select-window / select-pane
```

## 通知のタイミング

| いつ | 文言 | 遅延 |
|---|---|---|
| 応答が終わった | `応答完了・入力待ち` | 即座 |
| 承認ダイアログを放置 | `承認待ち: Bash: <コマンド>` | 約6秒 |
| 選択肢の質問を放置 | `質問に回答して` | 約6秒 |
| API エラーで停止 | `エラーで停止: rate_limit` | 即座 |

`permission_prompt` には約6秒のデバウンスがあり、すぐ承認すると発火しない。
`idle_prompt` は「入力待ちになった瞬間」ではなく放置の催促で、Stop から
実測 60.18 秒後に発火するため使っていない。

## セットアップ(この環境では適用済み)

Windows 側にのみ必要。すべて HKCU なので管理者権限は不要。

1. スクリプトを配置

```
%LOCALAPPDATA%\ClaudeCodeToast\
  focus-pane.ps1   ← このディレクトリからコピー
  focus-pane.vbs   ← 同上
  icon.png         ← claude-icon.png を 64x64 にリサイズしたもの
```

2. AppUserModelId を登録(通知の表示名。未登録だと通知が表示されない)

```powershell
$p = 'HKCU:\SOFTWARE\Classes\AppUserModelId\Claude Code'
New-Item -Path $p -Force
Set-ItemProperty -Path $p -Name DisplayName -Value 'Claude Code'
```

3. claude-pane プロトコルを登録(クリックの受け口)

```powershell
$p = 'HKCU:\SOFTWARE\Classes\claude-pane'
New-Item -Path "$p\shell\open\command" -Force
Set-ItemProperty -Path $p -Name '(Default)' -Value 'URL:Claude Pane Protocol'
Set-ItemProperty -Path $p -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$p\shell\open\command" -Name '(Default)' `
  -Value 'wscript.exe "%LOCALAPPDATA%\ClaudeCodeToast\focus-pane.vbs" "%1"'
```

`focus-pane.vbs` と `focus-pane.ps1` 内のパスは現状ハードコードのため、
ユーザー名が違う環境では書き換えが必要。

## ハマりどころ(すべて実測で確認済み)

- **`.ps1` は BOM 付き UTF-8 必須**。PowerShell 5.1 は BOM が無いと CP932 と
  して読むため、日本語が壊れて `LoadXml` が `0xC00CE56D` で落ちる。
- **`wsl-notify-send.exe` は使わない**。引数の非ASCIIを CP932 として解釈する
  ため日本語が復元不能に壊れる。UTF-8 直渡しも CP932 変換も効かない。
- **AppUserModelId が未登録だと `Show()` が成功を返しつつ表示されない**。
- **アイコンは `IconUri` では出ない**。toast XML の `appLogoOverride` に
  `src` を直接指定した場合のみ表示される。
- **`wezterm cli` は使えない**。`default_domain` が WSL ドメインのため CLI
  ソケットが Windows 側に露出せず、Windows から実行しても接続できない。
- **tmux のソケットは `/mnt/wslg/runtime-dir/tmux-1000/default`**。新規の
  `wsl.exe` には `TMUX_TMPDIR` が引き継がれず `/tmp/tmux-1000/default` を
  見に行くため、`-S` で明示指定する。
- **前面化は `AppActivate` では効かない**。トーストのクリックから
  wscript→powershell と2段挟むとフォアグラウンド権限が落ちるため、
  `AttachThreadInput` で入力状態を接続してから `SetForegroundWindow` する。
- **ハンドラに `powershell.exe` を直接指定しない**。`-WindowStyle Hidden` を
  付けてもコンソールが一瞬表示される。GUI サブシステムの `wscript.exe` から
  `Run(..., 0, False)` で起動する。
