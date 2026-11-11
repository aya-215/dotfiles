---
name: todo
description: 業務TODO（~/memo/todo.md）を一次データから AI が更新する。GitHub 同期 → /my-tasks の JSON 収集 → 台帳と突き合わせた変更案 → apply.py で適用。「/todo」「TODO更新」「todo を最新にして」「確認待ちに答えたから反映して」等で使用。平日朝に cron（scripts/todo-ai/run-unattended.sh）から `claude -p "/todo"` で無人実行もされる。
---

# /todo

`~/memo/todo.md` を、一次データ（`/my-tasks` の収集結果・GitHub・GitBucket）に合わせて更新する。
書き込みは `apply.py` だけが行う。Claude は変更案 JSON を作るだけで、todo.md を直接編集しない。

**質問しない。** 無人実行（`claude -p "/todo"`）でも同じ手順で最後まで走れるようにする。迷ったら「何もしない」か「確認待ちに出す」側に倒す。AskUserQuestion は使わない。

## やらないこと

- todo.md・`todo-decisions.jsonl`・`todo-archive/` を Edit/Write で直接書く（書くのは apply.py だけ）
- 外部アクション（PR/Issue コメント、Rocket Chat 送信、Issue 作成、`mcp__gitbucket__` の書き込み系）
- 過去の実行ログ（`~/.local/log/todo-ai/` のうち今回の `<RUN>` 以外のファイル）・過去の `/my-tasks` 出力を読む。AI の過去の推測が事実として戻ってくるため（例外は `review` モードの review.py だけ）
- todo.md をタスクの根拠にする。台帳は重複検出と人の行の把握にだけ使い、それも context-<RUN>.json 経由で見る
- 人が完了にした行を未完了に戻す・人の行のタイトルを書き換える（apply.py も止めるが、案にも入れない）
- ユーザーの意図（context の `intents`）に反して行を完了・移動する、next を上書きする。人が `/todo-edit` で消した行（`deleted_refs`）を足し直す

## 準備

以下、`L=~/.local/log/todo-ai/<今日 YYYY-MM-DD>`。シェルの変数は呼び出しをまたいで残らないので、各コマンドで書き直す。

```bash
mkdir -p ~/.local/log/todo-ai/$(date +%F) && date +%H%M%S
```

出力された6桁がこの実行の `<RUN>`。以降のコマンドの `<RUN>` はその値に置き換えて書く。ログが実行ごとに別ファイルになるので、同じ日の前回の結果を読まず、上書きもしない（`review.py` は `changes-<RUN>.json` 等を時刻順に読む）。

台帳の場所は `TODO_MD_PATH`（未設定なら `~/memo/todo.md`）。スクリプトは全部これに従うので、引数で渡さない。

## 手順

### 1. GitHub 同期

```bash
L=~/.local/log/todo-ai/$(date +%F); python3 -I ~/.dotfiles/scripts/todo-ai/sync_github.py >$L/sync-<RUN>.out 2>$L/sync-<RUN>.err; echo "exit=$?"
```

0 以外でも止めない（同期できなかった行は動かないだけ）。終了コードと `sync-<RUN>.err` の要点を最後の報告に入れる。

### 2. 台帳を読めるか確かめる

収集（手順3）は約8分かかるので、todo.md が壊れているならその前に止める。

```bash
L=~/.local/log/todo-ai/$(date +%F); python3 -I ~/.dotfiles/scripts/todo-ai/context.py >$L/context-<RUN>.json 2>$L/context-<RUN>.err; echo "exit=$?"; cat $L/context-<RUN>.err
```

0 以外なら止めて `context-<RUN>.err` を報告する（`見出しが足りない` 等なら todo.md が新形式でない。`migrate.py` が要る旨を添える）。ここでは出力の中身は読まない（手順4で作り直したものを読む）。

### 3. /my-tasks を JSON モードで収集（サブエージェント）

Agent ツール（`subagent_type: general-purpose`）で次を依頼する。収集は約50k tokens・8分かかるので、メインの文脈に入れない。`<L>` は展開した絶対パスで書く。

