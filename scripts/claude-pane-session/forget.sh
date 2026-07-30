#!/usr/bin/env bash
# Claude Code の SessionEnd hook。
# 終了した会話の session_id を「無効化(tombstone)」として追記する。
#
# なぜ必要か:
#   restore.sh は「同一パスのペインのうち pane_index 順で何番目か(rank)」で
#   会話を引き当てる。この方式は同一パスのペイン枚数が変わるとズレる。
#     例: 同じdirに2ペイン(会話A, 会話B) → 会話A側を閉じる
#         → 残ったペインが rank 0 になり、マップの rank 0 = 会話A を引く
#         → 自分の会話B ではなく隣の会話A が開く(実測で再現)
#   ペインを閉じると claude も終了し SessionEnd が発火するため、そこで
#   その会話の記録を無効化すれば、残る記録は会話B のみになり rank が整合する。
#
# wsl --shutdown との関係:
#   VM即停止では hook が走らないため tombstone は追記されない。つまり
#   意図せず落ちた場合は記録が丸ごと残り、全ペインが復元対象になる。
#   意図的に閉じた場合だけ間引かれる。これは望ましい挙動。
#
# 削除ではなく追記(tombstone)にする理由:
#   record.sh と本スクリプトは複数ペインで同時に発火しうる。
#   ファイルを読んで書き戻す方式(awk > tmp && mv)だと、その間に来た
#   追記を取りこぼす。追記のみなら競合しない。
#
# 座標ではなく session_id をキーに無効化する:
#   /clear や compact は(実測では SessionEnd を出さないが)新しい session_id を
#   発行しつつペインは生き続ける。座標で消すと生存中の会話を無効化しうる。

set -uo pipefail

MAP_FILE="${CLAUDE_PANE_SESSION_MAP:-$HOME/.local/share/claude-pane-session/map.tsv}"

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
[[ -f "$MAP_FILE" ]] || exit 0

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
[[ -n "$session_id" ]] || exit 0

# UUID形式でなければ何もしない(不正な値でマップを汚さない)
[[ "$session_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || exit 0

# 形式: END <TAB> <session_id>
# 通常のレコードは5列で1列目がsession名。1列目 END で区別する。
printf 'END\t%s\n' "$session_id" >> "$MAP_FILE"

exit 0
