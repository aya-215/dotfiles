---
name: handoff
description: 誰かの判断待ち（PR のレビュー・マージ待ち、営業さんの作業待ち、課題DB の確認待ち等）になったセッションの状態を、引き継ぎメモとして agent-memory に残す。ユーザーはこのあとセッションを消し、返事が来たら新しいセッションで /pickup して再開する。「/handoff」「引き継ぎを書いて」「引き継ぎ残して」等で使う。再開側は pickup スキル。
---

# handoff

## Overview

今のセッションの「待っているもの・状態・決めたこと・次にやること」を、新しいセッションがすぐ続きを始められる形で残す。
決まった事実（作業場所・ブランチ・PR・セッション ID・日時）はスクリプトと置換で集め、Claude は文章だけを書く。

## 手順

1. 事実を集める:
   ```bash
   bash ~/.claude/skills/handoff/scripts/collect.sh
   ```
   `cwd` / `remote` / `branch` / `pr_url` / `pr_number` / `created` が出る。GitHub の PR はここで取れる。
   `remote` が GitBucket なら、`mcp__gitbucket__gitbucket_list_prs` でこのブランチの PR を探して URL を控える（無ければ空でよい）。
2. このセッションの ID は `${CLAUDE_SESSION_ID}`。
3. 引き継ぎメモを書く。置き場所は `~/.claude/skills/agent-memory/memories/work-in-progress/handoff-<YYYYMMDD-HHMM>-<英数字の短い slug>.md`（日時は `created` から）。既存ファイルは上書きしない。

   ```markdown
   ---
   summary: "<題名>。<誰の何を待っているか>。<PR 番号・課題No などの番号>"
   created: <YYYY-MM-DD>
   status: blocked
   tags: [handoff, <リポジトリ名>]
   ---

   # <題名>

   ## 待っているもの
   <誰の、何の返事・作業か。どこに届くか（PR・課題DB・Rocket Chat・メール）>

   ## 今の状態
   <どこまで終わっているか。コミット・ブランチ・PR の状態>

   ## 決めたことと理由
   <このセッションで決めたことと、その理由。再開後に「なぜ？」と聞かれて答えられるように>

   ## 次にやること
   <返事が来たらやること。返事の内容で分岐するなら分岐ごとに>

   ## 関連
   - PR: <pr_url（無ければ省く）>
   - 課題DB: <No0000xxxx など（あれば）>
   - スレッド・メール: <あれば>

   ## 元のセッション
   - 作業場所: <cwd>（ブランチ <branch>）
   - 文脈が足りなければ: `cd <cwd> && claude --resume <セッションID>`
   ```

   - PR の URL・課題No・スレッド URL は本文にそのまま書く（`/pickup` は本文全体を番号や言葉で探す）
   - 決めたことの理由は省かない。要約で一番抜けやすく、再開後に作業をやり直す原因になる
4. ユーザーに、書いたファイルのパスと題名を示し、「このセッションは消してよい。返事が来たら新しいセッションで `/pickup <PR番号など>`」と伝える。