> Skill ツールで `my-tasks` を args `--json <L>/my-tasks-<RUN>.json` で起動し、SKILL.md の「JSON 出力モード」に従って `<L>/my-tasks-<RUN>.json` の1ファイルだけを書いてください。`~/memo/todo.md`、`~/.local/log/todo-ai/` 配下（いま書くファイル以外）、過去の /my-tasks 出力は読まないこと。外部アクション（コメント・送信・Issue 作成）はしないこと。質問はせず最後まで実行し、返答は件数（mine/theirs/maybe_done）と、取得できなかったデータ源だけにしてください。

戻ったら検証する。

```bash
L=~/.local/log/todo-ai/$(date +%F); python3 -I ~/.dotfiles/scripts/todo-ai/my_tasks_schema.py $L/my-tasks-<RUN>.json >$L/my-tasks-<RUN>.validate.txt; echo "exit=$?"; cat $L/my-tasks-<RUN>.validate.txt
```

0 以外（ファイルが無い・形が違う）なら **ここで止める**。適用はせず、検証エラーを報告して終わる。

### 4. 台帳の材料を作る

収集の間に人が todo.md を触っていてもよいように、手順2と同じコマンドで作り直す。

```bash
L=~/.local/log/todo-ai/$(date +%F); python3 -I ~/.dotfiles/scripts/todo-ai/context.py >$L/context-<RUN>.json 2>$L/context-<RUN>.err; echo "exit=$?"; cat $L/context-<RUN>.err
```

0 以外なら止めて `context-<RUN>.err` を報告する。

`context-<RUN>.json` の中身（数えたり読み取ったりを Claude がやり直さない。ここに出ている値を使う）:

| フィールド | 使い方 |
|---|---|
| `items[]` | 台帳の各行。`ref` `section` `title` `key` `url` `next` `done` `origin`（ai/human）`added_date` `age_days` `pinned_to`（人が AI/同期の移動を戻したため、その行を移してはいけないセクション。空なら制限なし）`intents`（ユーザーが `/todo-edit` で残したその行の意図。新しい順で最大5件の `{ts, value}`。下の「意図の扱い」）`answers`（その行への確認待ちの回答。新しい順の `{kind, value, ts, superseded}`）。`pinned_to`・`intents`・`answers` は、key を付ける前・改名する前の ref の記録も含む |
| `intent_refs[]` | 意図の記録がある全 ref（改名前の ref、todo.md から消えた行も含む）。意図の中身は `items[].intents` と `other_intents` で読む |
| `deleted_refs[]` | ユーザーが `/todo-edit` の delete で消した ref と、edit_title で変わる前の ref。**足し直さない**（apply も source ai の add/attach を `skip: intent_deleted` で飛ばす）。人が書き戻して台帳にある ref は入らない |
| `other_intents[]` | 台帳に行が無く（key 付け・改名で今の行につながる旧 ref も除く）`deleted_refs` にも無い ref の意図（`{ref, intents}`。まだ台帳に無い key へのメモ等）。その ref の候補を扱うときに意図として従う |
| `confirm_blocks[]` | 今の確認待ち（回答済みのものも含む）。`ref` `kind` `question`（タグと末尾の（事実）を外した問い）`facts` `options` `answer`。旧書式（4行）のブロックも同じ形で出る |
| `confirm_errors[]` | 確認待ちを書き換えられない理由。空でなければ下の「確認待ちが壊れているとき」 |
| `answered_now[]` | 回答欄が埋まった分（ref, kind, answer, superseded）。apply が回答欄から同じものを記録する。Claude はこれを見て回答に沿った op を作る。`superseded: true` は問いを書いた後に同じ行の意図が記録された conflict の回答で、従わない |
| `answered_refs[]` | 判断記録にある過去の回答（ref, kind, value, ts, superseded）。同じ ref・kind の問いは出さない（`superseded: true` の conflict は除く） |
| `rejected_refs[]` | 人が消した AI の追加（まだ記録されていない分も含む）。この key は二度と `add`・`attach` しない |
| `archived_keys[]` | 30日でアーカイブされた完了行の key。完了済みなので `add` しない |

`my-tasks-<RUN>.json` と `context-<RUN>.json` だけを読んで次へ進む。todo.md 本体は読まない（最後の報告で適用後の確認待ち欄を見るときだけ読む）。

### 5. GitBucket の状態（読み取りのみ）

