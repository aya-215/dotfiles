---
name: todo
description: 業務TODO（~/memo/todo.md）を一次データから AI が更新する。GitHub 同期 → /my-tasks の JSON 収集 → 台帳と突き合わせた変更案 → apply.py で適用。「/todo」「TODO更新」「todo を最新にして」「確認待ちに答えたから反映して」等で使用。cron の `claude -p "/todo"` からも無人で回る。
---

# /todo

`~/memo/todo.md` を、一次データ（`/my-tasks` の収集結果・GitHub・GitBucket）に合わせて更新する。
書き込みは `apply.py` だけが行う。Claude は変更案 JSON を作るだけで、todo.md を直接編集しない。

**質問しない。** 無人実行（`claude -p "/todo"`）でも同じ手順で最後まで走る。迷ったら「何もしない」か「確認待ちに出す」側に倒す。AskUserQuestion は使わない。

## やらないこと

- todo.md・`todo-decisions.jsonl`・`todo-archive/` を Edit/Write で直接書く（書くのは apply.py だけ）
- 外部アクション（PR/Issue コメント、Rocket Chat 送信、Issue 作成、`mcp__gitbucket__` の書き込み系）
- 過去の実行ログ（`~/.local/log/todo-ai/` の今日以外）・過去の `/my-tasks` 出力を読む。AI の過去の推測が事実として戻ってくるため
- todo.md をタスクの根拠にする。台帳は重複検出と人の行の把握にだけ使い、それも context.json 経由で見る
- 人が完了にした行を未完了に戻す・人の行のタイトルを書き換える（apply.py も止めるが、案にも入れない）

## 準備

以下、`T=~/.dotfiles/scripts/todo-ai`、`L=~/.local/log/todo-ai/<今日 YYYY-MM-DD>`。シェルの変数は呼び出しをまたいで残らないので、各コマンドで書き直す。

```bash
mkdir -p ~/.local/log/todo-ai/$(date +%F)
```

台帳の場所は `TODO_MD_PATH`（未設定なら `~/memo/todo.md`）。スクリプトは全部これに従うので、引数で渡さない。

## 手順

### 1. GitHub 同期

```bash
L=~/.local/log/todo-ai/$(date +%F); python3 -I ~/.dotfiles/scripts/todo-ai/sync_github.py >$L/sync.out 2>$L/sync.err; echo "exit=$?"
```

0 以外でも止めない（同期できなかった行は動かないだけ）。終了コードと `sync.err` の要点を最後の報告に入れる。

### 2. /my-tasks を JSON モードで収集（サブエージェント）

先に今日の古い出力を消す（同じ日の2回目の実行で前回の結果を読まず、手順5の Write が既存ファイルで失敗しないため）。

```bash
rm -f ~/.local/log/todo-ai/$(date +%F)/my-tasks.json ~/.local/log/todo-ai/$(date +%F)/changes.json
```

Agent ツール（`subagent_type: general-purpose`）で次を依頼する。収集は約50k tokens・8分かかるので、メインの文脈に入れない。`<L>` は展開した絶対パスで書く。

> Skill ツールで `my-tasks` を args `--json <L>/my-tasks.json` で起動し、SKILL.md の「JSON 出力モード」に従って `<L>/my-tasks.json` の1ファイルだけを書いてください。`~/memo/todo.md`、`~/.local/log/todo-ai/` 配下（いま書くファイル以外）、過去の /my-tasks 出力は読まないこと。外部アクション（コメント・送信・Issue 作成）はしないこと。質問はせず最後まで実行し、返答は件数（mine/theirs/maybe_done）と、取得できなかったデータ源だけにしてください。

戻ったら検証する。

```bash
L=~/.local/log/todo-ai/$(date +%F); python3 -I ~/.dotfiles/scripts/todo-ai/my_tasks_schema.py $L/my-tasks.json >$L/my-tasks.validate.txt; echo "exit=$?"; cat $L/my-tasks.validate.txt
```

