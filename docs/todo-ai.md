# 業務TODOのAI管理（todo-ai）

`~/memo/todo.md` を、一次データ（GitHub・`/my-tasks` の収集結果）に合わせて AI とスクリプトが更新する仕組み。
人は今までどおり tmux のポップアップ（`docs/todo-md.md`）で読み書きする。設計は `docs/superpowers/specs/2026-11-10-todo-ai-management-design.md`。

todo.md に書くのは `scripts/todo-ai/apply.py` だけ。AI（`/todo`）も同期スクリプトも変更案 JSON を作って apply に渡す。
apply は人の行・完了・回答を壊す案を丸ごと止め、通った変更を `todo(ai): ` / `todo(sync): ` のコミットにする（本文に理由と根拠リンク）。

## 構成

| ファイル | 役割 |
|---|---|
| `scripts/todo-ai/apply.py` | 唯一の書き込み口（検証・nvim ロック・排他・30日アーカイブ・コミット） |
| `scripts/todo-ai/sync_github.py` | GitHub でマージ/クローズ済みの行を完了へ移す（AI なし。cron 用） |
| `scripts/todo-ai/context.py` | `/todo` が読む台帳の材料を JSON で出す |
| `scripts/todo-ai/decisions.py` | 人の判断（回答・戻し・消した追加）の記録と検出 |
| `scripts/todo-ai/migrate.py` | 旧形式の todo.md を新形式へ一度だけ変換 |
| `scripts/todo-ai/review.py` | 週次見直し用に人の訂正を一覧化 |
| `scripts/todo-ai/pr_ball.py` | 自分の PR のボール（mine / theirs / done / unknown）を決める。マージ・クローズ済みは done、取得に失敗した PR は unknown |
| `scripts/lib/ebpm_issues.py` | 課題DB（ebpm）の自分のコメント・お知らせ・担当を読み取る |
| `.claude-global/skills/todo/SKILL.md` | `/todo` と `/todo review` |
| `.claude-global/skills/todo-edit/SKILL.md` | `/todo-edit`（ユーザー指示で直し、意図を記録） |

`~/memo` に増えるもの: `todo-decisions.jsonl`（人の判断の記録）、`todo-archive/YYYY-MM.md`（30日を過ぎた完了行）。どちらも apply がコミットする。

## 導入

### 1. todo.md を新形式に移す

新形式は上から `## 確認待ち` → `## やる` → `## 待ち` → `## 完了`。旧形式のままだと apply・context は解釈できずに止まる。

先にコピーで変換結果を見る。

```sh
mkdir -p /tmp/todo-migrate && cp ~/memo/todo.md /tmp/todo-migrate/todo.before.md && cp ~/memo/todo.md /tmp/todo-migrate/todo.md
python3 ~/.dotfiles/scripts/todo-ai/migrate.py /tmp/todo-migrate/todo.md
diff -u /tmp/todo-migrate/todo.before.md /tmp/todo-migrate/todo.md
```

差分で見るところ:

- 見出しの無い未完了が `## やる` に入り、先頭に空の `## 確認待ち` が付く。タスクの文言は変わらない
- 日付の無い完了行に、移行した日の ` (done: YYYY-MM-DD)` が付く。30日後に `todo-archive/` へ移る
- 見出しまわりの空行が整う

問題なければ実ファイルを変換して、人のコミットとして残す。

```sh
python3 ~/.dotfiles/scripts/todo-ai/migrate.py ~/memo/todo.md
git -C ~/memo commit -m "todo: 新形式へ移行" -- todo.md
```

日付を変えたいときは `--date YYYY-MM-DD`。新形式に再実行しても変わらない。

### 2. ~/memo/.gitignore

ロックと書き込み途中の一時ファイルをコミットに混ぜないため、次を足す。

```gitignore
.todo.lock
.todo.write.lock
.*.tmp
```

`.todo.lock` は nvim がポップアップを開いている間の PID、`.todo.write.lock` は apply 同士の排他（flock）。
一時ファイルは書き込み先と同じ場所の `.<名前>.tmp`（`.todo.md.tmp`、`.todo-decisions.jsonl.tmp`、`todo-archive/.YYYY-MM.md.tmp`）。

### 3. cron で GitHub 同期

平日 8〜20 時に毎時。

```cron
0 8-20 * * 1-5 mkdir -p /home/aya/.local/log/todo-ai && /home/aya/.dotfiles/scripts/todo-ai/sync_github.py >> /home/aya/.local/log/todo-ai/sync.log 2>&1
```

cron の PATH に Nix の `gh` は無いが、見つからなければ `~/.nix-profile/bin` と `/etc/profiles/per-user/$USER/bin` を前に足して探す。
`ebase-dev/*` へは `gh auth token --user eBASE-Mori` のトークンで問い合わせる。

### 4. cron で /todo を無人実行

平日 7 時に1回。`claude -p` はサブスクの枠で動く（2026-11-11 にユーザー確認）。

