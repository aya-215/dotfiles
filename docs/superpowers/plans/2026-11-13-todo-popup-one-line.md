# TODO ポップアップ 1行1タスク表示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/memo/todo.md` を nvim で開いたとき、タスク行を題だけの1画面行で見せ、カーソル行の下に `<key> → <next>` を仮想行で出す。

**Architecture:** 表示だけを変える。`lua/todo/core.lua`（純関数）に「隠す範囲と詳細文字列」を求める `detail` を足し、`conceal_ranges` をそれに合わせる。`lua/todo/init.lua` の表示部で `nowrap`・`concealcursor=n`・カーソル行の `virt_lines` を付ける。render-markdown が描画のたびに `concealcursor` を `''` に戻すので、render-markdown の `on.render` フックから todo バッファだけ `n` に戻す。

**Tech Stack:** Neovim Lua（extmark の conceal / virt_lines）、render-markdown.nvim、テストは `nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua`

**Spec:** `docs/superpowers/specs/2026-11-13-todo-popup-one-line-design.md`

## Global Constraints

- `todo.md` の中身・形式、`scripts/todo-ai/` 配下は一切変えない
- 変更するのは `config/nvim/lua/todo/core.lua`・`config/nvim/lua/todo/init.lua`・`config/nvim/lua/plugins/render-markdown.lua`・`config/nvim/tests/todo_core_spec.lua` だけ
- 文字列の引用符・書き方は既存ファイルに合わせる（このファイル群はダブルクォート）。コメントは非自明な WHY だけ1行で
- 仮想行の書式は `<key> → <next>`（key だけなら `<key>`、next だけなら `→ <next>`）、ハイライトは `Comment`
- key の判定は `scripts/todo-ai/todo_md.py` の `KEY_RE` と同じ種類（`epc#N` `emm#N` `eae#N` `eas#N` `gb:<repo>#N` `rc:<id>` `rc:<id>#N` `mail:<id>` `wt:<name>` `ebpm:No<数字>`）。末尾の `[key](url)` のうち中身が key のものだけが key のリンク

## Review Focus

1. 人の題がリンクそのもの（`- [ ] [officeのteams資料修正](https://...)`）→ key 扱いせず題として見せ、仮想行は出さない（Task 1 のテスト）
2. 完了行の `(done: YYYY-MM-DD)` → 日付は見せたまま key だけ隠す（Task 1）
3. 題に `[a]` や ` — next: ` が入る行 → 最後の ` — next: ` から後ろだけを next とみなす（apply.py の rfind と同じ）（Task 1）
4. カーソルが見出し・確認待ち・空行にある → 仮想行を出さない（Task 2）
5. 挿入モード・conceallevel 0 → 仮想行を出さない。表示の操作でファイルの中身は変わらない（Task 2）

---

### Task 1: core.detail と conceal_ranges の変更

**Files:**
- Modify: `config/nvim/lua/todo/core.lua`（`conceal_ranges` 周辺、`M.NEXT_SEP` の近く）
- Test: `config/nvim/tests/todo_core_spec.lua`（conceal のブロック）

**Interfaces:**
- Produces: `M.detail(line: string) -> { [1]: integer, [2]: integer, [3]: string } | nil` — タスク行（`M.parse` が非 nil）で key のリンクか ` — next: ` がある行だけ返す。`[1]` 隠し始め（0-based byte、key のリンク直前の空白、無ければ最後の ` — next: ` の先頭）、`[2]` 隠し終わり（半開。末尾 ` (done: YYYY-MM-DD)` があればその直前、無ければ `#line`）、`[3]` 仮想行の文字列
- Produces: `M.conceal_ranges(line)` は3番目の要素（代わりの文字）を返さなくなる。タスク行で `detail` があれば `{ d[1], d[2] }` を1つ入れ、`d[1]` より前のリンクだけ従来どおり `[` と `](url)` を隠す。確認待ちのタグ隠しは従来どおり

- [ ] **Step 1: 既存の conceal テストを新仕様に書き換え、detail のテストを足す**

`shown()` の期待値を変える（`r[3]` は使わなくなるが `shown` はそのままでよい）:

