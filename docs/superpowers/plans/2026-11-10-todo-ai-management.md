# 業務TODOのAI管理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/memo/todo.md` を、AI が元リンクと Next 付きで書き・動かし、判断が要るものだけ先頭の確認待ちに並べる台帳にする。

**Architecture:** todo.md への書き込み口は決定的な Python スクリプト `apply.py` だけ。GitHub 同期（AI なし・毎時 cron）と AI 実行（`/todo` スキル、平日朝に `claude -p` で無人実行）はどちらも「変更案 JSON」を作って `apply.py` に渡す。人の判断は `todo-decisions.jsonl` に決定的に記録し、蒸し返しと取り合いを防ぐ。

**Tech Stack:** Python 3（標準ライブラリのみ、`unittest`）、bash、Neovim Lua（`nvim -l` の自前テスト）、gh CLI、Claude Code スキル、crontab。

**Spec:** `docs/superpowers/specs/2026-11-10-todo-ai-management-design.md`

## Global Constraints

- 台帳: `~/memo/todo.md`（remote の無いローカル git）。全スクリプトは `TODO_MD_PATH` で差し替え可能にし、テストは実ファイルを触らない（既存 `todo/init.lua` と同じ）
- 見出しは上から `## 確認待ち` → `## やる` → `## 待ち` → `## 完了`
- タスク行: `- [ ] <title> [<key>](<url>) — next: <next>`（リンク・next は任意）。完了行は末尾に ` (done: YYYY-MM-DD)`
- key 形式: GitHub `<repo略称>#<番号>`（略称: `epc`=ebase-portal-chat, `emm`=ebase-middleware-mcp, `eae`=eb-api-extended, `eas`=ebase-agent-specs）、GitBucket `gb:<repo>#<番号>`、Rocket Chat `rc:<_id>`（1発言に複数作業は `rc:<_id>#1`）、メール `mail:<Message-ID の @ より前>`、worktree `wt:<worktree名>`
- コミット: 人 `todo: YYYY-MM-DD HH:MM`（既存）、AI `todo(ai): <要約>`、同期 `todo(sync): <要約>`。AI/同期コミットの本文に変更ごとの理由と根拠リンク
- `ebase-dev/*` への gh は必ず `GH_TOKEN=$(gh auth token --user eBASE-Mori)`。未指定はアクティブアカウントへ無言で落ちる
- `claude -p` は `--settings '{"disableAllHooks":true}'` を付ける（SessionEnd 要約 hook の再帰発火防止）
- cron から呼ぶスクリプトは先頭で `export LANG=C.UTF-8`
- AI・スクリプトは外部アクション（PR コメント・RC 送信・Issue 作成）をしない
- コードコメントは `.claude-global/rules/code-comments.md` に従う（非自明な WHY だけ、1行）
- dotfiles のコミットプレフィックス `feat:` `fix:` `docs:` `chore:`。コミット後 push

## Review Focus

1. cron 発火時にポップアップで todo.md を編集中 → 書かずにスキップし、次回に回す。nvim が落ちて古いロックが残っても永久に止まらない（Task 1, 4）
2. 人が見出しを消した・確認待ち欄に自由文を書いた・タイトルに `— next:` や `](` を含めた → `apply.py` は壊さず、解釈できなければ書かずにエラー終了（Task 2, 4）
3. gh の認証失敗・アカウント取り違え・API エラー → 同期は何も完了に移さない（「取れなかった」を「閉じた」と扱わない）（Task 6）
4. 同期 cron と AI 実行が同時に走る → 書き込みは排他（flock）で直列化（Task 4）
5. 同じタイトルの行が2つある・人の行に AI が付け足した後に人がタイトルを直した → 出どころ判定と文言保護が誤爆しない（Task 3, 4）

---

## File Structure