`items` のうち `section` がやる/待ちで `key` が `gb:` の行（`pinned_to` に `完了` がある行は除く）は、`url` から owner/repo/番号を取り、`mcp__gitbucket__gitbucket_get_pr`（`/pull/`）または `mcp__gitbucket__gitbucket_get_issue`（`/issues/`）で状態を見る。マージ済み・クローズなら `move → 完了`（reason に状態と URL。行に `intents` があれば手順6の「意図の扱い」を先に見る）。取れなかった・ツールが無いときは動かさず、報告に「GitBucket 未確認」と書く。書き込み系の gitbucket ツールは呼ばない。

### 6. 変更案を作る

`~/.local/log/todo-ai/<今日>/changes-<RUN>.json` に Write で書く。形は次のとおり（`source` は常に `"ai"`）。

```json
{"source": "ai",
 "ops": [{"op": "add", "section": "やる", "key": "epc#1163", "url": "https://...", "title": "...", "next": "...", "reason": "..."}],
 "confirm": [{"ref": "...", "kind": "...", "question": "...", "facts": "...", "options": [{"label": "A", "text": "...", "recommended": true}]}]}
```

- op は `add` / `move` / `set_next` / `attach` / `order` / `edit_title`（`origin: ai` の行の題を短くするときだけ。下の規則 11）。各 op の `reason` に根拠（候補の `evidence` の引用・URL）を書く。apply がコミット本文に残す
- `ref` は行の `key`、key の無い行は `title:<タイトル完全一致>`。`context-<RUN>.json` の `ref` をそのまま使う
- 候補と台帳の突き合わせは **key の完全一致**（`items` の全セクション、完了も含む）

#### 規則

以下の「候補」は `my-tasks-<RUN>.json` の `candidates[]`、「行」は `context-<RUN>.json` の `items[]`。

**まず候補をふるい分ける（規則 1〜10 より前に、上から順に見る）。** 落とした候補は op にも確認待ちにもせず、報告の「足さなかった候補」に key（無ければ title）と理由を1行で書く。

- **ユーザーが消した ref**: 候補の key（key が無ければ `title:<候補の title>`）が `deleted_refs` にある → 落とす。人が `/todo-edit` で消した・改名した行で、足し直すと人の判断を覆すため（後片付けにも入れない）。候補の ref が `other_intents` にあれば、その意図に従って扱う（例「来たら待ちへ」なら待ちへ add）
- **他人の担当（F2）**: `evidence`・`title`・`next` に、担当・assignee・依頼先が自分以外だと書かれている（他人に割り当てられた Issue/課題DB の課題、他人の PR で自分へのレビュー依頼が無い、他人への依頼を横で見ているだけ等）→ 落とす。`theirs` の候補は、自分の作業（自分の質問・依頼・提出物・自分の PR・自分が出したレビュー（Request Changes 等）への相手の修正）が相手の返答を待っていると `evidence` から読めるときだけ残す。読めなければ落とす。ただし同じ key の行が既にあれば落とさず、その行として規則 2〜5 にかける（足さないだけで、台帳の行の更新は止めない）
- **後片付け（F4）**: 成果物を作らず、終わった作業の残りを片付けるだけの `mine`/`theirs` の候補（worktree・ブランチ・stash・一時ファイル・検証用のデータや環境の削除、不要になった PR/Issue のクローズ等）を、`title`・`next`・`evidence` の文言で判断する → 規則 1・4・7 にかけず、下の「後片付けの行」に回す。ただし同じ key の行が既にあれば後片付けにせず、その行として規則 2〜5 にかける。迷ったら後片付けにしない（通常の規則にかける）
- **自分の PR の ball**: 自分の PR の候補の `ball` は `/my-tasks` が `pr_ball.py` で決めた値なので、そのまま使う（`evidence`・`next` の文言から mine/theirs を決め直さない。レビュー依頼済みで相手の反応が無い PR は `theirs` で、待ちに入る）。`evidence` に pr_ball の `unknown`（取得失敗等）が書かれている候補は、その ball を根拠に既存の行をやる⇄待ちへ動かさない

