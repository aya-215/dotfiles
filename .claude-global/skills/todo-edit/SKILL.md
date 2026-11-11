---
name: todo-edit
description: ユーザーの指示で業務TODO（~/memo/todo.md）を直し、直した意図を記録して /todo の次の判断基準にする。「/todo-edit」「todo を直して」「資料の件は〜にして」「この行を消して」「〇〇は待ちに移して」「〇〇は完了じゃなくてまだやる」等で使用。対話専用（無人実行・他のスキルからは使わない）。
---

# /todo-edit

ユーザーの指示どおりに `~/memo/todo.md` を直し、**なぜ直したか（意図）** を `todo-decisions.jsonl` に残す。
意図は次の `/todo` が context の `intents` / `deleted_refs` / `other_intents` として読み、意図に反して行を完了・削除・上書きしない。間違ってクローズすることも、消した行が残り続けることも防ぐ。

書き込みは `apply.py` だけが行う。Claude は変更案 JSON を作るだけで、todo.md・`todo-decisions.jsonl` を Edit/Write で直接書かない。

このスキルは **対話専用で、質問してよい唯一の todo 系スキル**。曖昧なら聞く、実行前に必ず OK をもらう。

## やらないこと

- 外部アクション（PR/Issue コメント、Rocket Chat 送信、Issue 作成、`mcp__gitbucket__` の書き込み系）
- 他のスキル・無人実行から `--allow-user` を付けて apply.py を呼ぶ（`/todo` は source `ai` 固定。`TODO_AI_DENY_USER=1` なら apply が拒否する）
- ユーザーが OK する前に apply.py を実行する
- 指示に無い行・項目まで直す（指示の範囲だけ）

## 手順

台帳の場所は `TODO_MD_PATH`（未設定なら `~/memo/todo.md`）。スクリプトは全部これに従うので、引数で渡さない。

### 1. 台帳を読む

```bash
L=~/.local/log/todo-ai/$(date +%F); mkdir -p $L; python3 -I ~/.dotfiles/scripts/todo-ai/context.py >$L/edit-context-$(date +%H%M%S).json; echo "exit=$?"
```

出力の `items[]`（`ref` `section` `title` `key` `next` `done` `origin` `intents` `pinned_to`）、`deleted_refs`、`other_intents` を読む。todo.md 本体は読まない。0 以外なら止めて stderr を報告する。

### 2. 指示を行に対応づける

ユーザーの指示（タイトルの一部・key。例「資料作成の件」「epc#1163」）を `items` の行に対応づける。todo.md の行に番号は無いので、番号で言われたら `AskUserQuestion` でタイトルか key を聞く。`ref` は行の `key`、key の無い行は `title:<タイトル完全一致>`。

- 当てはまる行が複数ある・1つも無い・指示がどの操作か読めない → 候補を出して `AskUserQuestion` で聞く。推測で進めない
- 行の `intents` に既に意図があれば、指示がそれを覆すのか確認する（新しい指示が優先。覆すときも新しい意図に理由を残す）

### 3. 変更案を作る

`~/.local/log/todo-ai/<今日 YYYY-MM-DD>/edit-<HHMMSS>.json` に Write で書く（`~` を展開した絶対パスで書き、そのパスを手順5でそのまま使う）。`source` は常に `"user"`。**すべての op に `intent` が必須**（無い・空白だけだと apply が全体を止める）。

```json
{"source": "user",
 "ops": [{"op": "set_next", "ref": "eas#60", "next": "eas#60 のマージ後にレビュー依頼する",
          "intent": "「eas#60 のマージ後にレビュー依頼する」と指示された。マージまで待ちのまま残す"}]}
```

`intent` は **ユーザーの指示を要約した1文で、根拠の言葉をそのまま引用して含める**。「いつまで残す」「何が起きたら動かす」まで書く（/todo がこの1文を読んで判断する）。

| やりたいこと | op |
|---|---|
| next を変える | `{"op": "set_next", "ref", "next", "intent"}` |
| セクションを移す | `{"op": "move", "ref", "to": "やる"\|"待ち"\|"完了", "intent"}` |
| 行を足す | `{"op": "add", "section": "やる"\|"待ち", "title", "next"?, "key"?, "url"?, "intent"}`（key があれば url も必須。形式は `epc#N` `gb:<repo>#N` `rc:<id>` `mail:<id>` `wt:<name>` `ebpm:No<数字>` 等） |
| タイトルを直す | `{"op": "edit_title", "ref", "title", "intent"}` |
| 行を消す | `{"op": "delete", "ref", "intent"}` |
| 行は変えず意図だけ残す | `{"op": "note", "ref", "intent"}`（まだ台帳に無い key にも付けられる） |

