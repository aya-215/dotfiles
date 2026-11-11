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
| `.claude-global/skills/todo/SKILL.md` | `/todo` と `/todo review` |

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

AI の変更が違っていたら、nvim で直せばよい。git 履歴から検出して記録する。

- AI が足した行を消す → その key は二度と足さない（`reject_add`）
- AI が移した行を元のセクションへ戻す → その行を、戻された移動先へは二度と移さない（`revert_move`）。別のセクションへの移動は止めない。たとえば AI が待ちにした PR を `<Tab>` でやるに戻しても、マージされれば同期が完了へ移す
- `/todo-edit`（source user）で完了から戻した行は、戻し先によらず完了へは二度と移さない（`revert_move` の to=完了）。同期が毎時また完了にするのを防ぐ代わりに、本当に終わったら手で完了にする

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
| `git -C ~/memo log` | AI・同期の変更と理由（`todo(ai): ` / `todo(sync): ` の本文。飛ばした op は `skip: ...`） |
| `~/memo/todo-decisions.jsonl` | 人の判断の記録 |

`/todo` は過去のログを読まない（AI の過去の推測が事実として戻ってくるため）。読むのは `review.py` だけ。

## やっていないこと

- GitBucket の状態は `/todo` 実行時に AI が読み取りで見るだけで、cron の同期は GitHub だけ
