-- ~/memo/todo.md を開いたときだけ効くチェックボックス操作。
-- 窓の開閉は tmux 側（C-q t のポップアップ）に任せ、nvim からは開く導線を持たない。
local M = {}

-- TODO_MD_PATH はテスト用の差し替え口。実ファイルをテストで壊さないために使う
-- Windows の `\` は autocmd の pattern で `\3` 等が後方参照扱いになる(E65)ので `/` に揃える
M.path = (vim.env.TODO_MD_PATH or vim.fn.expand("~/memo/todo.md")):gsub("\\", "/")

local function count_nonblank(lines)
  local n = 0
  for _, l in ipairs(lines) do
    if not l:match("^%s*$") then
      n = n + 1
    end
  end
  return n
end

-- core の (lines, row) -> (lines, row) 関数をカーソル行に適用して保存する
local function apply(fn)
  return function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local new_lines, new_row = fn(lines, row)
    if vim.deep_equal(new_lines, lines) then
      return
    end
    -- 移動系の操作で非空行が減ることは無い。減るなら内容を失うバグなので反映しない
    if count_nonblank(new_lines) < count_nonblank(lines) then
      vim.notify("todo: 行が失われる変更を検出したため中止しました", vim.log.levels.ERROR)
      return
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
    vim.api.nvim_win_set_cursor(0, { new_row, 0 })
    vim.cmd.write()
  end
end

-- 案件の表は todo.md の隣に置く（顧客名を dotfiles に入れないため）。無い・読めないときは {} でまとめない
function M.groups_path()
  return vim.fn.fnamemodify(M.path, ":h") .. "/todo-groups.json"
end

function M.load_groups()
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(M.groups_path()), "\n"))
  end)
  if not ok or type(data) ~= "table" or type(data.groups) ~= "table" then
    return {}
  end
  for _, g in ipairs(data.groups) do
    if type(g) ~= "table" or type(g.name) ~= "string" or type(g.keys) ~= "table" or type(g.words) ~= "table" then
      return {}
    end
    for _, v in ipairs(vim.list_extend(vim.list_slice(g.keys), g.words)) do
      if type(v) ~= "string" then
        return {}
      end
    end
  end
  return data.groups
end

-- 開いている間は行を動かさず、閉じてコミットする直前に案件ごとにまとめる
local function regroup_file()
  if vim.fn.filereadable(M.path) == 0 then
    return
  end
  local lines = vim.fn.readfile(M.path)
  local new_lines = require("todo.core").regroup(lines, M.load_groups())
  if vim.deep_equal(new_lines, lines) then
    return
  end
  if count_nonblank(new_lines) < count_nonblank(lines) then
    vim.notify("todo: 案件の並べ替えで行が失われるため中止しました", vim.log.levels.ERROR)
    return
  end
  vim.fn.writefile(new_lines, M.path)
end

-- 閉じるときだけ git にコミットする（<CR> ごとに保存はするがコミットは荒らさない）
-- 対象ファイルだけ add するので、同じディレクトリの他ファイルは巻き込まない
function M.commit()
  regroup_file()
  local dir = vim.fn.fnamemodify(M.path, ":h")
  if vim.fn.isdirectory(dir .. "/.git") == 0 then
    return
  end
  local name = vim.fn.fnamemodify(M.path, ":t")
  vim.system({ "git", "-C", dir, "add", "--", name }):wait()
  local diff = vim.system({ "git", "-C", dir, "diff", "--cached", "--quiet", "--", name }):wait()
  if diff.code == 0 then
    return
  end
  vim.system({ "git", "-C", dir, "commit", "-q", "-m", "todo: " .. os.date("%Y-%m-%d %H:%M"), "--", name }):wait()
end

-- 編集中は apply.py が書き込みをスキップするためのロック。中身は PID で、落ちて残っても生死判定で無視される
local function lock_path()
  return vim.fn.fnamemodify(M.path, ":h") .. "/.todo.lock"
end

function M.lock()
  vim.fn.writefile({ tostring(vim.fn.getpid()) }, lock_path())
end

-- 他の nvim が置いたロックは消さない
function M.unlock()
  local f = lock_path()
  local ok, content = pcall(vim.fn.readfile, f)
  if ok and content[1] == tostring(vim.fn.getpid()) then
    vim.fn.delete(f)
  end
end

-- ~/.config/nvim は dotfiles へのシンボリックリンクなので、実体のパスから scripts/ を辿る
M.answers_script = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":p:h:h:h:h:h")
  .. "/scripts/todo-ai/answers.py"

-- 選択肢の文字1つの回答を AI なしで反映する。ポップアップは閉じるので待たず、結果は answers.py のログに残る
function M.reflect_answers()
  pcall(function()
    if vim.fn.has("unix") == 0 or vim.fn.executable("python3") == 0 or vim.fn.filereadable(M.answers_script) == 0 then
      return
    end
    -- nvim が先に終わるので、子の出力を nvim のパイプに残さない
    vim.fn.jobstart({ "sh", "-c", 'exec python3 -I "$0" >/dev/null 2>&1 </dev/null', M.answers_script },
      { detach = true, env = { TODO_MD_PATH = M.path } })
  end)
end

-- 書き込み → commit → unlock → 回答の反映の順。先に外すと apply.py が未コミットの人の編集に AI の変更を重ねる
function M.leave()
  local mine = vim.fn.bufnr(M.path) ~= -1 and vim.fn.filereadable(M.path) == 1
  if mine then
    M.commit()
  end
  M.unlock()
  if mine then
    M.reflect_answers()
  end
end

-- exit の後は処理が走らないので、unlock は VimLeavePre の M.leave に任せる
local function quit()
  vim.cmd("update")
  M.commit()
  vim.cmd("exit")
end

function M._insert_task(above)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local at = above and row - 1 or row
  vim.api.nvim_buf_set_lines(0, at, at, false, { "- [ ] " })
  vim.api.nvim_win_set_cursor(0, { at + 1, 0 })
  vim.cmd.startinsert({ bang = true })
end

-- expr マップ用: 完了・確認待ちエリアでは素の o/O、未完了エリアでは "- [ ] " 付きの新規行
-- (expr 内ではバッファを変更できないため挿入は <Cmd> 経由で行う)
local function new_task(above)
  local core = require("todo.core")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local heading = core.find_done_heading(lines)
  if (heading and row >= heading) or core.in_confirm_area(lines, row) then
    return above and "O" or "o"
  end
  return ("<Cmd>lua require('todo')._insert_task(%s)<CR>"):format(tostring(above))
end

M.ns = vim.api.nvim_create_namespace("todo_conceal")

-- 確認待ちの選択肢の行は隠し、カーソルのある問いだけ 回答: の右に出す
local function decorate_confirm(buf, lines, cursor)
  for _, b in ipairs(require("todo.core").confirm_blocks(lines)) do
    if b.opt then
      vim.api.nvim_buf_set_extmark(buf, M.ns, b.opt - 1, 0, { conceal_lines = "" })
      local last = math.max(b.q, b.opt, b.ans or 0)
      if b.ans and cursor >= b.q and cursor <= last then
        vim.api.nvim_buf_set_extmark(buf, M.ns, b.ans - 1, 0, {
          virt_text = { { "  " .. b.options, "Comment" } },
          virt_text_pos = "eol",
        })
      end
    end
  end
end

-- 表示だけを変える（ファイルの中身は変えない）。タスク行は題だけを見せ、カーソル行の下に key と next を仮想行で出す。
-- conceallevel 0（render-markdown の挿入モード）では生の行が見えるので仮想行は付けない
function M.decorate(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    win = vim.fn.win_findbuf(buf)[1]
  end
  local cursor = win and vim.api.nvim_win_get_buf(win) == buf and vim.api.nvim_win_get_cursor(win)[1] or -1
  local show_detail = win ~= nil and vim.wo[win].conceallevel > 0 and vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i"
  local core = require("todo.core")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  decorate_confirm(buf, lines, cursor)
  for _, h in ipairs(core.group_headings(lines, M.load_groups())) do
    vim.api.nvim_buf_set_extmark(buf, M.ns, h.row - 1, 0, { virt_lines = { { { h.text, "Title" } } }, virt_lines_above = true })
  end
  for lnum, line in ipairs(lines) do
    for _, r in ipairs(core.conceal_ranges(line)) do
      vim.api.nvim_buf_set_extmark(buf, M.ns, lnum - 1, r[1], { end_col = r[2], conceal = "" })
    end
    if lnum == cursor and show_detail then
      local d = core.detail(line)
      if d then
        vim.api.nvim_buf_set_extmark(buf, M.ns, lnum - 1, 0, { virt_lines = { { { d[3], "Comment" } } } })
      end
    end
  end
end

local function set_view_options(win)
  vim.api.nvim_set_option_value("conceallevel", 2, { scope = "local", win = win })
  vim.api.nvim_set_option_value("concealcursor", "n", { scope = "local", win = win })
  vim.api.nvim_set_option_value("wrap", false, { scope = "local", win = win })
end

-- render-markdown は描画のたびに concealcursor を '' に戻すので、todo.md の窓だけ戻し直す
function M.on_render(ctx)
  if not (vim.api.nvim_buf_is_valid(ctx.buf) and vim.b[ctx.buf].todo_view) then
    return
  end
  if not vim.api.nvim_win_is_valid(ctx.win) then
    return
  end
  vim.api.nvim_set_option_value("concealcursor", "n", { scope = "local", win = ctx.win })
end

-- nowrap なので、$ や A→Esc でカーソルが隠した URL の奥へ行くと横にずれて題が全部見えなくなる。題の末尾に戻す
function M.clamp_cursor(buf)
  if vim.api.nvim_get_mode().mode ~= "n" then
    return
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local last = vim.b[buf].todo_last_row or row
  vim.b[buf].todo_last_row = row
  -- 隠した選択肢の行に留まると j/k が止まったように見え、編集もその行に入るので、動いた向きの隣へ進める
  for _, b in ipairs(require("todo.core").confirm_blocks(vim.api.nvim_buf_get_lines(buf, 0, -1, false))) do
    if b.opt == row then
      row = row < last and b.q or (b.ans or b.q)
      vim.b[buf].todo_last_row = row
      vim.api.nvim_win_set_cursor(win, { row, 0 })
      return
    end
  end
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
  local stop = require("todo.core").visible_end(line)
  if not stop or stop == 0 or col < stop then
    return
  end
  vim.api.nvim_win_set_cursor(win, { row, stop - 1 + vim.str_utf_start(line, stop) })
  if vim.fn.winsaveview().leftcol > 0 then
    vim.fn.winrestview({ leftcol = 0 })
  end
end

local function attach_view(buf)
  local group = vim.api.nvim_create_augroup("todo_md_view", { clear = false })
  vim.api.nvim_clear_autocmds({ group = group, buffer = buf })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = buf,
    callback = function()
      set_view_options(vim.api.nvim_get_current_win())
      M.decorate(buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = group,
    buffer = buf,
    callback = function(ev)
      if ev.event == "CursorMoved" or ev.event == "ModeChanged" then
        M.clamp_cursor(buf)
      end
      M.decorate(buf)
    end,
  })
  vim.b[buf].todo_view = true
  -- OptionSet はバッファに限定できないので1つだけ作り、表示を付けたバッファのときだけ付け直す
  vim.api.nvim_create_autocmd("OptionSet", {
    group = vim.api.nvim_create_augroup("todo_md_view_option", { clear = true }),
    pattern = "conceallevel",
    callback = function()
      if vim.b.todo_view then
        M.decorate(vim.api.nvim_get_current_buf())
      end
    end,
  })
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    set_view_options(win)
  end
  M.decorate(buf)
end

local function attach(buf)
  attach_view(buf)
  local function map(lhs, rhs, desc, expr)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc, expr = expr })
  end
  local core = require("todo.core")
  map("<CR>", apply(core.toggle), "TODO: 完了/未完了を切り替え")
  map("<Tab>", apply(core.toggle_wait), "TODO: 未完了/待ちを移動")
  map("o", function() return new_task(false) end, "TODO: 下に新規タスク", true)
  map("O", function() return new_task(true) end, "TODO: 上に新規タスク", true)
  map("q", quit, "TODO: 保存して閉じる（git commit）")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("todo_md", { clear = true })
  vim.api.nvim_create_autocmd("BufNewFile", {
    group = group,
    pattern = M.path,
    callback = function(ev)
      vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, require("todo.core").skeleton())
    end,
  })
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = group,
    pattern = M.path,
    callback = function(ev)
      attach(ev.buf)
      M.lock()
    end,
  })
  -- :q / :wq で抜けた場合の保険
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.leave()
    end,
  })
end

return M