1. **add**: `key` と `url` が両方ある `mine`/`theirs` の候補で、同じ key の行が無く、`rejected_refs` にも `archived_keys` にも無く、`answered_refs` にその key の回答が（kind を問わず）無く、`confirm_blocks` に同じ ref の問いが無いもの。`mine`→`やる`、`theirs`→`待ち`。`title`・`next` は候補の値を下の「題と next の書き方」に沿って縮めたもの（改行を入れない）。ただし規則 4 の attach・規則 4b の問いに当たるなら add しない
2. **move → 完了**: `maybe_done` の候補で、同じ key の行がやる/待ちにあり、`evidence` に決着（マージ・クローズ・「対応しました」・送信済み等）が読めるもの。決着が読めなければ動かさない
3. **move やる⇄待ち**: 候補の `ball`（mine/theirs）と行の section が食い違うとき。2・3 とも、移動先が行の `pinned_to` に入っていれば動かさない（人が戻した行と取り合わない。apply も `skip: pinned` で飛ばす）。`pinned_to` に無い移動先へは動かしてよい（例: 人が待ち→やるに戻した PR がマージされたら完了へ）
4. **attach**: `key` が null の行（やる/待ち）と、同じ作業だと言い切れる候補（`key` と `url` あり、その key の行がまだ無い）。行の `next` が null のときだけ候補の `next` も付ける。`origin: human` の行で「言い切れる」のは、候補の title が行の title と表記揺れ（助詞・「の」・空白・全角半角）しか違わず、同じ作業らしい候補が他に無いときだけ。それ以外の人の行は 4b。`origin: ai` の行で言い切れなければ何もしない
4b. **人の行と同じ作業らしい候補**: `key` と `url` がある `mine`/`theirs` の候補が、`origin: human` のやる/待ちの行と同じ作業らしい（4 の「言い切れる」に届かない）とき、add せず確認待ち（`kind=is_task`）を出す（人の行に key を付けると、その PR/Issue が閉じたとき同期が行ごと完了にするので、人が決める）。当たる候補の数で問いを変える
   - **1件だけ**: ref=候補の key、question=`『<行の title>』と同じ作業？`（title は行の題そのまま。回答の反映で行を探す手がかりになる）、facts=`<候補の題を短く>・<自分の番|相手待ち>`、options=A `同じ（今の行に紐付ける）`（おすすめ）/ B `別の作業（<やる|待ち>に足す）` / C `足さない`。B の括弧は候補の ball（mine→やる、theirs→待ち）
   - **2件以上（行が複数の作業をまとめた傘の行）**: 紐付けを勧めない（1件だけ紐付けると、その PR が閉じた時点で行ごと完了になり残りを追えなくなる）。問いは1つだけ: ref=行の ref、question=`『<行の title>』に <候補の key を・でつなぐ> を別の行で足す？`（行は ref で分かるので題は縮めてよい。key は `gb:` を外した短い形でよい。例 `『パイロット』に java-source#7・WEB#4・WEB#3 を別の行で足す？`）、facts は空でよい、options=A `足す`（おすすめ）/ B `足さない（今の行で追う）`
   - 傘の行の ref に is_task の回答が `answered_refs` にあれば、その行に当たる候補は問わず回答に従う（A なら規則 1 で add、B なら足さない）。後から当たった新しい候補も同じ