```cron
0 7 * * 1-5 mkdir -p /home/aya/.local/log/todo-ai && /home/aya/.dotfiles/scripts/todo-ai/run-unattended.sh >> /home/aya/.local/log/todo-ai/cron.log 2>&1
```

- 承認ダイアログに答える人がいないので `--permission-mode auto` で動かす。hook は `disableAllHooks` で止める（セッション要約の再帰発火を防ぐ）
- `~/.claude/skills` はメイン checkout（`~/.dotfiles`）を指す。そこが main 以外のブランチで `/todo` が無いと、claude を呼ばずに exit 1 で終わる
- 前回の実行が終わっていなければ何もせず終わる（flock）
- 実行するコマンドは `run-unattended.sh --dry-run` で確かめられる

## 使い方

### /todo

Claude Code で `/todo`（「TODO更新」「確認待ちに答えたから反映して」等でもよい）。手順は GitHub 同期 → 台帳を読めるかの確認 → `/my-tasks` の JSON 収集（約8分）→ 台帳の材料づくり → 変更案 → apply。
質問はせず最後まで走り、結果・op の件数・新しい確認待ち・警告だけを報告する。

確認待ちには問いごとに4行のブロックが出る。答えるときは `回答:` の後ろに書くだけで、問い・事実・選択の行は書き換えない（書き換えると、人が直すまで apply が確認待ちを更新しない）。
回答は次の `/todo` で `todo-decisions.jsonl` に記録され、同じ問いは二度と出ない。

所要は実測で約14分・約306k tokens（2026-11-11）。大半は `/my-tasks` の収集（サブエージェント）。

### データ源と key

収集元に課題DB（ebpm）が加わった。読み取りのみで、`ebpm_issues.py` が API を1回30件まで・呼び出しの間1秒空けて直列に叩く。落ちている・打ち切られたときは `sources_failed` に `ebpm` が入るだけで、他の収集は止まらず、`rc:` 等と同様に「進展なし」とは扱わない。

課題DB の行の key は `ebpm:<課題No>`（例 `ebpm:No00007400`）、URL は `https://ebpm.ebase-jp.com/ebase-web-v3/DispDetail.do?volumeName=02043&itemID=<item_id>`。`item_id` が取れない課題は key なしの候補になり、確認待ち（`is_task`）で聞く。自分の PR は `pr_ball.py` が決めた ball を使い、取得に失敗した PR を「待ち」と決めつけない。

AI の変更が違っていたら、nvim で直せばよい。git 履歴から検出して記録する。

- AI が足した行を消す → その key は二度と足さない（`reject_add`）。key の無い行は記録しないが、後片付けの行（`後片付け（` で始まる）だけは、やる・待ちから消して後片付けの行が残っていないときに記録し、別の日の後片付けも足さない（完了から消す・題を `後片付け（…` のまま直すのは記録しない）
- AI が移した行を元のセクションへ戻す → その行を、戻された移動先へは二度と移さない（`revert_move`）。別のセクションへの移動は止めない。たとえば AI が待ちにした PR を `<Tab>` でやるに戻しても、マージされれば同期が完了へ移す
- `/todo-edit`（source user）で完了から戻した行は、戻し先によらず完了へは二度と移さない（`revert_move` の to=完了）。同期が毎時また完了にするのを防ぐ代わりに、本当に終わったら手で完了にする
- `/todo-edit` のそれ以外の変更（`todo(user): ` のコミット）は戻しとして検出しない。止める根拠は記録した意図で、`/todo` が読む
- key の無い行に AI が key を付けると、apply が `alias`（`{"ref": <key>, "kind": "alias", "prev_ref": <旧 title: ref>, "by": "ai"}`）を記録する。人の判断ではなく、付ける前の意図・戻し・回答を新しい key の行へつなぐための印

### /todo-edit

Claude Code で `/todo-edit`（「todo を直して」「資料の件は〜にして」「この行を消して」でもよい）。**対話専用**で、AI が自分で判断せずユーザーの指示どおりに直す。

手順: 指示を読む → `context.py` で台帳を読む → 指示を行に対応づける（曖昧なら候補を出して聞く）→ 変更案と意図を見せて OK をもらう → `apply.py --allow-user` → コミットの差分と記録した意図を見せる。変更案は `~/.local/log/todo-ai/<日付>/edit-<HHMMSS>.json` に残る。

できること:

| 指示 | op | 注意 |
|---|---|---|
| next を変える | `set_next` | |
| セクションを移す | `move` | 完了から出す（reopen）と、以後 `/todo` も同期も自動で完了に戻さない。GitHub の key の行は、やる/待ちにあるうちは意図を残しても PR がマージ・クローズされると同期が完了へ移す（同期は意図を読まない）。開いたまま残すには、完了に移った後に完了から出す |
| 行を足す | `add` | |
| タイトルを直す | `edit_title` | key の無い行は、元のタイトルを `/todo` が足し直さない（key のある行は ref が変わらない） |
| 行を消す | `delete` | その行を `/todo` が二度と足し直さない |
| 意図だけ残す | `note` | 行は変わらない |