| ファイル | 責務 |
|---|---|
| `config/nvim/lua/todo/core.lua` | 新しい見出し・完了日付への対応（純関数） |
| `config/nvim/lua/todo/init.lua` | ポップアップを開いている間のロックファイル |
| `config/nvim/tests/todo_core_spec.lua` | 上記のテスト |
| `scripts/todo-ai/todo_md.py` | todo.md ⇄ モデルの parse / render（純関数） |
| `scripts/todo-ai/origin.py` | 行の出どころ（ai / human）を git から判定 |
| `scripts/todo-ai/decisions.py` | 判断記録の読み書きと、人の戻しの検出 |
| `scripts/todo-ai/apply.py` | 唯一の書き込み口（検証・ロック・排他・アーカイブ・コミット） |
| `scripts/todo-ai/sync_github.py` | GitHub 状態から変更案を作る（AI なし） |
| `scripts/todo-ai/migrate.py` | 既存 todo.md を新形式へ一度だけ変換 |
| `scripts/todo-ai/review.py` | 週次見直し用に人の訂正を一覧化 |
| `scripts/todo-ai/run-unattended.sh` | cron から `claude -p` で `/todo` を回す |
| `scripts/todo-ai/tests/test_*.py` | `python3 -m unittest discover -s scripts/todo-ai/tests` |
| `.claude-global/skills/my-tasks/SKILL.md` | JSON 出力モードの追加 |
| `.claude-global/skills/todo/SKILL.md` | `/todo`（同期→収集→変更案→適用、`review` モード） |
| `docs/todo-ai.md` | 使い方・cron 設定・トラブル時の見方 |

## 変更案 JSON（Task 4 以降の共通インターフェース）

```json
{
  "source": "ai",
  "ops": [
    {"op": "add", "section": "やる", "key": "epc#1163", "url": "https://...", "title": "PR#1163 レビュー指摘対応", "next": "N1,N2 を直して push", "reason": "..."},
    {"op": "move", "ref": "epc#1202", "to": "待ち", "reason": "..."},
    {"op": "set_next", "ref": "epc#1163", "next": "...", "reason": "..."},
    {"op": "attach", "ref": "title:インターン資料修正", "key": "rc:abc", "url": "...", "next": "...", "reason": "..."},
    {"op": "order", "section": "やる", "refs": ["epc#1163", "title:インターン資料修正"]}
  ],
  "confirm": [
    {"ref": "epc#1202", "kind": "policy", "question": "...", "facts": "...", "options": [{"label": "A", "text": "...", "recommended": true}]}
  ],
  "answered": [{"ref": "epc#1202", "kind": "policy", "answer": "A"}]
}
```

- `ref` は key、またはリンクの無い行なら `title:<タイトル完全一致>`
- `source` は `ai` か `sync`。`confirm` は毎回全置換（番号は apply が 1 から振る）
- `kind` の値: `policy`（方針）, `before_share`（人に見せる前）, `manual`（自分の手作業）, `conflict`（人と AI の食い違い）, `is_task`（これはタスク？）, `still_needed`（14日経過）

---

### Task 0: `claude -p` の課金確認（ゲート）

**Files:** なし（結果を `docs/todo-ai.md` の冒頭に1行記録するのは Task 9）

- [ ] **Step 1:** ユーザーに claude.ai の使用量画面（Settings → Usage）の現在値を控えてもらう
- [ ] **Step 2:** 次を実行（auto mode で止まる場合はユーザーに `!` で打ってもらい、コマンドをクリップボードへ入れる）

```bash
echo "1+1 は？数字だけ" | claude -p --model haiku --no-session-persistence --settings '{"disableAllHooks":true}'
```

Expected: `2`

- [ ] **Step 3:** ユーザーに使用量画面を再確認してもらい、「サブスク枠で消費」か「クレジット消費」かを記録する
- [ ] **Step 4:** クレジット消費だった場合は止まり、ユーザーに金額を見て判断してもらう（Task 8 以降の無人実行の可否）。Task 1〜7 は判断を待たずに進めてよい

---

### Task 1: nvim の todo を新形式に対応させる

**Files:**
- Modify: `config/nvim/lua/todo/core.lua`
- Modify: `config/nvim/lua/todo/init.lua`
- Test: `config/nvim/tests/todo_core_spec.lua`

