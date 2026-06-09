# Claude会話 セッション要約システム Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code のセッション終了時に Haiku で会話を構造化要約し、夜の daily-review がそれを集約して正確な日報サマリーを作る仕組みを構築する。

**Architecture:** SessionEnd hook が終了したセッションの transcript JSONL をバックグラウンドで要約プロセスに渡す。前処理（extract.py）で text + ツールメタだけ抽出 → `claude -p --model haiku` で6項目要約 → `~/.nb/claude/sessions/YYYY-MM-DD/<session_id>.md` に保存。daily-review-auto.sh は生ログ参照をやめ、この要約群を集約する。既存の `claude-nb-sync.py`（生ログ整形）は完全廃止。

**Tech Stack:** bash, python3, Claude Code CLI (`claude -p`), cron, SessionEnd hook（`~/.claude/settings.json`）。すべてサブスク枠で動き API 課金なし。

設計: `docs/superpowers/specs/2026-06-09-claude-session-summary-design.md`

---

## File Structure

| ファイル | 責務 | 新規/改修 |
|---|---|---|
| `scripts/claude-summarize/extract.py` | JSONL 1本から text + ツールメタ抽出（tool_result 本体除外） | 新規 |
| `scripts/claude-summarize/summarize.sh` | extract.py で前処理 → Haiku で6項目要約 → `sessions/` に保存 | 新規 |
| `scripts/claude-summarize/summarize-session.sh` | SessionEnd hook 入力(JSON)を受け、判定 → summarize.sh をバックグラウンド起動 → 即 exit 0 | 新規 |
| `.claude-global/settings.json` | SessionEnd hook に summarize-session.sh を1コマンド追加 | 改修 |
| `scripts/daily-review/daily-review-auto.sh` | 生ログ参照をやめ `sessions/` の要約を集約 | 改修 |
| crontab | `claude-nb-sync.py` の5分cron行を削除 | 改修 |
| `scripts/claude-sync/` 一式 + `~/.claude/nb-sync-state.json` | 廃止 | 削除 |

要約出力先: `~/.nb/claude/sessions/YYYY-MM-DD/<session_id>.md`

---

### Task 1: extract.py — JSONL から text + ツールメタを抽出

**Files:**
- Create: `scripts/claude-summarize/extract.py`
- Test: 手動実行で検証（pytest 環境がないため実 JSONL で確認）

JSONL の `user`/`assistant` 行を走査し、会話 text と「どのツールを何に使ったか」のメタ情報だけを
プレーンテキスト化する。巨大な `tool_result` 本体（コマンド出力・diff）は捨てる。
セッションのメタ（project=cwd の basename、session_id、開始/終了時刻）も先頭に出力する。

- [ ] **Step 1: extract.py を作成**