```lua
eq(shown("- [ ] 再レビュー [epc#1210](https://github.com/x/pull/1210) — next: 修正を確認"),
  "- [ ] 再レビュー", "hide key link and next on a task line")
eq(shown("- [ ] [officeのteams資料修正](https://somu.example/Disp.do?volumeName=00467&itemID=t1)"),
  "- [ ] officeのteams資料修正", "human title link is not a key")
eq(shown("- [x] 済 [gb:ebase-web#96](http://192.168.0.1:8080/gitbucket/x/pull/96) (done: 2026-11-11)"),
  "- [x] 済 (done: 2026-11-11)", "hide key on a done line, keep the date")
eq(shown("- [ ] a — next: b — next: c"), "- [ ] a — next: b", "next starts at the last separator")
eq(shown("- [ ] [資料](https://x/y) 確認 [epc#1](https://g/1)"), "- [ ] 資料 確認", "title link kept, key hidden")
eq(shown("- [ ] a [x](has space) — next: b"), "- [ ] a [x](has space)", "url with space is not a link")
eq(shown("- [ ] a [foo#1](https://g/1)"), "- [ ] a foo#1", "non-key tail link is a title link")
```

`"1. a — next: b"`・確認待ちタグ・選択肢行・`plain task` の既存テストはそのまま残す。detail のテスト:

```lua
local l = "- [ ] 再レビュー [epc#1210](https://g/1210) — next: 修正を確認"
eq(core.detail(l), { #"- [ ] 再レビュー", #l, "epc#1210 → 修正を確認" }, "detail key and next")
eq(core.detail("- [ ] a [rc:abc#2](https://t/x)")[3], "rc:abc#2", "detail key only")
eq(core.detail("- [ ] a — next: b")[3], "→ b", "detail next only")
eq(core.detail("- [x] 済 [gb:ebase-web#96](http://h/96) (done: 2026-11-11)")[3], "gb:ebase-web#96", "detail on done line")
eq(core.detail("- [ ] [資料](https://x/y)"), nil, "no detail for human title link")
eq(core.detail("- [ ] plain"), nil, "no detail for plain task")
eq(core.detail("1. q — next: b"), nil, "no detail outside task lines")
eq(core.detail("## やる"), nil, "no detail on heading")
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua`
Expected: `FAIL hide key link and next on a task line` 等と `detail` 未定義のエラーで exit 1

- [ ] **Step 3: `M.detail` を実装し、`conceal_ranges` を合わせる**

手順: 末尾の ` (done: YYYY-MM-DD)` を外した範囲で、最後の `M.NEXT_SEP` を探して next を切り出す → 残りの末尾が `[<key>](<空白と括弧を含まない url>)` で、`<key>` が上の key の種類に一致し、直前が空白か本文の先頭ならそれを key とする。key の判定は `local function is_key(s)` に Lua パターンの表で持つ（`gb:` の repo 部は `[^%s%[%]()#]+`）。`conceal_ranges` の `→` 置換（`M.NEXT_ARROW` の3番目要素）は消し、`M.NEXT_ARROW` は `detail` の文字列で使う。

- [ ] **Step 4: テストを走らせて通ることを確認**

Run: `nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua`
Expected: conceal・detail のテストは `ok`。init.lua 側の `arrow shown while conceallevel > 0` 系は Task 2 で直すので、ここで落ちてよいのはその3件と `cursor row shows raw text` だけ

- [ ] **Step 5: Commit**

```bash
git add config/nvim/lua/todo/core.lua config/nvim/tests/todo_core_spec.lua
git commit -m "feat: todo のタスク行で key と next を隠す範囲を detail で求める"
```

### Task 2: 表示（nowrap・カーソル行の仮想行・render-markdown フック）

**Files:**
- Modify: `config/nvim/lua/todo/init.lua`（`M.decorate`・`set_view_options`・新規 `M.on_render`）
- Modify: `config/nvim/lua/plugins/render-markdown.lua`（opts に `on.render`）
- Test: `config/nvim/tests/todo_core_spec.lua`（「表示の conceal はファイルを変えず…」のブロック）

**Interfaces:**
- Consumes: `core.detail(line)`、`core.conceal_ranges(line)`（Task 1）
- Produces: `M.on_render(ctx: { buf: integer, win: integer })` — `vim.b[ctx.buf].todo_view` のときだけ `ctx.win` の `concealcursor` を `"n"` にする

