# TODO 案件見出し Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** やる・待ちを `~/memo/todo-groups.json` の表で案件ごとにまとめ（apply.py の書き出し時と nvim の閉じる時）、nvim で `── <案件> (<件数>) ──` の見出しを仮想行で出す。

**Architecture:** 判定・並べ替えは決定的なコードで Python（`todo_md.py`）と Lua（`lua/todo/core.lua`）に同じ規則で持つ。表は1ファイル。見出しは extmark の `virt_lines_above` で表示だけ。

**Tech Stack:** Python 3（unittest）、Neovim Lua（extmark）

**Spec:** `docs/superpowers/specs/2026-11-13-todo-group-headings-design.md`

## Global Constraints

- 表: `<todo.md のディレクトリ>/todo-groups.json`、形 `{"groups": [{"name": str, "keys": [str], "words": [str]}]}`
- 判定: 表を上から見て最初に当たった案件。`keys` の要素が `#` か `:` で終われば key の前方一致、それ以外は完全一致。`words` は題（key のリンクと ` — next: ` 以降、` (done: …)` を除いた部分。Python の `Item.title`）に部分一致。どれにも当たらなければ `"その他"`
- 並び: 表の順、`その他` は最後。同じ案件の中は元の順（安定）。対象はやる・待ちだけ、完了は触らない
- 表が無い → まとめない・見出しを出さない。読めない（JSON 不正・形違い）→ 同じく何もしない＋ Python は stderr に `todo_md: todo-groups.json を読めない: <理由>` を1行
- 見出しの書式 `── <案件> (<件数>) ──`、ハイライト `Title`
- todo.md の行の形式は変えない。LLM の判断を増やさない
- コメントは非自明な WHY だけ1行。Lua は既存ファイルに合わせダブルクォート

## Review Focus

1. 人の題がリンク（`[officeのteams資料修正](https://...)`）・key の無い行 → words だけで判定され、無ければ その他（Task 1・2）
2. 表が無い・壊れている状態で /todo が無人実行される → apply は今までどおり書き出し、止まらない（Task 1）
3. 同じ案件の行が並べ替え後も元の相対順を保つ（AI の order を壊さない）（Task 1・2）
4. やる・待ちに空行が混じる人の編集 → 並べ替えで行が失われない（Task 2。`count_nonblank` の保護と同じ考え）
5. 見出しの件数が、その連続したかたまりの件数と一致する（並べ替え前の手で足した行で同じ案件が2か所に分かれても、それぞれの件数）（Task 2）

---

### Task 1: Python の判定・並べ替えと apply への組み込み

**Files:**
- Modify: `scripts/todo-ai/todo_md.py`、`scripts/todo-ai/apply.py`（`run` の `new_text = todo_md.render(kept)` の直前）
- Test: `scripts/todo-ai/tests/test_todo_md.py`、`scripts/todo-ai/tests/test_apply.py`

**Interfaces:**
- Produces: `GROUPS_NAME = "todo-groups.json"`、`OTHER_GROUP = "その他"`
- Produces: `load_groups(path: Path) -> list[dict]` — 無ければ `[]`、読めなければ stderr に1行出して `[]`
- Produces: `group_of(item: Item, groups: list[dict]) -> str`
- Produces: `regroup(doc: Doc, groups: list[dict]) -> Doc` — やる・待ちを安定ソートした新しい Doc（groups が空なら同じ並び）。元の doc は変えない

- [ ] **Step 1: テストを書く**（test_todo_md.py に `class GroupTest(unittest.TestCase)`）

```python
G = [{"name": "パイロット", "keys": ["gb:WEB#"], "words": ["パイロット"]},
     {"name": "共通", "keys": ["epc#1176"], "words": []},
     {"name": "シフトオン", "keys": ["epc#"], "words": ["車両"]}]
# group_of
assert group_of(Item("P.11 検索", key="rc:abc", url="u"), G) == "その他"
assert group_of(Item("パイロット P.11", key="rc:abc", url="u"), G) == "パイロット"   # words
assert group_of(Item("バナー", key="gb:WEB#3", url="u"), G) == "パイロット"          # 前方一致
assert group_of(Item("商品カード", key="epc#1176", url="u"), G) == "共通"           # 完全一致が上にある
assert group_of(Item("x", key="epc#11760", url="u"), G) == "シフトオン"             # 完全一致は前方一致しない
assert group_of(Item("車両 [資料](https://x/y)"), G) == "シフトオン"                 # key 無し・題のリンク
assert group_of(Item("a", next="車両を見る"), G) == "その他"                          # next は見ない
# regroup: やるが [その他1, シフト1, パイロット1, シフト2, その他2] → [パイロット1, シフト1, シフト2, その他1, その他2]、待ち・完了も確認（完了は不変）
# regroup(doc, []) は並び不変、元の doc の sections が変わっていない
# load_groups: 無いパス → []、"{" だけのファイル → [] かつ stderr に "todo-groups.json を読めない"、{"groups": [{"name": "a"}]} の keys/words 欠け → [] と警告（形違い）
```

