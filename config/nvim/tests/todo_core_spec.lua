-- 実行: nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
-- nvim の rtp ローダーが ~/.config/nvim の同名モジュールを先に拾うため、rtp にも足す
vim.opt.rtp:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local core = require("todo.core")
local failures = 0

core.today = function() return "2026-11-10" end

local function eq(actual, expected, name)
  if vim.deep_equal(actual, expected) then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name)
    print("  expected: " .. vim.inspect(expected))
    print("  actual:   " .. vim.inspect(actual))
  end
end

-- parse
eq(core.parse("- [ ] foo @tag"), { done = false, text = "foo @tag" }, "parse open task")
eq(core.parse("- [x] foo"), { done = true, text = "foo" }, "parse done task")
eq(core.parse("- [X] foo"), { done = true, text = "foo" }, "parse done task (upper)")
eq(core.parse("  - [ ] indented"), { done = false, text = "indented" }, "parse indented task")
eq(core.parse("## 完了"), nil, "parse heading -> nil")
eq(core.parse("- plain list"), nil, "parse plain list -> nil")
eq(core.parse(""), nil, "parse empty -> nil")

-- find_done_heading
eq(core.find_done_heading({ "# TODO", "- [ ] a", "", "## 完了", "- [x] b" }), 4, "find heading")
eq(core.find_done_heading({ "# TODO", "- [ ] a" }), nil, "no heading -> nil")

-- toggle: open -> done, moves to just below heading
do
  local lines = { "# TODO", "- [ ] a", "- [ ] b", "", "## 完了", "- [x] old" }
  local out, row = core.toggle(lines, 2)
  eq(out, { "# TODO", "- [ ] b", "", "## 完了", "- [x] a (done: 2026-11-10)", "- [x] old" }, "toggle open->done lines")
  eq(row, 5, "toggle open->done cursor follows to done section")
end

-- toggle: done -> open, appended to end of open area (before blank+heading)
do
  local lines = { "# TODO", "- [ ] a", "", "## 完了", "- [x] b", "- [x] c" }
  local out, row = core.toggle(lines, 5)
  eq(out, { "# TODO", "- [ ] a", "- [ ] b", "", "## 完了", "- [x] c" }, "toggle done->open lines")
  eq(row, 3, "toggle done->open cursor follows the item")
end

-- toggle: heading missing -> created at end
do
  local lines = { "# TODO", "- [ ] a" }
  local out = core.toggle(lines, 2)
  eq(out, { "# TODO", "", "## 完了", "- [x] a (done: 2026-11-10)" }, "toggle creates heading when missing")
end

-- toggle: non-task line -> unchanged
do
  local lines = { "# TODO", "- [ ] a", "", "## 完了" }
  local out, row = core.toggle(lines, 1)
  eq(out, lines, "toggle non-task -> unchanged")
  eq(row, 1, "toggle non-task -> cursor unchanged")
end

-- toggle: last open task -> done, cursor clamps to heading line
do
  local lines = { "# TODO", "- [ ] a", "", "## 完了" }
  local out, row = core.toggle(lines, 2)
  eq(out, { "# TODO", "", "## 完了", "- [x] a (done: 2026-11-10)" }, "toggle last open -> done")
  eq(row, 4, "toggle last open -> cursor follows")
end

-- open_area_end: row after which a new open task should be inserted
eq(core.open_area_end({ "# TODO", "- [ ] a", "", "## 完了" }), 2, "open_area_end skips trailing blank")
eq(core.open_area_end({ "# TODO", "", "## 完了" }), 1, "open_area_end with no tasks")
eq(core.open_area_end({ "# TODO", "- [ ] a" }), 2, "open_area_end without heading")

-- open_area_end stops before ## 待ち when present
eq(core.open_area_end({ "# TODO", "- [ ] a", "", "## 待ち", "- [ ] w", "", "## 完了" }), 2, "open_area_end stops before wait")

-- toggle_wait: open -> wait (appended to end of wait area)
do
  local lines = { "# TODO", "- [ ] a", "- [ ] b", "", "## 待ち", "- [ ] w", "", "## 完了" }
  local out, row = core.toggle_wait(lines, 2)
  eq(out, { "# TODO", "- [ ] b", "", "## 待ち", "- [ ] w", "- [ ] a", "", "## 完了" }, "toggle_wait open->wait lines")
  eq(row, 6, "toggle_wait open->wait cursor follows")
end

-- toggle_wait: wait -> open (appended to end of open area)
do
  local lines = { "# TODO", "- [ ] a", "", "## 待ち", "- [ ] w", "", "## 完了" }
  local out, row = core.toggle_wait(lines, 5)
  eq(out, { "# TODO", "- [ ] a", "- [ ] w", "", "## 待ち", "", "## 完了" }, "toggle_wait wait->open lines")
  eq(row, 3, "toggle_wait wait->open cursor follows")
end