```python
#!/usr/bin/env python3
"""
Claude Code セッション JSONL から、要約に必要な情報だけを抽出する。

会話の text ブロックと、ツール使用のメタ情報（ツール名・編集ファイルパス・
Bash コマンド）を残し、巨大な tool_result 本体は捨てる。これにより
Haiku の 200K コンテキストに確実に収まり、ノイズも除去される。

使用方法:
    python3 extract.py <transcript.jsonl>
標準出力に整形済みテキストを出す。JSONL が読めない場合は exit 1。
"""
import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: extract.py <transcript.jsonl>", file=sys.stderr)
        return 1

    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"ERROR: ファイルが見つかりません: {path}", file=sys.stderr)
        return 1

    cwd = ""
    session_id = ""
    first_ts = ""
    last_ts = ""
    lines_out: list[str] = []

    with path.open(encoding="utf-8") as fh:
        for raw in fh:
            try:
                d = json.loads(raw)
            except json.JSONDecodeError:
                continue

            if d.get("type") not in ("user", "assistant"):
                continue

            # メタ情報を拾う（最初に出てきた値を採用）
            if not cwd and d.get("cwd"):
                cwd = d["cwd"]
            if not session_id and d.get("sessionId"):
                session_id = d["sessionId"]
            ts = d.get("timestamp", "")
            if ts:
                if not first_ts:
                    first_ts = ts
                last_ts = ts

            role = "User" if d["type"] == "user" else "Claude"
            content = d.get("message", {}).get("content", "")

            if isinstance(content, str):
                text = content.strip()
                if text:
                    lines_out.append(f"**{role}:** {text}")
                continue

            if not isinstance(content, list):
                continue

            for item in content:
                if not isinstance(item, dict):
                    continue
                itype = item.get("type")
                if itype == "text":
                    text = item.get("text", "").strip()
                    if text:
                        lines_out.append(f"**{role}:** {text}")
                elif itype == "tool_use":
                    name = item.get("name", "?")
                    inp = item.get("input", {})
                    # ツールごとに要約に有用なメタだけ抜く
                    if name in ("Edit", "Write", "Read", "NotebookEdit"):
                        meta = inp.get("file_path", "")
                    elif name == "Bash":
                        meta = inp.get("command", "")[:120]
                    elif name in ("Grep", "Glob"):
                        meta = inp.get("pattern", "")
                    else:
                        meta = ""
                    lines_out.append(f"  [tool:{name}] {meta}".rstrip())
                # tool_result は本体を捨てる（要約に不要・巨大）

    project = Path(cwd).name if cwd else "unknown"
    header = [
        f"project: {project}",
        f"session_id: {session_id}",
        f"cwd: {cwd}",
        f"start: {first_ts}",
        f"end: {last_ts}",
        "---",
    ]
    print("\n".join(header))
    print("\n".join(lines_out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: 実行権限を付与**

Run: `chmod +x ~/.dotfiles/scripts/claude-summarize/extract.py`

- [ ] **Step 3: 構文チェック**

Run: `python3 -c "import ast; ast.parse(open('$HOME/.dotfiles/scripts/claude-summarize/extract.py').read()); print('OK')"`
Expected: `OK`

- [ ] **Step 4: 実 JSONL で動作確認（小さいセッション）**

Run:
```bash
f=$(find ~/.claude/projects -name "*.jsonl" -mtime -7 | grep -v subagents | while read p; do echo "$(wc -c <"$p") $p"; done | sort -n | tail -1 | awk '{print $2}')
python3 ~/.dotfiles/scripts/claude-summarize/extract.py "$f" | head -30
echo "---文字数---"; python3 ~/.dotfiles/scripts/claude-summarize/extract.py "$f" | wc -c
```
Expected: 先頭に `project:` 等のヘッダ、続いて `**User:**` / `**Claude:**` / `[tool:...]` 行。tool_result の巨大出力が含まれないこと。文字数が元 JSONL より大幅に小さいこと。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add scripts/claude-summarize/extract.py
git commit -m "feat: セッションJSONLからtext+ツールメタを抽出するextract.pyを追加"
```

---

### Task 2: summarize.sh — Haiku で6項目要約を生成

**Files:**
- Create: `scripts/claude-summarize/summarize.sh`
- Test: 手動実行で検証

extract.py で前処理した内容を `claude -p --model haiku` に渡し、6項目の構造化要約を
`~/.nb/claude/sessions/YYYY-MM-DD/<session_id>.md` に保存する。日付は JSONL の最終 timestamp（JST）から決める。

- [ ] **Step 1: summarize.sh を作成**

