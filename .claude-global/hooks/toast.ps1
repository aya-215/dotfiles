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
# 本文は stdin から UTF-8 で受け取る。引数経由は cmd 層でのエンコード劣化を
# 避けられないため使わない。

[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"
try {
  $text = [Console]::In.ReadToEnd().Trim()
  if (-not $text) { exit 0 }

  # 1行目を見出し、2行目を本文(作業ディレクトリ)として扱う
  $lines = $text -split "`n", 2
  $title = [System.Security.SecurityElement]::Escape($lines[0].Trim())
  $body = if ($lines.Count -gt 1) { [System.Security.SecurityElement]::Escape($lines[1].Trim()) } else { "" }

  [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
  [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType=WindowsRuntime] | Out-Null

  $icon = Join-Path $env:LOCALAPPDATA 'ClaudeCodeToast\icon.png'
  $img = if (Test-Path $icon) {
    "<image placement='appLogoOverride' hint-crop='circle' src='$([System.Security.SecurityElement]::Escape($icon))'/>"
  } else { "" }

  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
  $xml.LoadXml("<toast><visual><binding template='ToastGeneric'>$img<text>$title</text><text>$body</text></binding></visual></toast>")

  $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Claude Code").Show($toast)
} catch {
  exit 1
}
