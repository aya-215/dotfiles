-- ~/.nb/notes/todo.md を開いたときだけ効くチェックボックス操作。
-- 窓の開閉は tmux 側（C-q t / C-q T）に任せ、nvim からは開く導線を持たない。
local M = {}

M.path = vim.fn.expand("~/.nb/notes/todo.md")

local function toggle()
  local core = require("todo.core")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local new_lines, new_row = core.toggle(lines, row)
  if vim.deep_equal(new_lines, lines) then
    return
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
  vim.api.nvim_win_set_cursor(0, { new_row, 0 })
  vim.cmd.write()
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
  map("<CR>", toggle, "TODO: 完了/未完了を切り替え")
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
