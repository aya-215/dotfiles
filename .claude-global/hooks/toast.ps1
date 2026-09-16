# Claude Code 通知フックのトースト送信部。
#
# wsl-notify-send.exe を使わない理由:
#   引数に渡した非ASCIIを CP932 として解釈するため日本語が復元不能に壊れる。
#   UTF-8 をそのまま渡しても、事前に CP932 へ変換して渡しても化ける(実測)。
#   本文は stdin から UTF-8 で受け取る。引数経由は cmd 層でのエンコード劣化を
#   避けられないため使わない。
#
# appId "Claude Code" は wsl-notify-send が登録済みのものを流用する。
# アイコンと通知履歴をそのまま引き継ぐため。

[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"
try {
  $text = [Console]::In.ReadToEnd().Trim()
  if (-not $text) { exit 0 }

  [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
  [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType=WindowsRuntime] | Out-Null

  # 1行目を見出し、2行目以降を本文として扱う
  $lines = $text -split "`n", 2
  $title = [System.Security.SecurityElement]::Escape($lines[0].Trim())
  $body = if ($lines.Count -gt 1) { [System.Security.SecurityElement]::Escape($lines[1].Trim()) } else { "" }

  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
  $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$title</text><text>$body</text></binding></visual></toast>")

  $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Claude Code").Show($toast)
} catch {
  exit 1
}