守ること:

- どの文字列にも改行を入れない。`title`・`next` に ` — next: ` と `](` を入れない。`title` の前後に空白を入れない
- `move` の `to` が今のセクションと同じなら op にしない
- `edit_title` した行は、新しい ref に意図が付く。key の無い行（ref が `title:`）だけ、元の ref が `deleted_refs` に入る（key のある行は ref が変わらない）
- `confirm`・`answered` キーは入れない（user は確認待ちを書き換えられない）。確認待ちへの回答は、人が todo.md の回答欄に書く

#### 操作ごとにユーザーへ伝えること

- **完了からの `move`（reopen）**: 「完了から出した行は、以後 `/todo` も GitHub 同期も **自動で完了に戻さない**。本当に終わったら自分で完了にしてください」と伝える
- **GitHub の key（`epc#` `emm#` `eae#` `eas#`）の行を開いたまま残したい（PR はマージ・クローズ済み）**: 毎時の GitHub 同期（`sync_github.py`）は意図を読まず、マージ・クローズ済みの PR の行を完了へ移す。止められるのは完了からの `move`（reopen。完了に戻さない pin が付く）だけ。やる/待ちにある行へ `note` や `set_next` で意図を残しても同期は止まらないので、「同期で一度完了に移った後に、完了から出す指示をもう一度ください」と伝える
- **`delete`**: 「この行は `/todo` が二度と足し直さない」と伝える。対象が `後片付け（` で始まる行なら、「**後片付け行は今後一切（別の日の分も）足されなくなる**」と伝える。後片付けの1回分を終わらせたいだけなら、delete でなく `move → 完了` を勧める（完了なら翌日以降に新しい後片付け行が足される）。ユーザーが delete を望むなら従う
- **`edit_title`**: 人の行のタイトルを直す正規の手段。key の無い行なら、元のタイトルは `/todo` が足し直さない
- **`note`**: 行は変わらない。意図だけが残り、以後の `/todo` がそれに従う

### 4. 見せて OK をもらう

変更案を次の形で見せ、`AskUserQuestion`（OK / 直す / やめる）で承認を取る。

- 各 op: 行（ref・タイトル）、変更前 → 変更後
- 各 op の `intent`（記録される文そのまま）
- 上の「操作ごとにユーザーへ伝えること」に当たる注意

「直す」なら変更案を作り直して再度見せる。「やめる」なら apply せず終わる。

### 5. 適用

OK をもらってから実行する。`<変更案の絶対パス>` は手順3で Write した絶対パスをそのまま入れる（`$(date +%F)` で組み直さない。日付をまたぐと別の日のディレクトリを指す）。

```bash
python3 -I ~/.dotfiles/scripts/todo-ai/apply.py --allow-user --changes <変更案の絶対パス>; echo "exit=$?"
```

| 終了コード | 意味 | すること |
|---|---|---|
| 0 | 適用した | 手順6へ |
| 3 | todo.md を nvim で編集中、または実行中に変わった | 「編集中のため未適用。nvim のポップアップを閉じてもう一度」と伝え、同じ変更案で再実行するか聞く |
| 2 | 検証違反（intent 欠落・ref が見つからない/複数・タイトル保護・`TODO_AI_DENY_USER` 等）。何も書いていない | stderr の全文を伝え、直せるなら変更案を直して手順4から |
| 1 | その他のエラー | stderr を伝えて終わる |

user の変更は、op を1つでも飛ばす場合は全体が止まる（承認した変更が一部だけ入ることは無い）。

### 6. 結果を見せる

```bash
R=$(dirname "${TODO_MD_PATH:-$HOME/memo/todo.md}"); git -C "$R" show --stat HEAD; git -C "$R" show HEAD -- todo.md; git -C "$R" show HEAD -- todo-decisions.jsonl
```

- コミット（件名 `todo(user): ...`）と todo.md の差分
- 記録された意図（このコミットで足された `kind: intent` の行。ref と value）

を短くまとめて出す。最後に「この意図は次の `/todo` から判断基準になる」と一言添える。

ログは `~/.local/log/todo-ai/<今日>/edit-<HHMMSS>.json`（変更案）に残る。