5. **set_next**: 行の `next` と候補の `next` が違うとき。ただし `origin: human` で `next` が既にある行は上書きしない。自分の PR に未対応のレビュー指摘があるときの next は `N1,N2 残` の形で始める
6. **still_needed**: やる/待ちの行で、key が `rc:` か `mail:` で始まり、`age_days` が 14 より大きく（null は対象外）、同じ key の候補が今回の `my-tasks-<RUN>.json` に無く、`answered_refs` に `(ref, still_needed)` が無いもの。ただし `my-tasks-<RUN>.json` の `sources_failed` に `rocketchat` があれば `rc:` の行、`mail` があれば `mail:` の行には適用しない（取れなかったことを「進展なし」と扱わない） → `confirm kind=still_needed`（question=`『<行の題>』はまだ要る？`、facts=`<age_days>日動きなし`、選択: A `要る` / B `不要（完了にする）`）
7. **is_task**: `mine`/`theirs` の候補で、`key` が null のもの、または `key` はあるが `url` が null のもの（`wt:` 等。apply は url の無い key を受け付けない）で、同じ作業の行が無いもの → `confirm kind=is_task`。**`maybe_done` の候補は出さない**（足す作業が残っていないので雑音になる）。ref は key があれば key、無ければ `title:<候補の title>`（ref は候補の題のまま。question の題だけを縮める）。question=`『<候補の題を縮めたもの>』をタスクに足す？`、facts は判断の決め手を1つ（例 `期限 11/14`・`内堀さんの返事待ち`）。options は文言を固定する: A `追加する（<やる|待ち>）`（括弧は ball が mine ならやる、theirs なら待ち）/ B `タスクではない（追加しない）`。おすすめは evidence から選び、迷えば B（表示した追加先と反映先を一致させるため、文言を変えない）。`answered_refs` に同じ ref の is_task があれば出さない。ref の表記が違っても同じ作業への回答が `answered_refs` にあれば出さない
8. **conflict**: 完了にある行と同じ key の候補が `mine`/`theirs`（元がまだ開いている）→ `confirm kind=conflict`。question=`完了にした『<行の題>』がまだ開いている。どうする？`、選択は「完了のまま（おすすめ）」と「自分でやるに戻す」。**AI は完了から動かせない**ので、戻す op は作らない
9. **order**（やる）: 並べ替え後の順を `{"op": "order", "section": "やる", "refs": [...]}` で出す。順位は ① 対応する候補に `waiting_person` がある ② `deadline` が早い（null は後）③ `blocks` が多い ④ 元の順。候補の無い行は元の順のまま後ろ（人の行が下に回るのは今の挙動どおりでよい）。**refs は前の op を適用した後の ref**（attach した行は付けた key、add した行はその key、edit_title した key の無い行は `title:<新しい題>`）。順が変わらなければ出さない
10. **policy / before_share / manual**: 候補の next が「方針を決める」「人に見せる前の確認」「ユーザーにしかできない手作業」のときだけ。多用しない
11. **edit_title**（AI の行の題を短くする）: やる/待ちの `origin: ai` の行で、題が30字を超えるか key の番号（`PR #1210`・`#1224`・`eae#59` 等）を含むもの → `{"op": "edit_title", "ref": <行の ref>, "title": <縮めた題>, "reason": "題を短くする"}`。題は下の「題と next の書き方」に沿う。`origin: human` の行・完了の行・`後片付け（` で始まる行には出さない（apply が人の行なら全体を exit 2 で止め、完了・後片付けの行は `skip:` で飛ばす）。key の無い行は ref が `title:<新しい題>` に変わる（apply が `alias` で前の記録とつなぐ）。同じ実行の後の op はその新しい ref を使う

#### 題と next の書き方

ポップアップは幅が狭く、URL は nvim が隠すが文字数はそのまま折り返しに効く。

- 題（`title`）は何の作業かが分かる名詞句で25字目安。key の番号（`PR #1210`・`#1224`・`gb:ebase-web#96` 等）を書かない（key はリンクとして行の後ろに出る）。人名は要るときだけ括弧で（例 `車両候補バブルの再レビュー（彌永さん）`）
- `next` は次の一手を30字目安で。コミットのハッシュ・URL・経緯を書かない
- 規則 5 の set_next は、候補の `next` を縮めた文が今の `next` と同じ中身なら出さない（言い回しの違いだけで毎回書き換えない）

#### 後片付けの行（F4）

ふるい分けで後片付けにした候補は、1行にまとめる。

- 題は常に日付付きの `後片付け（<追加した日 YYYY-MM-DD>）`（完了に同じ題の行が残ると ref が2つに当たり、apply が以後の set_next・move を `ambiguous` で飛ばすため）
- 対象の行: やる/待ちにある、title が `後片付け（` で始まる `origin: ai` の行。複数あれば最初の1つ。`origin: human` の行は人の行として扱い、作り直し・完了にしない
- 中身: 今回の後片付けの候補ごとに短い名前（例 `epc-1163 の worktree 削除`）を作り、候補の並び順に `; ` でつないで `next` にする。名前に改行・` — next: `・`](` を入れない
- 行が無く、中身が1つ以上 → `add`（section `やる`、`key` なし、title `後片付け（<今日>）`、next は中身）。ただし次のときは足さず報告に書く: `rejected_refs` か `deleted_refs` に `title:後片付け（` で始まる ref がある（人が一度消したら、別の日の後片付けも足さない。apply も同じ前方一致で飛ばす）／`items`（完了も含む）に `title:後片付け（<今日>）` が既にある（同じ日に完了にした。翌日に足す）
- 行があり、中身が今の `next` と違う → `set_next`。中身が0件 → `move → 完了`
- `sources_failed` が空でないときは、今の `next` の項目を残したまま新しい項目を後ろに足すだけにし、項目を消す・完了にすることはしない（取れなかったことを「片付いた」と扱わない）
- 行に `intents` があれば下の「意図の扱い」が優先する