**Interfaces:**
- Produces: ロックファイル `<todo.md のディレクトリ>/.todo.lock`（中身は nvim の PID）。`apply.py` が読む
- Produces: 完了行の末尾 ` (done: YYYY-MM-DD)`

- [ ] **Step 1: 失敗するテストを足す**（既存の `eq` を使う）
  - `skeleton()` が `{ "# TODO", "", "## 確認待ち", "", "## やる", "", "## 待ち", "", "## 完了" }`
  - `open_area_end` が `## やる` の直後から `## 待ち` 直前までを未完了エリアとし、`## 確認待ち` の番号付き行を含めない
  - `toggle`（やる→完了）で完了行が `- [x] a (done: 2026-11-10)` になる（日付は `core.today` を差し替え可能な関数にしてテストで固定）
  - `toggle`（完了→やる）で ` (done: …)` が外れる
  - `- [ ] a [epc#1](https://x) — next: b` を toggle しても行の中身（リンク・next）が保たれる
  - `## やる` 見出しが無い旧形式ファイルでも toggle が行を失わない
- [ ] **Step 2:** `nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua` → 新規分が FAIL
- [ ] **Step 3:** `core.lua` を修正。`M.TODO_HEADING = "## やる"`、`M.CONFIRM_HEADING = "## 確認待ち"` を足し、`open_area_end` の開始を `## やる` の次の行に（無ければ従来どおりファイル先頭）。完了化で日付付与、未完了化で `%s%(done: %d+%-%d+%-%d+%)$` を除去
- [ ] **Step 4:** テスト再実行 → `FAIL` 行なし
- [ ] **Step 5:** `init.lua` の `BufRead`/`BufNewFile` で `.todo.lock` に `vim.fn.getpid()` を書き、`quit()` と `VimLeavePre` で消す。`new_task` は `## 確認待ち` エリア内では素の `o`/`O` を返す
- [ ] **Step 6:** 手動確認: `TODO_MD_PATH=/tmp/claude-1000/todo-test.md nvim` で開いてロックが出来る・`q` で消える・`o` で `## やる` に `- [ ] ` が入る
- [ ] **Step 7:** コミット `feat: todo.md を確認待ち・やる見出しと完了日付に対応させる`

---

### Task 2: todo.md のモデル（parse / render）

**Files:**
- Create: `scripts/todo-ai/todo_md.py`
- Test: `scripts/todo-ai/tests/test_todo_md.py`

**Interfaces:**
- Produces:
  - `@dataclass Item: title: str; key: str|None; url: str|None; next: str|None; done: bool; done_date: str|None; raw: str`
  - `@dataclass Doc: preamble: list[str]; confirm: list[str]; sections: dict[str, list[Item]]`（キーは `"やる" "待ち" "完了"`）
  - `parse(text: str) -> Doc`（見出しが欠けている・未知の見出しがある・タスク以外の行が `## やる`/`## 待ち`/`## 完了` にある場合は `ParseError`）
  - `render(doc: Doc) -> str`
  - `Item.ref -> str`（key があれば key、無ければ `"title:" + title`）

- [ ] **Step 1: テスト**
  - `test_roundtrip`: Global Constraints の書式の行を含むファイルが `render(parse(x)) == x`
  - `test_item_fields`: `- [ ] PR#1163 対応 [epc#1163](https://g/1163) — next: N1 残` → title=`PR#1163 対応`, key=`epc#1163`, url=`https://g/1163`, next=`N1 残`
  - `test_title_only_link`: `- [ ] [officeのteams資料修正](https://somu/x)` → title=`[officeのteams資料修正](https://somu/x)`, key=None（key 形式に一致しないリンクはタイトルの一部）
  - `test_title_with_next_marker`: タイトルに ` — next: ` が2回あっても最後の1つで分割
  - `test_done_date`: `- [x] a (done: 2026-11-10)` → done=True, done_date=`2026-11-10`
  - `test_missing_heading_raises`: `## 待ち` が無い → `ParseError`
  - `test_free_text_in_section_raises`: `## やる` に `メモ` という行 → `ParseError`
  - `test_confirm_kept_verbatim`: `## 確認待ち` 配下は行のまま `confirm` に保持され、回答欄の自由文も壊れない
