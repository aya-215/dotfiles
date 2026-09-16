# Claude Code 通知フックのトースト送信部。
#
# このファイルが BOM 付き UTF-8 である理由:
#   PowerShell 5.1 は BOM の無い UTF-8 を CP932 として読む。BOM が無いと
#   スクリプト内の非ASCIIが壊れ、LoadXml が 0xC00CE56D で落ちる(実測)。
#   編集時に BOM を落とさないこと。
#
# wsl-notify-send.exe を使わない理由:
#   引数の非ASCIIを CP932 として解釈するため日本語が復元不能に壊れる。
#   UTF-8 の直渡しも CP932 への事前変換も効かない(実測)。
#
# アイコンを toast XML に直接埋めている理由:
#   AppUserModelId の IconUri に指定しても表示されない(実測)。
#   appLogoOverride で src を直接指定した場合のみ表示される。
#
# stdin の形式: 1行目=見出し, 2行目=作業ディレクトリ, 3行目=tmux pane ID
# pane ID を渡すと、クリックでその pane へ移動できる通知になる。

[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"
try {
  $text = [Console]::In.ReadToEnd().Trim()
  if (-not $text) { exit 0 }

  $lines = $text -split "`n", 3
  $title = [System.Security.SecurityElement]::Escape($lines[0].Trim())
  $body = if ($lines.Count -gt 1) { [System.Security.SecurityElement]::Escape($lines[1].Trim()) } else { "" }
  $pane = if ($lines.Count -gt 2) { $lines[2].Trim() } else { "" }

  [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
  [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType=WindowsRuntime] | Out-Null

  $icon = Join-Path $env:LOCALAPPDATA 'ClaudeCodeToast\icon.png'
  $img = if (Test-Path $icon) {
    "<image placement='appLogoOverride' hint-crop='circle' src='$([System.Security.SecurityElement]::Escape($icon))'/>"
  } else { "" }

  # pane ID が無い(tmux 外での実行など)場合もクリックで WezTerm へは飛べるよう、
  # activation 自体は常に付ける。ハンドラ側が pane 不在をフォールバックする。
  $launch = [System.Security.SecurityElement]::Escape("claude-pane://$pane")
  $attr = "activationType='protocol' launch='$launch'"

  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
  $xml.LoadXml("<toast $attr><visual><binding template='ToastGeneric'>$img<text>$title</text><text>$body</text></binding></visual></toast>")

  $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Claude Code").Show($toast)
} catch {
  exit 1
}
