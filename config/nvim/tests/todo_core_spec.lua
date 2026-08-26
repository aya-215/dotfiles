-- 実行: nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local core = require("todo.core")
local failures = 0

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
  eq(out, { "# TODO", "- [ ] b", "", "## 完了", "- [x] a", "- [x] old" }, "toggle open->done lines")
  eq(row, 2, "toggle open->done cursor stays on next open task")
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
  eq(out, { "# TODO", "", "## 完了", "- [x] a" }, "toggle creates heading when missing")
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
  eq(out, { "# TODO", "", "## 完了", "- [x] a" }, "toggle last open -> done")
  eq(row, 2, "toggle last open -> cursor clamps to next line")
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
  eq(row, 2, "toggle_wait open->wait cursor stays")
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
  eq(out, { "# TODO", "- [ ] a", "", "## 待ち", "", "## 完了", "- [x] w" }, "toggle from wait -> done")
end

-- toggle (<CR>) done -> open lands in open area, not wait area
do
  local lines = { "# TODO", "- [ ] a", "", "## 待ち", "- [ ] w", "", "## 完了", "- [x] z" }
  local out, row = core.toggle(lines, 8)
  eq(out, { "# TODO", "- [ ] a", "- [ ] z", "", "## 待ち", "- [ ] w", "", "## 完了" }, "toggle done->open respects wait")
  eq(row, 3, "toggle done->open cursor")
end

-- skeleton
eq(core.skeleton(), { "# TODO", "", "## 待ち", "", "## 完了" }, "skeleton")

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
