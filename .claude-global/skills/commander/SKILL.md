---
name: commander
description: 司令塔。todo（~/memo/todo.md）と待ち中の引き継ぎメモ（/handoff）を丸ごと読み、残りの作業を優先度別に理由付きで出し、起動する場所と打つプロンプトを付け、頼まれたら作業ごとに tmux セッションを立てて Claude を起動する。「/commander」「司令塔」「残りを全部出して、やる順番を提案して」「返ってきたもの有る？」「〇〇のセッションを起動して」「〇〇終わった」「〇〇止まった」「来週分も出して」等で使う。
---

# commander（司令塔）

Claude のセッションを開きっぱなしで放っておかないための入口。自分では作業せず、起動して最初のプロンプトを打つところまでをやる。

- 材料: todo（全タスクの概要）・待ち中の引き継ぎメモ（相手のボールの詳細）・PR/issue の状態
- 司令塔ファイル: `~/memo/commander/<YYYY-MM-DD>.md`。その日最初に開いたら前の日のファイルを材料に作り直し、日中は更新する。前の日のファイルは消さない
- 中身は古くなる前提。一覧を出す前に必ず一次情報と照らす（引き継ぎメモの「まだ」はよく古くなっている）

決定的な処理はスクリプト（`~/.claude/skills/commander/scripts/`）がやる。Claude は並べ方・理由・文章と、MCP でしか見られないもの（GitBucket・Rocket Chat・メール）の確認をやる。

## スクリプト

```bash
S=~/.claude/skills/commander/scripts
python3 -I $S/collect.py                       # 材料（todo・引き継ぎメモ・祝日・ファイルの場所・tmux）
python3 -I $S/carry.py --prev <前の日のファイル>  # 引き継ぐ欄を写して掃除
echo '[{"ref":"epc#1308","since":"2026-11-20T18:22:00+09:00"}]' | python3 -I $S/check_waits.py   # GitHub の返ってきた判定
```

- `collect.py` の出力: `today`・`range_end`（14日先）・`holidays`・`files`（`today`・`today_exists`・`previous`）・`todo`（`section`・`ref`・`title`・`next`・`location`・`handoffs`）・`confirm_lines`・`handoffs`（`path`・`summary`・`since`・`refs`・`location`・`todo_refs`）・`tmux_sessions`（`null` は tmux の一覧を取れなかった）・`warnings`
- `carry.py` の出力: `section`（そのまま貼る `## 引き継ぐ欄`）・`removed_tmux`・`removed_done`・`done_still_in_todo`・`unparsed_done`
- `check_waits.py` には各引き継ぎメモの `refs` を、そのメモの `since` と組にして渡す。`returned` が `true`（返ってきた）・`false`・`null`（`kind` が `gitbucket` なら MCP で、`other` なら手で確かめる）
- `warn:` は stderr。出たらユーザーに一言伝える

## 司令塔ファイルの書式

```markdown
# 司令塔 2026-11-24（火）

## 祝日と期限
<holidays と引き継ぐ欄の期限を日付順の表に>

## 引き継ぐ欄
### 期限
- 2026-11-25 シフトオン 先方への修正版の期限
### 済んだこと
- 2026-11-24 RDP で本番 00010 に MSD 登録 [ref:title:AI参考情報 指示2項目の本番登録・配置]
### 作業中の tmux セッション
- pilot-p11: P.11 マージ→検証環境→実機確認
### メモ
- 11/24 #1321 は辻本さんが対応中なので後回し

## 一覧
### 最優先
### 高
### 中
### 低
### 返事待ち

## 同じ場所を使うときの注意
```

- `## 引き継ぐ欄` は `carry.py` が次の日へ写す。ここにしか無い情報（その日の判断・作業中の tmux セッション・貼られたチェックリスト・決めることの経緯）は必ずこの欄に書く。ほかの章は毎日作り直す
- 済んだことの行は `- <YYYY-MM-DD> <内容> [ref:<todo の ref>]`。ref は collect の `todo[].ref`（キーが無い行は `title:<タイトル>`）。todo に無いものは ref を付けない
- tmux の行は `- <セッション名>: <内容>`

## 手順

### 1. 開いたとき

1. `collect.py` を流す
2. `files.today_exists` が false（その日最初）:
   - `files.previous` があれば `carry.py --prev <previous>`。無ければ「最初の1回」（下）
   - 書式どおりに今日のファイルを作る。期限は todo の `next`（「（11/25）」等）・引き継ぎメモ本文・貼られたチェックリストから拾って、引き継ぐ欄の「期限」に足す
3. `files.today_exists` が true: 今日のファイルを読み、collect の結果で古いところを直す（増えた todo・増えた引き継ぎメモ・消えたもの）
4. 一覧を出す前に照合する:
   - `check_waits.py` で GitHub の待ちを確かめる
   - `kind: gitbucket` は `mcp__gitbucket__gitbucket_get_pr` と `mcp__gitbucket__gitbucket_list_comments` で確かめる（`since` より後の相手のコメント・マージ）