0 以外（ファイルが無い・形が違う）なら **ここで止める**。適用はせず、検証エラーを報告して終わる。

### 3. 台帳の材料を作る

```bash
L=~/.local/log/todo-ai/$(date +%F); python3 -I ~/.dotfiles/scripts/todo-ai/context.py >$L/context.json 2>$L/context.err; echo "exit=$?"; cat $L/context.err
```

0 以外なら止めて `context.err` を報告する（`見出しが足りない` 等なら todo.md が新形式でない。`migrate.py` が要る旨を添える）。

`context.json` の中身（数えたり読み取ったりを Claude がやり直さない。ここに出ている値を使う）:

| フィールド | 使い方 |
|---|---|
| `items[]` | 台帳の各行。`ref` `section` `title` `key` `url` `next` `done` `origin`（ai/human）`added_date` `age_days` `pinned` |
| `confirm_blocks[]` | 今の確認待ち。`ref` `kind` `question`（タグを外した問い）`facts` `options` `answer` |
| `confirm_errors[]` | 確認待ちを書き換えられない理由。空でなければ下の「確認待ちが壊れているとき」 |
| `answered_now[]` | 回答欄が埋まった分（ref, kind, answer）。apply が回答欄から同じものを記録する。Claude はこれを見て回答に沿った op を作る |
| `answered_refs[]` | 判断記録にある過去の回答（ref, kind, value）。同じ ref・kind の問いは出さない |
| `rejected_refs[]` | 人が消した AI の追加。この key は二度と `add` しない |
| `archived_keys[]` | 30日でアーカイブされた完了行の key。完了済みなので `add` しない |

`my-tasks.json` と `context.json` だけを読んで次へ進む。todo.md 本体は読まない（最後の報告で適用後の確認待ち欄を見るときだけ読む）。

### 4. GitBucket の状態（読み取りのみ）

`items` のうち `section` がやる/待ちで `key` が `gb:` の行（`pinned` は除く）は、`url` から owner/repo/番号を取り、`mcp__gitbucket__gitbucket_get_pr`（`/pull/`）または `mcp__gitbucket__gitbucket_get_issue`（`/issues/`）で状態を見る。マージ済み・クローズなら `move → 完了`（reason に状態と URL）。取れなかった・ツールが無いときは動かさず、報告に「GitBucket 未確認」と書く。書き込み系の gitbucket ツールは呼ばない。

### 5. 変更案を作る

`~/.local/log/todo-ai/<今日>/changes.json` に書く。形は次のとおり（`source` は常に `"ai"`）。

```json
{"source": "ai",
 "ops": [{"op": "add", "section": "やる", "key": "epc#1163", "url": "https://...", "title": "...", "next": "...", "reason": "..."}],
 "confirm": [{"ref": "...", "kind": "...", "question": "...", "facts": "...", "options": [{"label": "A", "text": "...", "recommended": true}]}]}
```

- op は `add` / `move` / `set_next` / `attach` / `order`。各 op の `reason` に根拠（候補の `evidence` の引用・URL）を書く。apply がコミット本文に残す
- `ref` は行の `key`、key の無い行は `title:<タイトル完全一致>`。`context.json` の `ref` をそのまま使う
- 候補と台帳の突き合わせは **key の完全一致**（`items` の全セクション、完了も含む）

#### 規則

以下の「候補」は `my-tasks.json` の `candidates[]`、「行」は `context.json` の `items[]`。