`edit_title` / `delete` / `note` は user だけの op。外部アクション（コメント・送信等）はしない。

**やる・待ちの後片付けの行を消すと、後片付けの行は別の日の分も含めて二度と足されなくなる。** 1回分を片付け終えたいだけなら、消さずに完了へ移す（翌日以降は新しい後片付け行が足される。完了へ移した後に完了から消すのはかまわない）。

#### 意図の記録

各 op に付けた `intent`（ユーザーの指示を要約した1文で、根拠の言葉を含む）を `todo-decisions.jsonl` に `{"ts", "ref", "kind": "intent", "value", "by": "human", "op"}` で記録する（`op` は意図を残した op。key の無い行の改名・key 付けでは `prev_ref` も付く）。コミットは `todo(user): <要約>` で、origin 判定では人の行扱い。

`/todo` は `context.py` の次を必ず読んで従う。

- `items[].intents`（その行の意図。新しい順で最大5件。key を付ける前・改名する前の ref の意図も含む）: 意図に反して完了・移動・next の上書きをしない。一次データが意図と食い違うとき（意図は「eas#60 のマージ後に依頼」なのに eas#60 がマージされた、GitBucket の PR がマージ・クローズされた等）は、op を作らず `conflict` の確認待ちで聞く。GitHub の key の行のマージ・クローズは毎時の同期が意図を読まずに完了へ移すので、conflict にはならない
- `items[].answers`: その行への確認待ちの回答。`superseded: true` の conflict の回答（問いや回答より後に同じ行の意図が記録された）には従わず、今回の実行で付いた回答なら最後の報告に問いと回答を出して、新しい意図を事実に入れて確認待ちで問い直す。apply も、意図より後に記録された回答だけを回答済みとして扱う（ファイル内の位置で比べる）
- `deleted_refs`: 消した行（key を付ける前の ref も）・key の無い行の改名前の ref。`add` も `attach` も確認待ちの問いにも使わない（後片付けは題の前方一致）。source ai の add/attach は apply が `skip: intent_deleted` で飛ばす。人が nvim で行を書き戻すと、その ref は外れてふつうの行に戻る（消した指示とそれより前の意図も `items[].intents` に出なくなる）
- `other_intents`: まだ台帳に無い key へのメモ。その候補を足すときの指示として従う

apply は source user に `--allow-user` を必須とし、`TODO_AI_DENY_USER=1` なら常に拒む（無人実行が user を名乗っても通らない）。完了から出した行には `revert_move`（to=完了）の記録が付き、AI・同期が完了に戻さない。

### /todo review

週1回、人が AI の判断を直した記録を、AI の根拠（変更案の reason・`/my-tasks` の evidence）と並べた表にし、どの規則・収集を直すかの案を出す。SKILL.md は OK を出すまで直さない。

```sh
python3 ~/.dotfiles/scripts/todo-ai/review.py --since $(date -d '7 days ago' +%F)
```

### 終了コード

| スクリプト | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| `apply.py` | 適用した（変更なしを含む） | その他のエラー | 検証違反で何も書いていない | nvim で編集中・実行中に変わったのでスキップ |
| `sync_github.py` | 動かす行が無い、または apply が 0 | トークン取得失敗・todo.md を読めない（apply を呼んだときは apply の終了コード） | apply の終了コード | apply の終了コード |
| `context.py` | 出力した | todo.md を読めない・解釈できない | - | - |
| `migrate.py` | 変換した | 旧形式として解釈できない（ファイルはそのまま） | 引数が違う | - |

3 は次の実行で反映されるので放っておいてよい。2 は stderr の理由を見て todo.md か変更案を直す。

## ログ

| 場所 | 中身 |
|---|---|
| `~/.local/log/todo-ai/sync.log` | cron の同期の stderr/stdout |
| `~/.local/log/todo-ai/cron.log` | 無人実行の開始・終了と終了コード |
| `~/.local/log/todo-ai/<YYYY-MM-DD>/run-<HHMMSS>.log` | 無人実行1回分の claude の出力 |
| `~/.local/log/todo-ai/<YYYY-MM-DD>/` | `/todo` の1回ごとのファイル。名前に開始時刻 `<HHMMSS>` が付く（`sync-`, `context-`, `my-tasks-`, `changes-`, `head-before-`, `apply-`） |
| `~/.local/log/todo-ai/<YYYY-MM-DD>/edit-<HHMMSS>.json` | `/todo-edit` の変更案 |
| `git -C ~/memo log` | AI・同期・ユーザー指示の変更と理由（`todo(ai): ` / `todo(sync): ` / `todo(user): ` の本文。飛ばした op は `skip: ...`） |
| `~/memo/todo-decisions.jsonl` | 人の判断（回答・戻し・消した追加）と `/todo-edit` の意図の記録 |

`/todo` は過去のログを読まない（AI の過去の推測が事実として戻ってくるため）。読むのは `review.py` だけ。

## やっていないこと

- GitBucket の状態は `/todo` 実行時に AI が読み取りで見るだけで、cron の同期は GitHub だけ