-- toggle_wait: heading missing -> created before ## 完了
do
  local lines = { "# TODO", "- [ ] a", "", "## 完了", "- [x] z" }
  local out = core.toggle_wait(lines, 2)
  eq(out, { "# TODO", "", "## 待ち", "- [ ] a", "", "## 完了", "- [x] z" }, "toggle_wait creates heading before done")
end

-- toggle_wait: heading missing and no ## 完了 -> appended at end
do
  local out = core.toggle_wait({ "# TODO", "- [ ] a" }, 2)
  eq(out, { "# TODO", "", "## 待ち", "- [ ] a" }, "toggle_wait creates heading at end")
end

-- toggle_wait: done task or non-task -> unchanged
do
  local lines = { "# TODO", "- [ ] a", "", "## 待ち", "", "## 完了", "- [x] z" }
  eq(core.toggle_wait(lines, 7), lines, "toggle_wait on done -> unchanged")
  eq(core.toggle_wait(lines, 4), lines, "toggle_wait on heading -> unchanged")
end

-- toggle (<CR>) from wait area -> done
do
  local lines = { "# TODO", "- [ ] a", "", "## 待ち", "- [ ] w", "", "## 完了" }
  local out = core.toggle(lines, 5)
  eq(out, { "# TODO", "- [ ] a", "", "## 待ち", "", "## 完了", "- [x] w (done: 2026-11-10)" }, "toggle from wait -> done")
end

-- toggle (<CR>) done -> open lands in open area, not wait area
do
  local lines = { "# TODO", "- [ ] a", "", "## 待ち", "- [ ] w", "", "## 完了", "- [x] z" }
  local out, row = core.toggle(lines, 8)
  eq(out, { "# TODO", "- [ ] a", "- [ ] z", "", "## 待ち", "- [ ] w", "", "## 完了" }, "toggle done->open respects wait")
  eq(row, 3, "toggle done->open cursor")
end

-- in_confirm_area
do
  local lines = { "# TODO", "", "## 確認待ち", "1. x", "", "## やる", "- [ ] a" }
  eq(core.in_confirm_area(lines, 4), true, "in_confirm_area inside")
  eq(core.in_confirm_area(lines, 3), true, "in_confirm_area on heading")
  eq(core.in_confirm_area(lines, 7), false, "in_confirm_area in やる")
  eq(core.in_confirm_area({ "- [ ] a" }, 1), false, "in_confirm_area legacy")
end

-- skeleton
eq(core.skeleton(), { "# TODO", "", "## 確認待ち", "", "## やる", "", "## 待ち", "", "## 完了" }, "skeleton")

-- 新形式: open_area_end は ## やる の中だけを未完了エリアとする
do
  local lines = { "# TODO", "", "## 確認待ち", "1. 方針確認", "", "## やる", "- [ ] a", "", "## 待ち", "", "## 完了" }
  eq(core.open_area_end(lines), 7, "open_area_end uses やる area, ignores 確認待ち")
  eq(core.open_area_end({ "# TODO", "", "## 確認待ち", "1. x", "", "## やる", "", "## 待ち" }), 6, "open_area_end empty やる -> right after heading")
end

-- toggle: やる -> 完了 で日付が付く / 戻すと外れる
do
  local lines = { "# TODO", "", "## やる", "- [ ] a", "", "## 待ち", "", "## 完了" }
  local out = core.toggle(lines, 4)
  eq(out, { "# TODO", "", "## やる", "", "## 待ち", "", "## 完了", "- [x] a (done: 2026-11-10)" }, "toggle やる->完了 adds done date")
  local back, row = core.toggle(out, 8)
  eq(back, { "# TODO", "", "## やる", "- [ ] a", "", "## 待ち", "", "## 完了" }, "toggle 完了->やる strips done date")
  eq(row, 4, "toggle 完了->やる cursor")
end

-- toggle: リンクと next を保つ
do
  local lines = { "## やる", "- [ ] a [epc#1](https://x) — next: b", "", "## 完了" }
  local out = core.toggle(lines, 2)
  eq(out[4], "- [x] a [epc#1](https://x) — next: b (done: 2026-11-10)", "toggle keeps link and next")
  local back = core.toggle(out, 4)
  eq(back[2], "- [ ] a [epc#1](https://x) — next: b", "toggle back keeps link and next")
end

-- toggle: ## やる が無い旧形式でも行を失わない
do
  local lines = { "# TODO", "- [ ] a", "- [ ] b", "", "## 待ち", "- [ ] w", "", "## 完了" }
  local out = core.toggle(lines, 2)
  eq(out, { "# TODO", "- [ ] b", "", "## 待ち", "- [ ] w", "", "## 完了", "- [x] a (done: 2026-11-10)" }, "toggle legacy file keeps lines")
  eq(core.toggle(out, 8), { "# TODO", "- [ ] b", "- [ ] a", "", "## 待ち", "- [ ] w", "", "## 完了" }, "toggle legacy round trip")
end

-- 日付が複数回付かない
eq(core.toggle({ "## やる", "", "## 完了", "- [x] a (done: 2026-01-02)" }, 4)[2], "- [ ] a", "toggle strips existing date")

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