#### 意図の扱い（すべての op と問いに、規則 1〜10・手順5・回答の反映より優先して当てる）

`items[].intents` は、ユーザーがその行について `/todo-edit` で指示した内容で、守るべき指示として読む（新しい順。食い違えば新しい方）。

- 意図のある行には、意図に反する op を作らない: 完了への `move`（手順5の GitBucket のマージ・クローズも含む）、やる⇄待ちの `move`、`set_next`（意図が next の中身・順番を指定しているとき）、`order` での位置。例: 「eas#60 のマージ後にレビュー依頼する」の行は、eas#60 がマージされるまで完了にも待ちにもせず、next をその指示と違う文に変えない
- 一次データ（候補の `evidence`・PR/Issue の状態）が意図と食い違う（意図は「残す」なのに決着している、意図の待ち条件が満たされた等）ときは、その行に op を作らず `confirm kind=conflict`（ref は行の ref）で聞く。question に意図と事実の食い違いを1行で書き、facts に意図と一次データを短く（例 `意図「マージ後に依頼」・eas#60 マージ済み`）、options は A `意図どおりにする`（おすすめ）/ B `<一次データに沿った op の内容>`。行の `answers` に `superseded: false` の conflict の回答があれば、問わずにその回答に従う。`superseded: true` だけなら回答の後に新しい意図が記録されているので、食い違えばもう一度聞く（apply も、意図より後に記録された回答だけを回答済みとして扱う。ts は比べない）。今回の `answered_now` の `superseded: true` は下の「回答の反映」のとおり必ず問い直す
- 意図に反しない op（意図が指示していない側面の更新）はふつうに作ってよい。意図が読み取れないときは op を作らず報告に書く
- `deleted_refs` の ref は、`add`・`attach`・確認待ちの問いのどれにも使わない（ふるい分けで落とす）。`other_intents` の意図は、その ref の候補を足すときの指示として従う

#### 確認待ちの書き方

apply は1問を次の3行で書く（`facts` が空なら括弧ごと出さない。おすすめは★。タグは nvim が隠す）。

```
1. <question>（<facts>） [<kind> <ref>]
   A <text>★ / B <text>
   回答:
```

- `question` は「決めること」を1行で書く。`ref` と `kind` は必須。kind は `policy` `before_share` `manual` `conflict` `is_task` `still_needed` のどれか。apply が問いの末尾に ` [<kind> <ref>]` のタグを付け、次の実行はこのタグで回答の記録先を決める。タグを自分で書かない
- `facts` は問いの後ろの括弧に入るので、判断に要る事実だけを20字目安で（件数・日付・状態・待ち相手）。推測・URL・長い引用を書かない。括弧を入れるなら閉じる
- 問い・事実・選択肢に中の言葉を書かない: `title:`・`mine`・`theirs`・`ball`・`ref`・`既存行:`・`候補:` 等。「やる/待ち」「自分の番/相手待ち」「今の行」で書く
- `options` は 2〜3 個、`label`（A/B/C）と `text` は空にしない。`recommended: true` はちょうど1つ
- `confirm` は毎回全置換。次の順で並べる: ① `confirm_blocks` のうち `answer` が空のものを写す（状況が片付いた問いは落としてよい）② 今回新しく出す問い。①は `ref` `kind` と選択肢の並び・意味を変えずに、`question` `facts` `options` の言い回しをこの書き方に合わせて縮めてよい（旧書式の長い問いはここで縮める）

#### 回答の反映