- [ ] **Step 2:** `python3 -m unittest discover -s scripts/todo-ai/tests` → FAIL
- [ ] **Step 3:** 実装。key 判定の正規表現は Global Constraints の key 形式だけを受け付ける
- [ ] **Step 4:** テスト → OK
- [ ] **Step 5:** コミット `feat: todo.md の parse/render を追加`

---

### Task 3: 既存 todo.md の移行と、行の出どころ判定

**Files:**
- Create: `scripts/todo-ai/migrate.py`, `scripts/todo-ai/origin.py`
- Test: `scripts/todo-ai/tests/test_migrate.py`, `scripts/todo-ai/tests/test_origin.py`

**Interfaces:**
- Consumes: `todo_md.parse/render`
- Produces: `origin_of(repo: Path, path: str, title: str) -> Literal["ai", "human"]` — `git log -S<title> --reverse --format=%s -- <path>` の最初のコミット件名が `todo(ai):` で始まれば `ai`、それ以外 `human`。同タイトルが複数あれば `human`（保護側に倒す）
- Produces: `migrate(text: str) -> str` — 見出しなしの未完了エリアを `## やる` に入れ、先頭に空の `## 確認待ち` を足す。タスクの文言は変えない

- [ ] **Step 1: テスト**
  - `test_migrate_current_shape`: 今の todo.md と同じ形（`# TODO` 直下に未完了、空行区切り、`## 待ち`、`## 完了`）→ 新形式。非空タスク行の集合が変換前後で同じ
  - `test_migrate_idempotent`: 新形式に再適用しても不変
  - `test_origin_ai` / `test_origin_human`: 一時 git リポジトリで `todo(ai):` / `todo:` コミットにより行を入れ、その後 `todo:` コミットで行を別セクションへ移しても判定が変わらない
  - `test_origin_duplicate_title_is_human`
- [ ] **Step 2:** FAIL を確認 → 実装 → OK
- [ ] **Step 3:** 実ファイル移行: `cp ~/memo/todo.md` をスクラッチへ退避 → `python3 scripts/todo-ai/migrate.py ~/memo/todo.md` → 差分をユーザーに見せて OK をもらう → `git -C ~/memo commit -m "todo: 新形式へ移行"`（人のコミット扱い）
- [ ] **Step 4:** コミット `feat: todo.md 移行と行の出どころ判定を追加`

---

### Task 4: 唯一の書き込み口 `apply.py`

**Files:**
- Create: `scripts/todo-ai/apply.py`
- Test: `scripts/todo-ai/tests/test_apply.py`

**Interfaces:**
- Consumes: `todo_md`, `origin_of`, 変更案 JSON
- Produces: CLI `apply.py --changes <json> [--todo PATH] [--decisions PATH] [--today YYYY-MM-DD]`
  - 終了コード: 0 適用（変更なし含む）、3 ロック中でスキップ、2 検証違反で未適用、1 その他
  - 関数 `apply_changes(doc: Doc, changes: dict, origins: Callable[[str], str], today: str) -> tuple[Doc, list[str]]`（純関数。2要素目はコミット本文の行）

- [ ] **Step 1: テスト**（純関数部分と CLI を一時 git リポジトリで）
  - `test_add_goes_to_section_with_link_and_next`
  - `test_move_to_done_adds_date` / `test_set_next_replaces_only_next`
  - `test_attach_to_human_line_keeps_title`: `attach` 後も title が一字一句同じ
  - `test_reject_reopen`: `source` が `ai`/`sync` で `完了→やる/待ち` の move → 終了コード 2・ファイル不変
  - `test_reject_human_title_change`: human 由来行の title が変わる結果になる op → 2
  - `test_reject_line_loss`: 非空タスク行が減る（アーカイブ分を除く）→ 2
  - `test_unknown_ref`: 存在しない ref への move → その op だけ無視して本文に `skip: unknown ref` を記録（全体は適用）
  - `test_confirm_rendered`: `confirm` が `1. <question>` / `   事実: <facts>` / `   選択: A <text>（おすすめ） / B <text>` / `   回答:` の形で `## 確認待ち` を全置換
  - `test_lock_skip`: `.todo.lock` に生存 PID（`os.getpid()`）→ 3・不変。存在しない PID → ロックを消して適用
  - `test_archive_30days`: `done_date` が `today` の31日前の完了行は `todo-archive/YYYY-MM.md`（完了月）に追記され本文から消える。30日前は残る
  - `test_commit_message`: `source=ai` → 件名 `todo(ai): ` で始まり本文に各 op の reason と url
  - `test_parse_error_exit2`: 壊れた todo.md → 2・不変
