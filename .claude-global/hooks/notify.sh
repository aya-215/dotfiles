#!/usr/bin/env bash
# Claude Code 通知フック（wsl-notify-send版）
#
# 文言を動的生成する理由:
#   permission_prompt のペイロードにはツール名が入らない(実測)。含まれるのは
#   message/notification_type/transcript_path 程度で、"Claude needs your
#   permission" という固定文しか得られない。どのツールの承認待ちかは
#   transcript の「tool_result が未着の tool_use」から引く必要がある。
#
#   固定文言だと承認・完了・終了が全て同じ見た目になり、鳴っても判別できない。
#
# 送信を PowerShell 経由にしている理由:
#   wsl-notify-send.exe は引数の非ASCIIを CP932 として解釈するため日本語が
#   復元不能に壊れる。UTF-8 直渡しも CP932 への事前変換も効かない(実測)。
#   ToastNotificationManager を直接叩けば日本語が保たれる。ただし
#   AppUserModelId の登録が無いと Show() が成功を返しつつ表示されないため、
#   HKCU への登録が前提(この環境では登録済み)。

set -uo pipefail

PWSH="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
TOAST_PS1="$HOME/.claude/hooks/toast.ps1"

input=$(cat)
[[ -x "$PWSH" && -r "$TOAST_PS1" ]] || exit 0

get() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

evt=$(get '.hook_event_name')
ntype=$(get '.notification_type')
reason=$(get '.reason')
tpath=$(get '.transcript_path')
cwd=$(get '.cwd')

DIR_NAME=$(basename "${cwd:-$PWD}")

# 発火時点で未完了のツール呼び出しを取る。
# 「transcript 末尾の tool_use」ではなく tool_result が未着のものを選ぶのは、
# 並列ツール呼び出しのときに末尾が承認対象とは限らないため。
# 全行パースはコストが高いので末尾のみ読む。
pending_tool() {
  [[ -n "$tpath" && -r "$tpath" ]] || return 0
  tail -c 200000 "$tpath" 2>/dev/null | python3 -c '
import json,sys
uses={}; done=set(); order=[]
for line in sys.stdin:
    try: d=json.loads(line)
    except Exception: continue
    c=(d.get("message") or {}).get("content")
    if not isinstance(c,list): continue
    for b in c:
        if not isinstance(b,dict): continue
        if b.get("type")=="tool_use":
            i=b.get("id"); inp=b.get("input") or {}
            h=inp.get("command") or inp.get("file_path") or inp.get("description") or ""
            uses[i]=(b.get("name") or "?", " ".join(str(h).split())[:45]); order.append(i)
        elif b.get("type")=="tool_result":
            done.add(b.get("tool_use_id"))
p=[uses[i] for i in order if i in uses and i not in done]
if p:
    n,h=p[-1]
    print(f"{n}: {h}" if h else n)
' 2>/dev/null
}

case "$evt" in
  Notification)
    case "$ntype" in
      permission_prompt)
        tool=$(pending_tool)
        if [[ "$tool" == AskUserQuestion* ]]; then
          title="質問に回答して"
        elif [[ -n "$tool" ]]; then
          title="承認待ち: $tool"
        else
          title="承認待ち"
        fi
        ;;
      agent_needs_input)   title="エージェントが入力待ち" ;;
      elicitation_dialog|elicitation_url_dialog)
                           title="MCP が入力を要求" ;;
      quota_auto_resume_fired)
                           title="クォータ回復で再開" ;;
      *)                   title="通知: ${ntype:-?}" ;;
    esac
    ;;
  Stop)          title="応答完了・入力待ち" ;;
  StopFailure)   title="エラーで停止: ${reason:-不明}" ;;
  *)             title="${evt:-Claude Code}" ;;
esac

# フックは対象の pane 内で実行されるため $TMUX_PANE がそのまま使える。
# pane_index ではなく pane ID を使うのは、ペインを閉じると index が
# 繰り上がってズレるため(scripts/claude-pane-session/record.sh と同じ理由)。
printf '%s\n%s\n%s' "$title" "$DIR_NAME" "${TMUX_PANE:-}" |
  "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$TOAST_PS1")" 2>/dev/null
exit 0