test_apply.py: 既存の apply 実行テストの作り方に合わせ、todo.md と同じディレクトリに todo-groups.json を置いて ops 無し（変更なし）の changes で `run` → 書き出された todo.md のやるが案件順になっていることを確かめる `test_regroups_on_write`。表を置かない同じテストで並びが変わらない `test_no_groups_file_keeps_order`。

- [ ] **Step 2: 失敗を確認** — Run: `python3 -m unittest scripts/todo-ai/tests/test_todo_md.py scripts/todo-ai/tests/test_apply.py` / Expected: `group_of` 等の ImportError・AttributeError で FAIL
- [ ] **Step 3: 実装** — `todo_md.py` に上の3関数。`apply.run` で `kept = todo_md.regroup(kept, todo_md.load_groups(repo / todo_md.GROUPS_NAME))` を render の直前に（`todo_changed` の比較はその後の new_text で行われるので、並び替えだけでも書き出される）
- [ ] **Step 4: 通ることを確認** — Run: `python3 -m unittest discover -s scripts/todo-ai/tests` / Expected: `OK`（変更前 373 件＋追加分）
- [ ] **Step 5: Commit** — `git add scripts/todo-ai/todo_md.py scripts/todo-ai/apply.py scripts/todo-ai/tests/test_todo_md.py scripts/todo-ai/tests/test_apply.py && git commit -m "feat: todo の書き出し時にやる・待ちを案件の表でまとめる"`

### Task 2: Lua の判定・並べ替え・見出しの計算（core.lua）

**Files:**
- Modify: `config/nvim/lua/todo/core.lua`
- Test: `config/nvim/tests/todo_core_spec.lua`

**Interfaces:**
- Consumes: 既存の `M.parse`・`M.detail`（題の終わり＝ `detail[1]`、無ければ ` (done: …)` の前か行末）
- Produces: `M.OTHER_GROUP = "その他"`
- Produces: `M.group_of(line: string, groups: table[]) -> string|nil` — タスク行でなければ nil
- Produces: `M.regroup(lines: string[], groups: table[]) -> string[]` — やる・待ちの欄ごとに、タスク行を安定ソートし、欄内のタスク以外の行（空行）はタスク行の後ろに元の順で置く。groups が空なら同じ内容のコピー
- Produces: `M.group_headings(lines: string[], groups: table[]) -> { row: integer, text: string }[]` — やる・待ちで案件が直前のタスク行と変わる行（欄の先頭のタスク行を含む）の 1-based 行番号と `── <案件> (<連続件数>) ──`。groups が空なら `{}`

- [ ] **Step 1: テストを書く**（Task 1 の G と同じ表を Lua の table で）

```lua
eq(core.group_of("- [ ] バナー [gb:WEB#3](u)", G), "パイロット", "group by key prefix")
eq(core.group_of("- [ ] 商品カード [epc#1176](u)", G), "共通", "exact key wins when listed first")
eq(core.group_of("- [ ] x [epc#11760](u)", G), "シフトオン", "exact key is not a prefix")
eq(core.group_of("- [ ] a [rc:abc](u) — next: 車両を見る", G), "その他", "next is not matched")
eq(core.group_of("- [ ] 車両 [資料](https://x/y)", G), "シフトオン", "words in human link title")
eq(core.group_of("## やる", G), nil, "not a task line")
-- regroup: {"## 確認待ち","1. q [is_task x]","## やる", その他1, シフト1, "", パイロット1, シフト2, "## 待ち", "## 完了", "- [x] シフト済 [epc#1](u) (done: 2026-11-01)"}
--   → やるが パイロット1, シフト1, シフト2, その他1, "" の順。確認待ち・完了は不変。非空行の数が同じ
-- regroup(lines, {}) は同じ内容
-- group_headings: やる [パイロット1, シフト1, シフト2, その他1] + 待ち [シフト3] → 各かたまり先頭の行番号と "── パイロット (1) ──" "── シフトオン (2) ──" "── その他 (1) ──"、待ちの先頭で "── シフトオン (1) ──"
-- group_headings: 並べ替え前で シフト, パイロット, シフト → シフトオン (1) が2回出る
-- group_headings(lines, {}) → {}
```