- [ ] **Step 2:** FAIL を確認
- [ ] **Step 3:** 実装。書き込み全体を `fcntl.flock(<todo dir>/.todo.write.lock)` で排他。`order` は指定外の行を元の相対順で末尾に残す。コミットは `git -C <dir> add <todo.md> todo-archive todo-decisions.jsonl` の対象ファイルだけ
- [ ] **Step 4:** テスト → OK
- [ ] **Step 5:** コミット `feat: todo.md の唯一の書き込み口 apply.py を追加`

---

### Task 5: 判断の記録と、人の戻しの検出

**Files:**
- Create: `scripts/todo-ai/decisions.py`
- Modify: `scripts/todo-ai/apply.py`（`answered` の記録、適用前に `detect_reverts` を呼んで記録）
- Test: `scripts/todo-ai/tests/test_decisions.py`

**Interfaces:**
- Produces:
  - 1行の形式 `{"ts": ISO8601, "ref": str, "kind": str, "value": str, "by": "human"}`。`kind` は確認待ちの kind、または `revert_move` / `reject_add`
  - `load(path) -> list[dict]`, `append(path, records)`
  - `is_pinned(records, ref) -> bool`（`revert_move` がある ref は同期が動かさない）
  - `already_answered(records, ref, kind) -> dict|None`
  - `detect_reverts(repo: Path, path: str) -> list[dict]`: 最新の `todo(ai)`/`todo(sync)` コミット C について、C の親・C・HEAD の3時点でセクションを比べ、C で動いた ref が HEAD で C の親と同じセクションに戻っていれば `revert_move`、C で足された ref が HEAD に無ければ `reject_add`。同じ C について二重記録しない（記録に `commit` を持たせる）

- [ ] **Step 1: テスト**: 一時 git リポジトリで「AI が待ちへ→人がやるへ戻す」「AI が追加→人が消す」「AI が完了へ→人がそのまま」の3パターン。3つ目は記録なし。2回呼んでも件数が増えない
- [ ] **Step 2:** FAIL → 実装 → OK
- [ ] **Step 3:** コミット `feat: 人の判断の記録と戻しの検出を追加`

---

### Task 6: GitHub 同期（AI なし）

**Files:**
- Create: `scripts/todo-ai/sync_github.py`
- Test: `scripts/todo-ai/tests/test_sync_github.py`

**Interfaces:**
- Consumes: `todo_md.parse`, `decisions.is_pinned`, `apply.py`
- Produces: CLI `sync_github.py [--todo PATH] [--dry-run]`。GitHub の key（`epc#` 等）を持つ未完了行の状態を `gh api` で取り、MERGED/CLOSED の行に `move → 完了` を作って `apply.py`（`source: sync`）に渡す
  - 状態取得関数 `fetch_state(repo: str, number: int) -> Literal["open","closed","merged"] | None`（失敗時 None）は差し替え可能にしてテストでモック

- [ ] **Step 1: テスト**
  - `test_merged_moves_to_done` / `test_open_untouched`
  - `test_fetch_failure_moves_nothing`: `fetch_state` が None → op なし
  - `test_pinned_untouched`: `revert_move` 記録のある ref は MERGED でも動かさない
  - `test_gitbucket_keys_ignored`: `gb:` は対象外（AI 実行側が判定する）
