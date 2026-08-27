-- 雑メモ: ~/memo/quick/YYYYMMDD-HHMMSS.md を開いたときだけ効く操作。
-- 新規メモの採番と窓の開閉は tmux 側 (C-q m) に任せる。
local M = {}

-- MEMO_DIR はテスト用の差し替え口。実ファイルをテストで壊さないために使う
M.dir = vim.env.MEMO_DIR or vim.fn.expand("~/memo/quick")

local function core()
  return require("memo.core")
end

local function is_memo_buf(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.startswith(name, M.dir .. "/") and name:sub(-3) == ".md"
end

-- 空白しか無いメモは残さない。バッファとディスクの両方を片付ける
local function discard_if_blank(buf)
  if not core().is_blank(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.uv.fs_stat(name) then
    os.remove(name)
  end
  vim.bo[buf].modified = false
  return true
end

local function quit()
  if discard_if_blank(0) then
    vim.cmd("quit")
  else
    vim.cmd("exit")
  end
end

function M.new_path()
  return M.dir .. "/" .. core().filename(os.time())
end

local function list_items()
  local files = vim.fn.glob(M.dir .. "/*.md", false, true)
  table.sort(files, function(a, b)
    return a > b
  end)
  local items = {}
  for _, path in ipairs(files) do
    local lines = vim.fn.readfile(path, "", 20)
    local title = core().title(lines)
    local stamp = core().stamp(path)
    items[#items + 1] = {
      file = path,
      text = (title or "") .. " " .. stamp,
      title = title,
      stamp = stamp,
    }
  end
  return items
end

function M.pick()
  Snacks.picker.pick({
    title = "Memo",
    items = list_items(),
    format = function(item)
      if item.title then
        return { { item.title }, { "  " .. item.stamp, "SnacksPickerComment" } }
      end
      return { { item.stamp, "SnacksPickerComment" } }
    end,
    preview = "file",
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.cmd.edit(item.file)
      end
    end,
    actions = {
      memo_new = function(picker)
        picker:close()
        vim.cmd.edit(M.new_path())
      end,
      memo_delete = function(picker, item)
        if not item then
          return
        end
        local label = core().label(item.file, vim.fn.readfile(item.file, "", 20))
        if vim.fn.confirm(("削除する? %s"):format(label), "&Yes\n&No", 2) ~= 1 then
          return
        end
        -- picker を開いたまま main ウィンドウのバッファを消すと close 時に復元されるため先に閉じる
        picker:close()
        os.remove(item.file)
        local buf = vim.fn.bufnr(item.file)
        if buf ~= -1 then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        M.pick()
      end,
    },
    win = {
      input = { keys = { ["<c-n>"] = { "memo_new", mode = { "i", "n" } }, ["<c-x>"] = { "memo_delete", mode = { "i", "n" } } } },
      list = { keys = { ["<c-n>"] = "memo_new", ["<c-x>"] = "memo_delete" } },
    },
  })
end

local function attach(buf)
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end
  map("<leader>e", M.pick, "Memo: 一覧")
  map("q", quit, "Memo: 保存して閉じる（空なら削除）")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("memo_quick", { clear = true })
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = group,
    pattern = M.dir .. "/*.md",
    callback = function(ev)
      vim.fn.mkdir(M.dir, "p")
      attach(ev.buf)
    end,
  })
  -- :q / :wq で抜けた場合の保険。vim-auto-save が空ファイルを書いていても消す
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and is_memo_buf(buf) then
          discard_if_blank(buf)
        end
      end
    end,
  })
end

return M