- 回答の記録は apply が回答欄とタグから行う。`answered` キーは入れない（入れる場合は `answered_now` と完全に一致しないと exit 2）
- 回答したブロックは `confirm` に写さない（写しても apply が、回答欄が埋まっている・判断記録にある (ref, kind) の問いを `skip: answered` で落とす）
- 回答の内容に沿った op を作る。回答は選択の `label`（A/B/C）か `text` の言葉で読む。問いの中身は `confirm_blocks` の同じ ref・kind のブロック（回答済みも載っている）の `question`・`facts` で見る。回答が読み取れない自由文なら op は作らず、記録だけして報告に書く
  - still_needed に「不要」→ `move → 完了`
  - is_task に `A 追加する（<やる|待ち>）` → 括弧のセクションへ `add`（F3: 相手ボールは待ち）。候補に `url` が無ければ `key` も入れず `title` だけ（`wt:` も同じ）。`B タスクではない` → op なし
  - `『…』と同じ作業？`（規則 4b の1件。旧書式では `既存の『…』と同じ作業？`）に「同じ」→ 問いの『』の題と title が完全一致するやる/待ちの行（旧書式で `facts` に `既存行:` があればその ref）へ、問いの ref の key と今回の候補の `url`（今回に無ければ旧書式の `facts` の url。どちらも無ければ attach せず報告に書く）で `attach`（行の `next` が null のときだけ候補の `next` も付ける）。行が見つからない・その行に既に key があれば attach せず報告に書く。「別の作業」→ 括弧のセクションへ `add`。「足さない」→ op なし（回答の記録が以後の add を止める）
  - `『…』に … を別の行で足す？`（規則 4b の傘の行。旧書式では `既存の『…』に含まれる作業。別の行で足す？`）に「足す」（旧書式は「別の行で足す」）→ 問いに挙げた各 key（旧書式は `facts` の `候補:`）を、今回の候補の ball（今回の JSON に無ければ旧書式の facts の ball）でやる/待ちへ `add`（`key` と `url` は今回の候補から。今回に無い候補は足さず報告に書く）。「足さない」→ op なし
  - conflict（意図との食い違い）に回答 → 選ばれた側の op を作る。「意図どおり」なら op なし
- `answered_now` の `superseded: true` の回答（問いを書いた後に新しい意図が記録された）は、黙って捨てない。従う op は作らず、毎回次の2つを両方する
  - `confirm` の②で同じ `ref`・`kind` の問いを出し直す。`facts` に新しい意図（行の `intents` の先頭）と前の回答を短く入れ、question・options は新しい意図に合わせて書き直してよい（apply は古くなった回答を回答済みに数えないので `skip: answered` にならない）
  - 報告の6に、問い（`confirm_blocks` の同じ ref・kind の `question`）とユーザーの回答を出す
- 回答に沿った op にも「意図の扱い」を当てる（`superseded: false` の回答なら回答に従い、`superseded: true` の回答には従わない）。`deleted_refs` の ref は、回答が何であっても `add`・`attach` しない（apply も飛ばす。報告に書く）

#### 確認待ちが壊れているとき（`confirm_errors` が空でない）

人が確認待ちの問い・事実・選択を書き換えた、または自由文を書いた状態。`confirm` を含めると apply は人が直すまで毎回 exit 2 で止まる。

- changes-<RUN>.json に `confirm` の **キーを入れない**（確認待ち欄はそのまま残り、回答も記録されない）
- 回答に基づく op も作らない
- それ以外の op はいつもどおり作って適用する
- `confirm_errors` の文言をそのまま報告に入れ、直し方を添える: 問い・事実・選択の書き換えや自由文なら「apply が書いた形に戻すか、そのブロックを消してください」、`タグが無い` なら「そのブロックを消してください」（記録先が分からないため）

#### apply が全体を止める書き方（1つでもあると何も書かれない）

- 完了にある行への `move`
- `add` の `section` がやる/待ち以外、`key` があるのに `url` が null、key の形式違い（`epc#N` `emm#N` `eae#N` `eas#N` `gb:<repo>#N` `rc:<id>` `rc:<id>#N` `mail:<id>` `wt:<name>` `ebpm:No<数字>`）
- どの文字列にも改行を入れる
- `title`・`next` に ` — next: ` や `](` を含める、`title` の前後に空白がある、`url` に空白や括弧がある（書き出すと別の行に読めてしまうため全体が止まる）
- `options` の要素に `label`/`text` が無い・空、`confirm` の要素に `ref` が無い・`kind` が上の6種以外
- `origin: human` の行（この実行で add した行を除き、apply が git 履歴で判定する）への `edit_title`

存在しない ref への op、`deleted_refs`（後片付けは `title:後片付け（` の前方一致）を足し直す add/attach、完了・後片付けの行への `edit_title` は、apply がその op だけ飛ばす（`skip:` / `skip: intent_deleted` / `skip: done` / `skip: cleanup` としてコミット本文に残る）。

