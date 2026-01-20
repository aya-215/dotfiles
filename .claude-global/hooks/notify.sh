#!/bin/bash
# Claude Code 通知フック（wsl-notify-send版）

# wsl-notify-sendが利用可能かチェック
if command -v wsl-notify-send.exe &> /dev/null; then
  wsl-notify-send.exe --category "Claude Code" "入力待ちです" 2>/dev/null || true
elif grep -qi microsoft /proc/version 2>/dev/null; then
  # wsl-notify-sendがない場合はPowerShellのBurntToast経由で通知
  powershell.exe -NoProfile -Command "
    Import-Module BurntToast -ErrorAction SilentlyContinue
    if (Get-Module -Name BurntToast) {
      New-BurntToastNotification -Text 'Claude Code', '入力待ちです' -AppLogo '' -Silent
    }
  " 2>/dev/null || true
else
  # Linux nativeの場合
  notify-send 'Claude Code' '入力待ちです' 2>/dev/null || true
fi
