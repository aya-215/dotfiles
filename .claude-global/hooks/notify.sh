#!/bin/bash
# Claude Code 通知フック（wsl-notify-send版）
DIR_NAME=$(basename "${PWD}")
ICON_PATH="C:\\Users\\368\\bin\\claude-icon.png"
/mnt/c/Users/368/bin/wsl-notify-send.exe --appId "Claude Code" --category "${DIR_NAME}" --icon "${ICON_PATH}" "Ready for input"
