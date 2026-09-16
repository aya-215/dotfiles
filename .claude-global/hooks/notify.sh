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
#   壊れる。UTF-8 のまま渡しても CP932 に変換して渡しても復元できない(実測)。
#   PowerShell に stdin から UTF-8 で渡せばコードポイントが保たれる。

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
  StopFailure)   title="エラーで停止${reason:+: $reason}" ;;
  SessionEnd)    title="セッション終了" ;;
  *)             title="${evt:-Claude Code}" ;;
esac

printf '%s\n%s' "$title" "$DIR_NAME" |
  "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$TOAST_PS1")" 2>/dev/null
exit 0