- [ ] **Step 1: 表示のテストを書き換える**

既存ブロックの `arrows()` と `cursor row shows raw text` を置き換える:

```lua
eq(vim.wo.wrap, false, "todo window nowrap")
eq(vim.wo.concealcursor, "n", "todo window conceals cursor line in normal mode")
-- M.ns の extmark のうち details.virt_lines を持つものの行（1-based、昇順）
local function virt_rows() end
-- 指定行の virt_lines（details.virt_lines）をそのまま返す
local function virt_lines_at(row) end
vim.api.nvim_win_set_cursor(0, { 9, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
eq(marked_rows()[9], true, "cursor task row is also concealed")
eq(virt_rows(), { 9 }, "virt line under cursor task row")
eq(virt_lines_at(9), { { { "epc#1 → b", "Comment" } } }, "virt line text")
vim.api.nvim_win_set_cursor(0, { 8, 0 })  -- ## やる
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
eq(virt_rows(), {}, "no virt line on heading")
vim.api.nvim_win_set_cursor(0, { 4, 0 })  -- 確認待ちの問い
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
eq(virt_rows(), {}, "no virt line on confirm row")
vim.api.nvim_win_set_cursor(0, { 9, 0 })
vim.wo.conceallevel = 0
eq(virt_rows(), {}, "no virt line when conceallevel is 0 (render-markdown in insert mode)")
vim.wo.conceallevel = 2
eq(virt_rows(), { 9 }, "virt line back when conceallevel returns")
vim.wo.concealcursor = ""
todo.on_render({ buf = buf, win = vim.api.nvim_get_current_win() })
eq(vim.wo.concealcursor, "n", "on_render restores concealcursor for todo buffer")
```

`conceal marks on tag and task rows`・`conceal does not change file contents` は残す。別の markdown バッファ（`vim.cmd.enew()` 等）で `on_render` を呼んでも `concealcursor` を変えないテストも足す（`"on_render ignores other buffers"`）。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua`
Expected: `FAIL todo window nowrap` 等で exit 1

- [ ] **Step 3: init.lua を実装**

- `set_view_options`: `wrap=false`、`concealcursor="n"` を足す（`conceallevel=2` はそのまま）
- `M.decorate`: カーソル行も含め全行に `conceal_ranges` の conceal を付ける（`virt_text` の矢印処理は消す）。カーソル行で `core.detail` が非 nil、かつ窓の `conceallevel > 0`、かつモードが挿入でない（`vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i"`）なら、その行に `virt_lines = { { { d[3], "Comment" } } }` の extmark を同じ `M.ns` で付ける
- `M.on_render(ctx)`: 上の Interfaces どおり。ウィンドウが無効なら何もしない

- [ ] **Step 4: render-markdown.lua に `on` を足す**

```lua
-- 描画のたびに concealcursor を '' に戻されるので、todo.md だけカーソル行も隠す
on = {
  render = function(ctx)
    require("todo").on_render(ctx)
  end,
},
```

- [ ] **Step 5: テストを走らせて全部通ることを確認**

Run: `nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua`
Expected: 最後が `all passed`、exit 0。あわせて `nvim --headless -u NONE -l config/nvim/tests/memo_core_spec.lua` も `all passed`（共通の表示を壊していない確認）

- [ ] **Step 6: Commit**

```bash
git add config/nvim/lua/todo/init.lua config/nvim/lua/plugins/render-markdown.lua config/nvim/tests/todo_core_spec.lua
git commit -m "feat: todo ポップアップを nowrap にし、カーソル行の下に key と next を出す"
```

### Task 3: 実機確認

- [ ] **Step 1:** `git push` 後、ユーザーに `C-q t` でポップアップを開いてもらい、次をスクショで確認する: やるの各行が1画面行で題だけ／カーソル行の下に `epc#1211 → …` が薄字で出る／確認待ちの4番目の下にあった空白行が消えている／`i` で挿入モードにすると生の行に戻り仮想行が消える／`q` で閉じた後 `git -C ~/memo diff` が空（表示で中身が変わっていない）