```bash
#!/bin/bash
# summarize.sh - セッション JSONL 1本を Haiku で6項目要約し、sessions/ に保存する
#
# extract.py で前処理（text + ツールメタ抽出）してから claude -p --model haiku に渡す。
# サブスク枠で動くため API 課金はなく、要約は軽いタスクなので Haiku で十分。
#
# 使用方法:
#   ./summarize.sh <transcript.jsonl> <session_id>
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLAUDE_BIN="$HOME/.local/bin/claude"
readonly SESSIONS_ROOT="$HOME/.nb/claude/sessions"

transcript="${1:?usage: summarize.sh <transcript.jsonl> <session_id>}"
session_id="${2:?usage: summarize.sh <transcript.jsonl> <session_id>}"

# 前処理（失敗したら何もせず終了）
extracted="$(python3 "$SCRIPT_DIR/extract.py" "$transcript" 2>/dev/null)" || exit 0
# 中身が実質空（ヘッダのみ）なら要約しない
body_lines="$(printf '%s\n' "$extracted" | sed -n '/^---$/,$p' | tail -n +2 | grep -c .)" || body_lines=0
[ "$body_lines" -gt 0 ] || exit 0

# 対象日を JSONL の最終 timestamp（JST）から決める。取れなければ今日。
target_date="$(printf '%s\n' "$extracted" \
  | sed -n 's/^end: //p' | head -1 \
  | { read -r ts; [ -n "$ts" ] && TZ=Asia/Tokyo date -d "$ts" +%Y-%m-%d 2>/dev/null || TZ=Asia/Tokyo date +%Y-%m-%d; })"

out_dir="$SESSIONS_ROOT/$target_date"
mkdir -p "$out_dir"
out_file="$out_dir/$session_id.md"

read -r -d '' PROMPT <<EOF || true
以下は Claude Code の1セッションの会話ログ（前処理済み: 会話テキストとツール使用メタのみ）です。
このセッションを日本語で要約し、**下記6項目の Markdown のみ**を出力してください。前置き・後置きは一切不要。

各項目の書き方:
- ## 意図 — このセッションで何をしようとしたか（1〜2行）
- ## 作業内容 — 実際に行った調査・実装のステップ（箇条書き）
- ## 結論 — 何が分かった・何ができたか（1〜2行）
- ## 編集/作成ファイル — [tool:Edit/Write] のファイルパス。なければ「調査のみ」
- ## 実行した主なコマンド — [tool:Bash] の特徴的なコマンド。なければ省略
- ## ナレッジ候補 — memory に残す価値のある発見。なければ「なし」

冒頭に必ず以下の frontmatter を付けること（会話ログのヘッダの値を転記）:
---
project: <project>
session_id: <session_id>
start: <start>
end: <end>
cwd: <cwd>
---

=== 会話ログ ===
${extracted}
EOF

"$CLAUDE_BIN" -p "$PROMPT" --model haiku > "$out_file" 2>/dev/null || { rm -f "$out_file"; exit 0; }
```

- [ ] **Step 2: 実行権限を付与**

Run: `chmod +x ~/.dotfiles/scripts/claude-summarize/summarize.sh`

- [ ] **Step 3: 構文チェック**