### 7. 適用

```bash
L=~/.local/log/todo-ai/$(date +%F); R=$(dirname "${TODO_MD_PATH:-$HOME/memo/todo.md}"); git -C "$R" rev-parse HEAD >$L/head-before-<RUN>.txt; python3 -I ~/.dotfiles/scripts/todo-ai/apply.py --changes $L/changes-<RUN>.json >$L/apply-<RUN>.out 2>$L/apply-<RUN>.err; echo "exit=$?"; cat $L/apply-<RUN>.err
```

| 終了コード | 意味 | すること |
|---|---|---|
| 0 | 適用した（変更なしを含む） | 報告へ |
| 3 | todo.md を nvim で編集中、または実行中に変わった | 「編集中のためスキップ（次回に反映）」と報告して終わる。やり直さない |
| 2 | 検証違反。何も書いていない | `apply-<RUN>.err` の全文を報告して終わる。同じ案で再実行しない |
| 1 | その他のエラー | `apply-<RUN>.err` を報告して終わる |

exit 2 で `確認待ちの問い・事実・選択が apply の書いた内容と違う` が出た場合も、再試行せず文言をそのまま伝える（人が戻すまで止まり続ける）。

## 報告（最後のチャット出力）

短く、次だけを出す。

1. 結果: 適用 / 変更なし / スキップ（編集中）/ 違反で未適用 / 収集失敗
2. op の種類ごとの件数: exit 0 で HEAD が `head-before-<RUN>.txt` から変わり、かつ `git -C <台帳のディレクトリ> log -1 --format=%s` の件名が `todo(ai): ` で始まるときだけ、その件名を出す（apply の集計、飛ばした op を除く）。それ以外（HEAD が同じ、人の未コミット分だけが `todo: ` でコミットされた等）は「AI の変更なし」と書き、changes-<RUN>.json の件数を「案」として添える
3. 新しい確認待ち: exit 0 なら適用後の todo.md の `## 確認待ち` 欄（番号・問い・おすすめ）。それ以外は「変更なし」
4. 違反・警告: `apply-<RUN>.err`、`confirm_errors`、同期の失敗、GitBucket 未確認、my-tasks で取れなかったデータ源
5. 足さなかった候補・止めた op: ふるい分けで落とした候補（意図で消された ref・他人の担当）と、意図のために作らなかった op を1行ずつ（key か title と理由）
6. 古くなった回答: `answered_now` の `superseded: true` ごとに1行（ref・問い・ユーザーの回答・新しい意図）と「確認待ちで問い直した」。無ければ出さない

ログは `~/.local/log/todo-ai/<今日>/`。1回の実行のファイルは同じ `<RUN>`（開始時刻 HHMMSS）を持つ（sync-<RUN>.out/err, context-<RUN>.json/err, my-tasks-<RUN>.json, changes-<RUN>.json, head-before-<RUN>.txt, apply-<RUN>.out/err）。

## review モード（`/todo review`）

人が AI の判断を直した記録を週1で見直し、`/my-tasks` と `/todo` のどこを直すかを決める。収集・同期・適用はしない。

過去ログを読んでよいのは review.py だけ。目的が AI の過去判断の評価で、タスクの根拠には使わないため。

```bash
python3 -I ~/.dotfiles/scripts/todo-ai/review.py --since $(date -d '7 days ago' +%F)
```

1. 出力の表（日付・ref・人がしたこと・AI がしたこと・AI の根拠・my-tasks の根拠・ball）を各行そのまま出す。`-` はログが無いだけで、推測で埋めない
2. 各行を3層に振り分ける（agent-memory `scripts/task-inventory-verification-gate.md`）
   - 取得層: 根拠のデータがそもそも無い・取れていない → 収集元を足す
   - 判定層: データはあるが機械的に引く工程が無い → 規則・ゲートを足す
   - 解釈層: 読んだのに誤読した → プロンプトの文言（確率的で、収集を厚くしても防げない）
3. 層ごとに、直す先（my-tasks SKILL.md か todo SKILL.md のどの規則）と具体的な修正案を出す。表の根拠が空の行は層を断定せず「ログ不足」とする
4. **ここで止まる。** SKILL.md の修正はユーザーが OK してから行う

無人実行（非対話）のときは、表と修正案を出力するだけで終わる。
