-- ~/.nb/notes/todo.md を開いたときだけ効くチェックボックス操作。
-- 窓の開閉は tmux 側（C-q t のポップアップ）に任せ、nvim からは開く導線を持たない。
local M = {}

-- TODO_MD_PATH はテスト用の差し替え口。実ファイルをテストで壊さないために使う
M.path = vim.env.TODO_MD_PATH or vim.fn.expand("~/.nb/notes/todo.md")

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

function M._insert_task(above)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local at = above and row - 1 or row
  vim.api.nvim_buf_set_lines(0, at, at, false, { "- [ ] " })
  vim.api.nvim_win_set_cursor(0, { at + 1, 0 })
  vim.cmd.startinsert({ bang = true })
end

-- expr マップ用: 完了エリアでは素の o/O、未完了エリアでは "- [ ] " 付きの新規行
-- (expr 内ではバッファを変更できないため挿入は <Cmd> 経由で行う)
local function new_task(above)
  local core = require("todo.core")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local heading = core.find_done_heading(lines)
  if heading and row >= heading then
    return above and "O" or "o"
  end
  return ("<Cmd>lua require('todo')._insert_task(%s)<CR>"):format(tostring(above))
end

local function attach(buf)
  local function map(lhs, rhs, desc, expr)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc, expr = expr })
  end
  local core = require("todo.core")
  map("<CR>", apply(core.toggle), "TODO: 完了/未完了を切り替え")
  map("<Tab>", apply(core.toggle_wait), "TODO: 未完了/待ちを移動")
  map("o", function() return new_task(false) end, "TODO: 下に新規タスク", true)
  map("O", function() return new_task(true) end, "TODO: 上に新規タスク", true)
  map("q", "<cmd>x<cr>", "TODO: 保存して閉じる")
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
    end,
  })
end

return M