Run: `bash -n ~/.dotfiles/scripts/claude-summarize/summarize.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: 実セッションで要約を生成して確認**

Run:
```bash
f=$(find ~/.claude/projects -name "*.jsonl" -mtime -7 | grep -v subagents | head -1)
sid=$(basename "$f" .jsonl)
env -u CLAUDECODE bash ~/.dotfiles/scripts/claude-summarize/summarize.sh "$f" "$sid"
echo "=== 生成された要約 ==="
cat ~/.nb/claude/sessions/*/"$sid".md 2>/dev/null | head -40
```
Expected: frontmatter + 6項目（意図/作業内容/結論/編集ファイル/コマンド/ナレッジ候補）の Markdown が生成される。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add scripts/claude-summarize/summarize.sh
git commit -m "feat: Haikuでセッションを6項目要約するsummarize.shを追加"
```

---

### Task 3: summarize-session.sh — SessionEnd hook 入口

**Files:**
- Create: `scripts/claude-summarize/summarize-session.sh`
- Test: hook 入力 JSON を模した stdin で検証

SessionEnd hook から呼ばれる。stdin の JSON（`transcript_path`, `session_id`, `reason`）を読み、
要約対象外の reason・subagent セッションを除外し、対象なら summarize.sh を**バックグラウンド起動**して即 `exit 0`。
hook はセッション操作を絶対に妨げない。

- [ ] **Step 1: summarize-session.sh を作成**

```bash
#!/bin/bash
# summarize-session.sh - SessionEnd hook の入口
#
# stdin で受け取る JSON（transcript_path, session_id, reason）を判定し、
# 対象セッションなら summarize.sh をバックグラウンド起動して即座に exit 0 する。
# 要約の成否に関わらず hook は常に成功扱い（セッション操作を妨げない）。
#
# 使用方法（hook から自動）:
#   echo '{"transcript_path":"...","session_id":"...","reason":"..."}' | summarize-session.sh
set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="$HOME/.local/log/claude-summarize.log"
mkdir -p "$(dirname "$LOG_FILE")"

input="$(cat)"
transcript_path="$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null || true)"
session_id="$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null || true)"
reason="$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("reason",""))' 2>/dev/null || true)"

# resume は「続きをやるだけ」なので要約しない
[ "$reason" = "resume" ] && exit 0
# 必須情報が欠けていたら何もしない
[ -n "$transcript_path" ] && [ -n "$session_id" ] || exit 0
[ -f "$transcript_path" ] || exit 0
# subagent セッションは除外（情報はメインに集約済み）
case "$transcript_path" in
  */subagents/*) exit 0 ;;
esac

# 要約をバックグラウンドで起動し、即座に制御を返す
{
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] summarize start: $session_id (reason=$reason)"
  bash "$SCRIPT_DIR/summarize.sh" "$transcript_path" "$session_id"
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] summarize done: $session_id"
} >> "$LOG_FILE" 2>&1 &

exit 0
```

- [ ] **Step 2: 実行権限を付与**

Run: `chmod +x ~/.dotfiles/scripts/claude-summarize/summarize-session.sh`

- [ ] **Step 3: 構文チェック**

Run: `bash -n ~/.dotfiles/scripts/claude-summarize/summarize-session.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: reason=resume が即スキップされるか確認**

Run:
```bash
echo '{"transcript_path":"/nonexistent","session_id":"x","reason":"resume"}' \
  | bash ~/.dotfiles/scripts/claude-summarize/summarize-session.sh; echo "exit=$?"
```
Expected: `exit=0`（何も起動せず即終了）

- [ ] **Step 5: subagent パスが除外されるか確認**

Run:
```bash
echo '{"transcript_path":"/home/aya/.claude/projects/foo/subagents/bar.jsonl","session_id":"x","reason":"clear"}' \
  | bash ~/.dotfiles/scripts/claude-summarize/summarize-session.sh; echo "exit=$?"
```
Expected: `exit=0`（subagent なので起動せず）

- [ ] **Step 6: 実セッションで end-to-end（バックグラウンド要約が走るか）**

Run:
```bash
f=$(find ~/.claude/projects -name "*.jsonl" -mtime -7 | grep -v subagents | head -1)
sid=$(basename "$f" .jsonl)
rm -f ~/.nb/claude/sessions/*/"$sid".md
echo "{\"transcript_path\":\"$f\",\"session_id\":\"$sid\",\"reason\":\"prompt_input_exit\"}" \
  | env -u CLAUDECODE bash ~/.dotfiles/scripts/claude-summarize/summarize-session.sh