- [ ] **Step 2: 失敗を確認** — Run: `nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua` / Expected: `group_of` が nil で E5113
- [ ] **Step 3: 実装** — 題と key の切り出しは `M.detail` と共通の内部関数に寄せてよい（判定は Global Constraints どおり、Python と同じ結果）
- [ ] **Step 4: 通ることを確認** — 同じコマンド / Expected: `all passed`
- [ ] **Step 5: Commit** — `git add config/nvim/lua/todo/core.lua config/nvim/tests/todo_core_spec.lua && git commit -m "feat: todo の案件の判定・並べ替え・見出しを core に足す"`

### Task 3: nvim の表示と閉じる時の並べ替え（init.lua）

**Files:**
- Modify: `config/nvim/lua/todo/init.lua`
- Test: `config/nvim/tests/todo_core_spec.lua`（表示ブロック）

**Interfaces:**
- Consumes: `core.group_of`・`core.regroup`・`core.group_headings`（Task 2）
- Produces: `M.groups_path()` → `<M.path の dirname>/todo-groups.json`、`M.load_groups() -> table[]`（無い・読めない → `{}`。`vim.json.decode` を pcall、`groups` が配列で各要素に name/keys/words があるときだけ採用）

- [ ] **Step 1: テストを書く** — 既存の表示テストの一時ディレクトリに todo-groups.json を書き、やるに案件の違う2行を置いた content で:
  - `decorate` 後、各かたまり先頭の行に `virt_lines_above = true` の extmark があり、`virt_lines` が `{ { { "── <案件> (<件数>) ──", "Title" } } }`（`"group heading above first row of each run"`）
  - 表を消して `decorate` → 見出しの extmark が無い（`"no headings without groups file"`）
  - 並びがバラバラの todo.md で `todo.commit()` を呼ぶ（git 管理外のディレクトリなので commit 自体は何もしない作り。並べ替えは commit の git 判定より前に行う）→ ファイルが `core.regroup` の結果になっている（`"commit regroups file"`）。表が無ければファイル不変
- [ ] **Step 2: 失敗を確認** — Run: `nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua` / Expected: 上のテスト名で FAIL
- [ ] **Step 3: 実装**
  - `M.decorate`: `core.group_headings(lines, M.load_groups())` の各行に `{ virt_lines = { { { text, "Title" } } }, virt_lines_above = true }` を `M.ns` で付ける。既存の詳細の仮想行（カーソル行の下）と同じ行に付いても両立させる
  - `M.commit()`: 先頭で、ファイルを `vim.fn.readfile` → `core.regroup` → 変わっていれば `vim.fn.writefile`（非空行の数が減るなら書かずに `vim.notify` で ERROR。`apply()` の保護と同じ）。その後に既存の git 判定・コミット。開いているバッファは閉じる直前なので触らない
  - 表の読み込みは decorate のたびに走る。気になるなら mtime で前回の結果を使い回す（任意）
- [ ] **Step 4: 通ることを確認** — 同じコマンドと `nvim --headless -u NONE -l config/nvim/tests/memo_core_spec.lua` / Expected: どちらも `all passed`
- [ ] **Step 5: Commit** — `git add config/nvim/lua/todo/init.lua config/nvim/tests/todo_core_spec.lua && git commit -m "feat: todo ポップアップに案件の見出しを出し、閉じる時に案件ごとに並べ替える"`

### Task 4: 表の設置・SKILL.md・実機確認

**Files:**
- Create: `~/memo/todo-groups.json`（spec の表そのまま。memo リポジトリに `todo: 案件の表を追加` でコミット）
- Modify: `.claude-global/skills/todo/SKILL.md`（規則 9 の末尾に1文）

- [ ] **Step 1:** SKILL.md 規則 9 に「apply が書き出し時に `todo-groups.json` の案件ごとにまとめるので、order は案件の中の順として効く」を足す
- [ ] **Step 2:** 表を設置し、`python3 -I scripts/todo-ai/context.py` が exit 0、`todo_md.regroup` を今の todo.md に当てた結果を表示して、spec の試作どおりの分かれ方か目で確認
- [ ] **Step 3: Commit** — dotfiles: `git add .claude-global/skills/todo/SKILL.md && git commit -m "docs: /todo の order は案件の中の順として効くと書く"`
- [ ] **Step 4:** main へマージ・push 後（ユーザーの承認を取る）、ユーザーに `C-q t` で開いて見出しの出方をスクショで確認してもらう。並べ替えは、ポップアップを閉じた時か次の /todo の書き出し時に起きる