- [ ] **Step 2:** FAIL → 実装（`GH_TOKEN=$(gh auth token --user eBASE-Mori)` を subprocess の env に明示）→ OK
- [ ] **Step 3:** 実データで `--dry-run` を実行し、出力された op をユーザーに見せる
- [ ] **Step 4:** crontab に追記（ユーザーに `crontab -e` を依頼し、行をクリップボードへ）: `0 8-20 * * 1-5 /home/aya/.dotfiles/scripts/todo-ai/sync_github.py >> /home/aya/.local/log/todo-ai/sync.log 2>&1`
- [ ] **Step 5:** コミット `feat: GitHub の状態で todo を完了に移す同期を追加`

---

### Task 7: `/my-tasks` の JSON 出力モード

**Files:**
- Modify: `.claude-global/skills/my-tasks/SKILL.md`（末尾に「JSON 出力モード」節を追加。既存手順は変えない）

**Interfaces:**
- Produces: 引数 `--json <path>` のとき、Step 2.5 の検証ゲート後の結果を次の形で `<path>` に書く（チャットには件数だけ出す）

```json
{"generated_at": "ISO8601", "window": {"from": "YYYY-MM-DD", "to": "YYYY-MM-DD"},
 "candidates": [{"key": "rc:abc#1", "url": "...", "title": "...", "ball": "mine|theirs|maybe_done",
   "next": "...", "evidence": "一次データの抜粋（1〜2行）", "deadline": "YYYY-MM-DD|null",
   "waiting_person": "名前|null", "blocks": ["key", "..."]}]}
```

- 「やらないこと: ファイル保存」は「チャットモードでは」に限定する旨を書き換える
- key は Global Constraints の形式。一次データまで遡れない候補は `key: null` で出す

- [ ] **Step 1:** 節を追加
- [ ] **Step 2:** 検証: 対話セッションで `/my-tasks --json /tmp/claude-1000/my-tasks.json` を実行し、`python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert all(set(c)>={'key','url','title','ball'} for c in d['candidates'])" /tmp/claude-1000/my-tasks.json` が通る。チャットモードの出力に変化がないことも1回確認
- [ ] **Step 3:** コミット `feat: my-tasks に JSON 出力モードを追加`

---

### Task 8: `/todo` スキル

**Files:**
- Create: `.claude-global/skills/todo/SKILL.md`

**Interfaces:**
- Consumes: `sync_github.py`, `/my-tasks --json`, `decisions.load/already_answered`, `apply.py`
- Produces: `/todo`（通常）と `/todo review`（Task 10）

SKILL.md に書く手順（通常モード）:
1. `sync_github.py` を実行
2. サブエージェントで `/my-tasks --json ~/.local/log/todo-ai/<日付>/my-tasks.json` を実行（todo.md・過去ログを根拠に読まない旨を明記）
3. `todo.md` を parse し、`ref` と候補 `key` で突き合わせて変更案を作る。規則:
   - 候補にあって台帳に無い `mine`/`theirs` → `add`（`mine`=やる、`theirs`=待ち）
   - `maybe_done` で evidence に決着がある → `move → 完了`
   - 台帳の rc:/mail: 行で、決着も進展も無く最初の追加から14日超（`git log -S` で追加日を取る）→ `confirm kind=still_needed`
   - リンクの無い人の行に一致しそうな候補 → `attach`
   - `key: null` の候補 → `confirm kind=is_task`（`already_answered` 済みは出さない）
   - 人が完了にした行の元がまだ open → `confirm kind=conflict`
   - `## やる` の順: `waiting_person` あり → `deadline` 昇順 → `blocks` が多い順 → 元の順
   - 自分の PR の未対応レビュー指摘は next に `N1,N2 残` の形
   - 確認待ちの書式: question は「決めること」1行、facts は判断に要る事実だけ、選択肢におすすめを1つ
4. `## 確認待ち` の `回答:` に書かれたものを `answered` に入れ、その項目は `confirm` から外し、回答内容に沿った op を作る
5. 変更案を `~/.local/log/todo-ai/<日付>/changes.json` に保存し `apply.py --changes` に渡す。終了コード 3 なら「編集中のためスキップ」と報告、2 なら違反内容を報告して終わる