echo "hook returned, waiting for background summary..."
sleep 30
cat ~/.nb/claude/sessions/*/"$sid".md 2>/dev/null | head -20
echo "--- log ---"; tail -5 ~/.local/log/claude-summarize.log
```
Expected: hook は即座に返り、30秒後に要約ファイルが生成されている。ログに start/done が記録される。

- [ ] **Step 7: コミット**

```bash
cd ~/.dotfiles
git add scripts/claude-summarize/summarize-session.sh
git commit -m "feat: SessionEnd hook入口のsummarize-session.shを追加"
```

---

### Task 4: SessionEnd hook に登録

**Files:**
- Modify: `.claude-global/settings.json`（`hooks.SessionEnd` 配列に1要素追加）

`~/.claude/settings.json` はこのファイルへのシンボリックリンクなので、編集すれば次回セッションから反映される（Nix switch 不要）。
既存の tmux-agent-sidebar の hook は残し、新しい hook を**追加**する。

- [ ] **Step 1: 現在の SessionEnd 定義を確認**

Run: `python3 -c "import json; print(json.dumps(json.load(open('$HOME/.dotfiles/.claude-global/settings.json'))['hooks']['SessionEnd'], ensure_ascii=False, indent=2))"`
Expected: tmux-agent-sidebar の hook が1つだけ入った配列。

- [ ] **Step 2: summarize-session.sh を SessionEnd に追加**

`.claude-global/settings.json` の `hooks.SessionEnd` 配列（現在は1要素）に、以下の要素を**末尾に追加**する。
Edit ツールで、既存の最後の `}` ブロックの後ろにカンマ区切りで挿入する。

追加するブロック:
```json
    {
      "hooks": [
        {
          "type": "command",
          "command": "~/.dotfiles/scripts/claude-summarize/summarize-session.sh"
        }
      ]
    }
```

追加後の `SessionEnd` は以下の形になる:
```json
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "~/src/github.com/hiroppy/tmux-agent-sidebar/hook.sh claude session-end"
        }
      ]
    },
    {
      "hooks": [
        {
          "type": "command",
          "command": "~/.dotfiles/scripts/claude-summarize/summarize-session.sh"
        }
      ]
    }
  ],
```

- [ ] **Step 3: JSON が壊れていないか検証**

Run: `python3 -c "import json; json.load(open('$HOME/.dotfiles/.claude-global/settings.json')); print('valid JSON')"`
Expected: `valid JSON`

- [ ] **Step 4: SessionEnd に2要素入ったか確認**

Run: `python3 -c "import json; d=json.load(open('$HOME/.dotfiles/.claude-global/settings.json')); print(len(d['hooks']['SessionEnd']), 'entries'); print([h['hooks'][0]['command'] for h in d['hooks']['SessionEnd']])"`
Expected: `2 entries` と、両方の command が表示される。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add .claude-global/settings.json
git commit -m "feat: SessionEnd hookにセッション要約を登録"
```

---

### Task 5: daily-review-auto.sh を要約集約方式に改修

**Files:**
- Modify: `scripts/daily-review/daily-review-auto.sh`

プロンプト内の「会話履歴の収集」を、生ログ（`~/.nb/claude/YYYY-MM-DD.md`）参照から
セッション要約群（`~/.nb/claude/sessions/YYYY-MM-DD/*.md`）の集約に変える。
`claude-nb-sync.py` の実行ステップも削除する（廃止するため）。

- [ ] **Step 1: 要約集約ロジックをスクリプトに追加**

`daily-review-auto.sh` の Rocket Chat 収集の直後（`rocketchat_log=...` の行の後）に、
セッション要約を集約する処理を追加する。`TARGET_DATE` は既に上部で readonly 定義済みなので、
それを使う。Edit ツールで `rocketchat_log=...` 行の直後に以下を挿入:

```bash

# その日のセッション要約を集約（なければプレースホルダ）
sessions_dir="$HOME/.nb/claude/sessions/$TARGET_DATE"
if compgen -G "$sessions_dir/*.md" > /dev/null; then
  session_summaries="$(cat "$sessions_dir"/*.md)"
else
  session_summaries="(本日のセッション要約なし)"
fi
```

- [ ] **Step 2: プロンプトの会話履歴ステップを差し替え**

`daily-review-auto.sh` のプロンプト内、現在の手順6:
```
6. Claude 会話履歴（~/.nb/claude/${TARGET_DATE}.md）を収集
```
を、以下に置き換える:
```
6. Claude 会話履歴は下記【セッション要約】を入力として使う（各セッションが意図/作業内容/結論/編集ファイル/コマンド/ナレッジ候補の6項目で要約済み）。生ログ参照は不要。
```

そして手順1の claude-nb-sync 実行:
```
1. claude-nb-sync.py を実行して最新の会話を同期
```
を削除し、後続番号を繰り上げる（手順2→1, 3→2, ...）。

- [ ] **Step 3: プロンプト末尾にセッション要約ブロックを埋め込む**

プロンプトの `【Rocket Chat 当日履歴（mori.a-times）】` ブロックの後（`${rocketchat_log}` の後の空行）に、以下を追加:

```
【セッション要約（${TARGET_DATE}・プロジェクト別）】
${session_summaries}
```

- [ ] **Step 4: 構文チェック**

Run: `bash -n ~/.dotfiles/scripts/daily-review/daily-review-auto.sh && echo OK`
Expected: `OK`

- [ ] **Step 5: プロンプトに要約が埋め込まれるか dry-run 確認**

Run:
```bash
# claude 実行直前までを確認するため、一時的に PROMPT を echo する形で検証
cd ~/.dotfiles
target_date=$(TZ=Asia/Tokyo date +%Y-%m-%d)
sessions_dir="$HOME/.nb/claude/sessions/$target_date"
ls "$sessions_dir"/*.md 2>/dev/null | head && echo "(要約あり)" || echo "(本日の要約なし=正常な場合あり)"
```
Expected: 要約ファイルがあれば一覧表示。なくてもスクリプトは「(本日のセッション要約なし)」で動く設計。

- [ ] **Step 6: コミット**

```bash
cd ~/.dotfiles
git add scripts/daily-review/daily-review-auto.sh
git commit -m "refactor: daily-review-autoを生ログからセッション要約集約に変更"
```

---

### Task 6: claude-nb-sync.py の廃止

**Files:**
- Modify: crontab（5分ごとの claude-nb-sync.py 行を削除）
- Delete: `scripts/claude-sync/`（ディレクトリごと）
- Delete: `~/.claude/nb-sync-state.json`

生ログ整形は完全廃止。検索が必要なら元 JSONL（`~/.claude/projects/`）を当たる。

- [ ] **Step 1: crontab から claude-nb-sync 行を削除**

Run:
```bash
crontab -l | grep -v "claude-nb-sync" | crontab -
echo "=== 削除後のcrontab ==="; crontab -l
```
Expected: `*/5 * * * * .../claude-nb-sync.py` の行が消え、他の行（nb-sync, claude-prompt, daily-review-auto）は残る。

- [ ] **Step 2: claude-sync スクリプト群を削除**

Run:
```bash
cd ~/.dotfiles
git rm -r scripts/claude-sync/
```
Expected: claude-nb-sync.py, install.sh, README.md が削除ステージに入る。

- [ ] **Step 3: state ファイルを削除**

Run: `rm -f ~/.claude/nb-sync-state.json && echo "removed"`
Expected: `removed`

- [ ] **Step 4: 他に claude-sync を参照している箇所がないか確認**

Run: `grep -rn "claude-nb-sync\|claude-sync" ~/.dotfiles --include="*.sh" --include="*.nix" 2>/dev/null | grep -v ".git/"`
Expected: 出力なし（daily-review-auto.sh からも参照が消えていること）。残っていたら該当箇所を修正。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git commit -m "chore: claude-nb-sync.py（生ログ整形）を廃止"
```

