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

-- 終了時はコミットが済むまでロックを残す
do
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.env.TODO_MD_PATH = dir .. "/todo.md"
  package.loaded["todo"] = nil
  local todo = require("todo")
  vim.fn.writefile(core.skeleton(), todo.path)
  vim.cmd.edit(todo.path)
  todo.lock()
  local lock_at_commit
  local lock_at_answers
  todo.commit = function()
    lock_at_commit = vim.fn.filereadable(dir .. "/.todo.lock")
  end
  todo.reflect_answers = function()
    lock_at_answers = vim.fn.filereadable(dir .. "/.todo.lock")
  end
  todo.leave()
  eq(lock_at_commit, 1, "leave commits while lock is held")
  eq(vim.fn.filereadable(dir .. "/.todo.lock"), 0, "leave unlocks after commit")
  eq(lock_at_answers, 0, "leave reflects answers after unlock")
  vim.cmd("bwipeout!")
  lock_at_answers = nil
  todo.leave()
  eq(lock_at_answers, nil, "leave from another file does not reflect answers")
  vim.fn.delete(dir, "rf")
end

-- 回答の反映は answers.py を TODO_MD_PATH 付きで裏で起動する
do
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.env.TODO_MD_PATH = dir .. "/todo.md"
  package.loaded["todo"] = nil
  local todo = require("todo")
  eq(todo.answers_script:sub(-#"/scripts/todo-ai/answers.py"), "/scripts/todo-ai/answers.py", "answers script path")
  eq(vim.fn.filereadable(todo.answers_script), 1, "answers script exists next to the nvim config")
  local marker = dir .. "/marker"
  todo.answers_script = dir .. "/stub.py"
  vim.fn.writefile({
    "import os",
    "open(" .. vim.inspect(marker) .. ", 'w').write(os.environ.get('TODO_MD_PATH', ''))",
  }, todo.answers_script)
  vim.env.TODO_MD_PATH = nil
  todo.reflect_answers()
  vim.wait(5000, function()
    return vim.fn.filereadable(marker) == 1 and vim.fn.readfile(marker)[1] ~= nil
  end)
  eq(vim.fn.readfile(marker), { todo.path }, "answers.py gets TODO_MD_PATH")
  todo.answers_script = dir .. "/missing.py"
  eq(pcall(todo.reflect_answers), true, "missing answers script does not fail")
  vim.fn.delete(dir, "rf")
end

-- 表示の conceal: 範囲を当てた後に見える文字列で確かめる
local function shown(line)
  local out, pos = {}, 1
  for _, r in ipairs(core.conceal_ranges(line)) do
    table.insert(out, line:sub(pos, r[1]))
    table.insert(out, r[3] or "")
    pos = r[2] + 1
  end
  table.insert(out, line:sub(pos))
  return table.concat(out)
end

eq(shown("- [ ] 再レビュー [epc#1210](https://github.com/x/pull/1210) — next: 修正を確認"),
  "- [ ] 再レビュー epc#1210 → 修正を確認", "conceal link and next on a task line")
eq(shown("- [ ] [officeのteams資料修正](https://somu.example/Disp.do?volumeName=00467&itemID=t1)"),
  "- [ ] officeのteams資料修正", "conceal human link")
eq(shown("- [x] 済 [gb:ebase-web#96](http://192.168.0.1:8080/gitbucket/x/pull/96) (done: 2026-11-11)"),
  "- [x] 済 gb:ebase-web#96 (done: 2026-11-11)", "conceal link on a done line")
eq(shown("1. 「パイロット」に足す？（3件） [is_task title:パイロット(P.1、2)]"),
  "1. 「パイロット」に足す？（3件）", "conceal confirm tag")
eq(shown("12. q [still_needed rc:abc#2]"), "12. q", "conceal confirm tag with 2-digit number")
eq(shown("1. q [is_task title:[資料](https://x/y)]"), "1. q", "conceal tag that contains a link")
eq(shown("1. 『X [a] の件』を足す？ [is_task title:X [a] の件]"), "1. 『X [a] の件』を足す？", "conceal tag after brackets in question")
eq(shown("1. q [foo epc#1]"), "1. q [foo epc#1]", "unknown kind is not a tag")
eq(shown("1. q [policy epc#1] あと"), "1. q [policy epc#1] あと", "tag must end the line")
eq(shown("- [ ] q [policy epc#1]"), "- [ ] q [policy epc#1]", "tag only on numbered lines")
eq(shown("1. a — next: b"), "1. a — next: b", "next arrow only on task lines")
eq(shown("- [ ] a — next: b — next: c"), "- [ ] a — next: b → c", "next arrow on the last separator")
eq(shown("- [ ] [x](has space)"), "- [ ] [x](has space)", "link url with space is not concealed")
eq(shown("   A 足す★ / B 足さない"), "   A 足す★ / B 足さない", "options line untouched")
eq(core.conceal_ranges("- [ ] plain"), {}, "plain task has no ranges")

-- 表示の conceal はファイルを変えず、カーソル行は生の文字を見せる
do
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.env.TODO_MD_PATH = dir .. "/todo.md"
  package.loaded["todo"] = nil
  local todo = require("todo")
  local content = {
    "# TODO", "", "## 確認待ち", "1. 足す？（3件） [is_task title:x]", "   A 足す★ / B 足さない", "   回答:", "",
    "## やる", "- [ ] a [epc#1](https://g/1) — next: b", "", "## 待ち", "", "## 完了",
  }
  vim.fn.writefile(content, todo.path)
  todo.setup()
  vim.cmd.edit(todo.path)
  local buf = vim.api.nvim_get_current_buf()
  eq(vim.wo.conceallevel, 2, "todo window conceallevel")
  eq(vim.wo.concealcursor, "", "todo window concealcursor")
  local function marked_rows()
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, todo.ns, 0, -1, {})) do
      rows[m[2] + 1] = true
    end
    return rows
  end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  eq({ marked_rows()[4], marked_rows()[9] }, { true, true }, "conceal marks on tag and task rows")
  vim.api.nvim_win_set_cursor(0, { 9, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  eq({ marked_rows()[4], marked_rows()[9] }, { true, nil }, "cursor row shows raw text")
  local function arrows()
    local n = 0
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, todo.ns, 0, -1, { details = true })) do
      if m[4].virt_text then
        n = n + 1
      end
    end
    return n
  end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  eq(arrows(), 1, "arrow shown while conceallevel > 0")
  vim.wo.conceallevel = 0
  eq(arrows(), 0, "no arrow when conceallevel is 0 (render-markdown in insert mode)")
  vim.wo.conceallevel = 3
  eq(arrows(), 1, "arrow back when conceallevel returns")
  vim.cmd("silent write")
  eq(vim.fn.readfile(todo.path), content, "conceal does not change file contents")
  vim.cmd("bwipeout!")
  vim.fn.delete(dir, "rf")
end

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