1. **add**: `key` と `url` が両方ある `mine`/`theirs` の候補で、同じ key の行が無く、`rejected_refs` にも `archived_keys` にも無く、`answered_refs` にその key の回答が（kind を問わず）無いもの。`mine`→`やる`、`theirs`→`待ち`。`title`・`next` は候補の値（改行を入れない）。ただし規則 4 の attach に当たるなら add しない
2. **move → 完了**: `maybe_done` の候補で、同じ key の行がやる/待ちにあり、`evidence` に決着（マージ・クローズ・「対応しました」・送信済み等）が読めるもの。決着が読めなければ動かさない
3. **move やる⇄待ち**: 候補の `ball`（mine/theirs）と行の section が食い違うとき。`pinned: true` の行は 2・3 とも動かさない（人が戻した行と取り合わない）
4. **attach**: `key` が null の行（やる/待ち）と、同じ作業だと言い切れる候補（`key` と `url` あり、その key の行がまだ無い）。行の `next` が null のときだけ候補の `next` も付ける。言い切れなければ何もしない
5. **set_next**: 行の `next` と候補の `next` が違うとき。ただし `origin: human` で `next` が既にある行は上書きしない。自分の PR に未対応のレビュー指摘があるときの next は `N1,N2 残` の形で始める
6. **still_needed**: やる/待ちの行で、key が `rc:` か `mail:` で始まり、`age_days` が 14 より大きく（null は対象外）、同じ key の候補が今回の `my-tasks.json` に無く、`answered_refs` に `(ref, still_needed)` が無いもの。ただし `my-tasks.json` の `sources_failed` に `rocketchat` があれば `rc:` の行、`mail` があれば `mail:` の行には適用しない（取れなかったことを「進展なし」と扱わない） → `confirm kind=still_needed`（選択: 要る / 不要＝完了にする）
7. **is_task**: `key` が null の候補（ball を問わない）、または `key` はあるが `url` が null の候補（`wt:` 等。apply は url の無い key を受け付けない）で、同じ作業の行が無いもの → `confirm kind=is_task`。ref は key があれば key、無ければ `title:<候補の title>`。`answered_refs` に同じ ref の is_task があれば出さない。ref の表記が違っても同じ作業への回答が `answered_refs` にあれば出さない
8. **conflict**: 完了にある行と同じ key の候補が `mine`/`theirs`（元がまだ開いている）→ `confirm kind=conflict`。選択は「完了のまま（おすすめ）」と「自分でやるに戻す」。**AI は完了から動かせない**ので、戻す op は作らない
9. **order**（やる）: 並べ替え後の順を `{"op": "order", "section": "やる", "refs": [...]}` で出す。順位は ① 対応する候補に `waiting_person` がある ② `deadline` が早い（null は後）③ `blocks` が多い ④ 元の順。候補の無い行は元の順のまま後ろ。**refs は前の op を適用した後の ref**（attach した行は付けた key、add した行はその key）。順が変わらなければ出さない
10. **policy / before_share / manual**: 候補の next が「方針を決める」「人に見せる前の確認」「ユーザーにしかできない手作業」のときだけ。多用しない

#### 確認待ちの書き方

- `question` は「決めること」を1行で書く。`ref` と `kind` は必須。kind は `policy` `before_share` `manual` `conflict` `is_task` `still_needed` のどれか。apply が問いの末尾に ` [<kind> <ref>]` のタグを付け、次の実行はこのタグで回答の記録先を決める。タグを自分で書かない
- `facts` は判断に要る事実だけ（件数・日付・状態）。推測を書かない
- `options` は 2〜3 個、`label`（A/B/C）と `text` は空にしない。`recommended: true` はちょうど1つ
- `confirm` は毎回全置換。次の順で並べる: ① `confirm_blocks` のうち `answer` が空のものを `ref` `kind` `question` `facts` `options` そのまま写す（状況が片付いた問いは落としてよい）② 今回新しく出す問い

#### 回答の反映

- 回答の記録は apply が回答欄とタグから行う。`answered` キーは入れない（入れる場合は `answered_now` と完全に一致しないと exit 2）
- 回答したブロックは `confirm` に写さない
- 回答の内容に沿った op を作る（例: still_needed に「不要」→ `move → 完了`、is_task に「追加」→ `add`（`section` はやる。候補に `url` が無ければ `key` も入れず `title` だけ。`wt:` も同じ））。回答が読み取れない自由文なら op は作らず、記録だけして報告に書く