5. carry の結果を1行ずつ伝える: `removed_tmux`（閉じたセッションを外した）・`removed_done`（todo から消えたので外した）・`done_still_in_todo`（「todo 側も `/todo-edit` で閉じる？」）・`unparsed_done`（ref が無い）
6. 引き継ぐ欄の「メモ」で古そうな行は「消してええ？」とまとめて聞き、OK のものだけ消す
7. 照合で待ちが済んでいる（マージ・クローズ済み）のに `status: blocked` の引き継ぎメモは、`status: resolved` にしてよいか聞く
8. ファイルを保存し、一覧を出す

### 2. 一覧の出し方

- 段: **最優先**（期限当日に直接かかわる）／**高**（その前に済ませたい）／**中**（今週中・期限あり）／**低**（期限なし）／**返事待ち**
- 段の中は、期限 → ほかの作業を止めているか → 同じ場所を使うか、の順で並べる
- 各項目に「理由（一言）」「今の状態（動ける／誰の何待ちか）」「起動する場所」「打つプロンプト」
  - 引き継ぎメモがある項目: 場所はメモの `location`、プロンプトは `/pickup <キー>` にユーザーの言葉を足す
  - 場所だけ分かる項目（todo の `location`）: 場所と、次にやること（`next`）を言い換えたプロンプト
  - `rc:` や参照の無い行: 概要だけ
- 同じ場所を使う項目を同時に開くと困るときは、表の下に注意（ブランチを切り替えない・worktree を切る等）
- 説明は論点を先に並べ、前置きを重ねない

### 3. 「返ってきたもの有る？」

1. 「開いたとき」の照合（GitHub・GitBucket）をやり直す
2. Rocket Chat: 引き継ぎメモ・todo の部屋リンク（DM は `/direct/<rid>`）から部屋を特定し、`mcp__rocketchat__get_channel_history` を `oldest=<since>` で取る。部屋が分からなければ相手のユーザー名で `mcp__rocketchat__list_channels`（表示名では見つからないことがある）
3. メール: `mcp__thunderbird__search_messages` を差出人（相手）と `after=<since の日付>` で絞る。GitHub の通知メール（`notifications@github.com`）は外す
4. 取るのは `since` 以降の相手の発言だけ。要約して出す。履歴を丸ごと出したりファイルに書いたりしない（DM に API キー等が貼られていることがある）
5. 課題DB で返事が来る待ちは「どこを見ればよいか」だけ出す
6. MCP がつながらなければ「Rocket Chat は見られなかった（`/mcp` でつなぎ直せる）」と出して続ける
7. 返ってきたものを、再開のプロンプト付きで出す

### 4. 「〇〇終わった」「〇〇止まった」

- 終わったもの: 引き継ぐ欄の「済んだこと」に `[ref:…]` 付きで足し、一覧から外す。todo には書かない（翌朝の `/todo` に任せる）
- 止まったもの: 状態を書き換える。理由があれば引き継ぐ欄の「メモ」に
- 引き継ぎメモの待ちが済んだなら `status: resolved` にしてよいか聞く
- ファイルを保存し、一覧を出し直す

### 5. 「〇〇のセッションを起動して」

agent-memory `user-preferences/commander-launch-tmux-sessions.md` の手順と罠に従う。要点:

```bash
s=<場所-課題番号>; d=<起動する場所>; p="<プロンプト>"
tmux new-session -d -s "$s" -c "$d"
tmux send-keys -t "$s" -l "claude '$p'"; tmux send-keys -t "$s" Enter
```

- zsh では `"${s}:tmp"` と書く（`"$s:tmp"` は `:t` 修飾子で壊れる）
- 起動後に `tmux capture-pane -p -t "$s"` で確かめる。「このフォルダを信頼しますか」で止まっていたら、Yes を選ぶようユーザーに伝える（既定の選択は「No, exit」。こっちから押さない）
- 動いているセッション（ユーザーが触ったもの）を kill しない。置き場所を変えるときは move-window
- 起動したら引き継ぐ欄の「作業中の tmux セッション」に足す

### 6. 「来週分も出して」

`range_end`（14日先）までの期限と祝日を使い、来週の月〜金に効くものを一覧に足す。

## 最初の1回

`files.previous` が無く `~/memo/weekly-plan-*.md` があれば、そのうち最新のものから、その日の判断・作業中の tmux セッション・貼られたチェックリスト・期限の表を引き継ぐ欄へ手で移す。どちらも無ければ空の引き継ぐ欄で始める。

## やらないこと

- todo.md を書き換える・`/todo-edit` を呼ぶ（todo の反映は翌朝の `/todo`）
- 外部アクション（PR コメント・マージ・Rocket Chat 送信・メール送信）。起動先のセッションでユーザーが承認する
- 頼まれていない作業のセッションを起動する
- 自分で作業する
- ボールが返ってきたことを通知する（気づくのはユーザー。聞かれたら見に行く）