- [ ] **Step 1:** SKILL.md を作成（description に「/todo」「TODO更新」「todo を最新にして」）
- [ ] **Step 2:** 検証: 対話セッションで `/todo` を実行 → `git -C ~/memo log -1` が `todo(ai):`、`## 確認待ち` が Global の書式、人の行のタイトルが不変（`git -C ~/memo diff HEAD~1 -- todo.md` をユーザーと一緒に見る）
- [ ] **Step 3:** 1つの確認待ちに `回答: A` と書いて再度 `/todo` → その項目が消え、`todo-decisions.jsonl` に1行増える。もう一度 `/todo` しても同じ問いが出ない
- [ ] **Step 4:** コミット `feat: todo を AI が更新する /todo スキルを追加`

---

### Task 9: 無人実行（Task 0 の結果が OK の場合のみ）

**Files:**
- Create: `scripts/todo-ai/run-unattended.sh`, `scripts/todo-ai/run-unattended-test.sh`
- Create: `docs/todo-ai.md`

**Interfaces:**
- Consumes: `/todo`
- Produces: `run-unattended.sh [--dry-run]`。`claude -p "/todo" --settings '{"disableAllHooks":true}'` を `~/.dotfiles` で実行し、標準出力を `~/.local/log/todo-ai/<日付>/run.log` へ。二重起動は `flock` で防ぐ。`--dry-run` は実行コマンドを表示するだけ

- [ ] **Step 1:** `run-unattended-test.sh`（既存 `*-test.sh` の `check` 形式）: `CLAUDE_BIN` を echo するスタブに差し替え、`--dry-run` の出力に `disableAllHooks` と `/todo` が含まれる・ロック取得中の2回目は即終了する、を確認 → FAIL → 実装 → `ALL OK`
- [ ] **Step 2:** 手動で1回本実行し、`run.log` と `git -C ~/memo log -1` を確認
- [ ] **Step 3:** crontab に追記（ユーザーに依頼・クリップボード）: `0 7 * * 1-5 /home/aya/.dotfiles/scripts/todo-ai/run-unattended.sh >> /home/aya/.local/log/todo-ai/cron.log 2>&1`
- [ ] **Step 4:** `docs/todo-ai.md` に使い方・cron 2行・Task 0 の課金確認結果・ログの場所・終了コードの意味
- [ ] **Step 5:** コミット `feat: todo の AI 更新を平日朝に無人実行する`

---

### Task 10: 週次見直し（`/my-tasks` を使いながら直す）

**Files:**
- Create: `scripts/todo-ai/review.py`
- Test: `scripts/todo-ai/tests/test_review.py`
- Modify: `.claude-global/skills/todo/SKILL.md`（`review` モード節）

**Interfaces:**
- Consumes: `decisions.load`、`~/.local/log/todo-ai/*/changes.json`
- Produces: `review.py --since YYYY-MM-DD` → 人の訂正（`revert_move` / `reject_add` / `conflict` への回答）を、元の op の reason と my-tasks の evidence と並べた Markdown 表で標準出力

- [ ] **Step 1: テスト**: 記録2件と changes.json 1件から、ref ごとに「AI がしたこと / 人がしたこと / AI の根拠」の行が出る
- [ ] **Step 2:** FAIL → 実装 → OK
- [ ] **Step 3:** SKILL.md の `review` モード: `review.py --since <7日前>` の結果を、agent-memory `scripts/task-inventory-verification-gate.md` の3層（取得層・判定層・解釈層）に振り分け、`/my-tasks` か `/todo` のどこを直すかの案を出して止まる（修正はユーザーの OK 後）
- [ ] **Step 4:** 既存の金曜 18:00 週次リマインド（life `review-reminder.yml`）の本文に `/todo review` を足すかはユーザーに確認（外部リポジトリの変更のため）
- [ ] **Step 5:** コミット `feat: todo の週次見直し（人の訂正の一覧化）を追加`