---

### Task 7: 統合動作確認と push

**Files:** なし（検証のみ）

- [ ] **Step 1: 新規セッションで SessionEnd hook が要約を生成するか確認**

このセッションとは別に、新しい Claude Code セッションを起動して何か会話し、`/exit` で終了する。
その後（数十秒待って）:
```bash
today=$(TZ=Asia/Tokyo date +%Y-%m-%d)
ls -la ~/.nb/claude/sessions/"$today"/ 2>/dev/null
tail -10 ~/.local/log/claude-summarize.log
```
Expected: 終了したセッションの `<session_id>.md` が生成され、ログに start/done が記録されている。

- [ ] **Step 2: daily-review-auto.sh を手動実行（ユーザー自身が実行）**

`--dangerously-skip-permissions` を含むため、ユーザーがプロンプトで実行する:
```
! env -u CLAUDECODE bash ~/.dotfiles/scripts/daily-review/daily-review-auto.sh
```
その後ログ確認:
```
! tail -60 ~/.local/log/daily-review-auto.log
```
Expected: セッション要約を集約したサマリーが生成され、日報 Issue が更新される。生ログ参照のエラーが出ないこと。

- [ ] **Step 3: 全コミットを push**

```bash
cd ~/.dotfiles
git push
```
Expected: `main` がリモートに反映される。

---

## 実装順序と依存

Task 1（extract）→ Task 2（summarize、extract に依存）→ Task 3（hook 入口、summarize に依存）→
Task 4（hook 登録、summarize-session に依存）→ Task 5（daily-review 改修、sessions/ 出力に依存）→
Task 6（廃止）→ Task 7（統合確認）。

Task 1〜3 は各々単体テスト可能。Task 4 で初めて実セッションに繋がる。
Task 6 の廃止は Task 5 完了後（daily-review が要約方式に切り替わってから）に行うこと。