#### 確認待ちが壊れているとき（`confirm_errors` が空でない）

人が確認待ちの問い・事実・選択を書き換えた、または自由文を書いた状態。`confirm` を含めると apply は人が直すまで毎回 exit 2 で止まる。

- changes.json に `confirm` の **キーを入れない**（確認待ち欄はそのまま残り、回答も記録されない）
- 回答に基づく op も作らない
- それ以外の op はいつもどおり作って適用する
- `confirm_errors` の文言をそのまま報告に入れ、直し方を添える: 問い・事実・選択の書き換えや自由文なら「apply が書いた形に戻すか、そのブロックを消してください」、`タグが無い` なら「そのブロックを消してください」（記録先が分からないため）

#### apply が全体を止める書き方（1つでもあると何も書かれない）

- 完了にある行への `move`
- `add` の `section` がやる/待ち以外、`key` があるのに `url` が null、key の形式違い（`epc#N` `emm#N` `eae#N` `eas#N` `gb:<repo>#N` `rc:<id>` `rc:<id>#N` `mail:<id>` `wt:<name>`）
- どの文字列にも改行を入れる
- `title`・`next` に ` — next: ` や `](` を含める、`title` の前後に空白がある、`url` に空白や括弧がある（書き出すと別の行に読めてしまうため全体が止まる）
- `options` の要素に `label`/`text` が無い・空、`confirm` の要素に `ref` が無い・`kind` が上の6種以外

存在しない ref への op は apply がその op だけ飛ばす（`skip:` としてコミット本文に残る）。

### 6. 適用

```bash
L=~/.local/log/todo-ai/$(date +%F); R=$(dirname "${TODO_MD_PATH:-$HOME/memo/todo.md}"); git -C "$R" rev-parse HEAD >$L/head-before.txt; python3 -I ~/.dotfiles/scripts/todo-ai/apply.py --changes $L/changes.json >$L/apply.out 2>$L/apply.err; echo "exit=$?"; cat $L/apply.err
```

| 終了コード | 意味 | すること |
|---|---|---|
| 0 | 適用した（変更なしを含む） | 報告へ |
| 3 | todo.md を nvim で編集中、または実行中に変わった | 「編集中のためスキップ（次回に反映）」と報告して終わる。やり直さない |
| 2 | 検証違反。何も書いていない | `apply.err` の全文を報告して終わる。同じ案で再実行しない |
| 1 | その他のエラー | `apply.err` を報告して終わる |

exit 2 で `確認待ちの問い・事実・選択が apply の書いた内容と違う` が出た場合も、再試行せず文言をそのまま伝える（人が戻すまで止まり続ける）。

## 報告（最後のチャット出力）

短く、次だけを出す。

1. 結果: 適用 / 変更なし / スキップ（編集中）/ 違反で未適用 / 収集失敗
2. op の種類ごとの件数: exit 0 で HEAD が `head-before.txt` から変わり、かつ `git -C <台帳のディレクトリ> log -1 --format=%s` の件名が `todo(ai): ` で始まるときだけ、その件名を出す（apply の集計、飛ばした op を除く）。それ以外（HEAD が同じ、人の未コミット分だけが `todo: ` でコミットされた等）は「AI の変更なし」と書き、changes.json の件数を「案」として添える
3. 新しい確認待ち: exit 0 なら適用後の todo.md の `## 確認待ち` 欄（番号・問い・おすすめ）。それ以外は「変更なし」
4. 違反・警告: `apply.err`、`confirm_errors`、同期の失敗、GitBucket 未確認、my-tasks で取れなかったデータ源

ログは `~/.local/log/todo-ai/<今日>/`（sync.out/err, my-tasks.json, context.json, changes.json, apply.out/err）。
