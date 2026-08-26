-- todo.md の行操作（純関数）。バッファには一切触らない。
-- セクション順は 未完了(先頭) → ## 待ち → ## 完了 を前提とする。
local M = {}

M.WAIT_HEADING = "## 待ち"
M.DONE_HEADING = "## 完了"
M.HEADING = M.DONE_HEADING

---@param line string
---@return { done: boolean, text: string }|nil
function M.parse(line)
  local mark, text = line:match("^%s*%- %[([ xX])%]%s?(.*)$")
  if not mark then
    return nil
  end
  return { done = mark ~= " ", text = text }
end

---@return integer|nil row (1-based)
local function find_heading(lines, title)
  local pat = "^##%s+" .. title .. "%s*$"
  for i, line in ipairs(lines) do
    if line:match(pat) then
      return i
    end
  end
  return nil
end

function M.find_wait_heading(lines)
  return find_heading(lines, "待ち")
end

function M.find_done_heading(lines)
  return find_heading(lines, "完了")
end

-- [from, to) の範囲で末尾の空行を除いた最終行。範囲が空なら from - 1。
local function trimmed_end(lines, from, to)
  local last = to - 1
  while last >= from and lines[last]:match("^%s*$") do
    last = last - 1
  end
  return math.max(last, from - 1)
end

-- 未完了エリアの最終行（末尾の空行は含まない）。新規タスクはこの直後に挿入する。
---@return integer row (0 = 先頭に挿入)
function M.open_area_end(lines)
  local stop = M.find_wait_heading(lines) or M.find_done_heading(lines) or #lines + 1
  return trimmed_end(lines, 1, stop)
end

-- 待ちエリアの最終行。見出しが無ければ nil。
function M.wait_area_end(lines)
  local wait = M.find_wait_heading(lines)
  if not wait then
    return nil
  end
  local stop = M.find_done_heading(lines) or #lines + 1
  return trimmed_end(lines, wait + 1, stop)
end

function M.skeleton()
  return { "# TODO", "", M.WAIT_HEADING, "", M.DONE_HEADING }
end

-- 見出し行の直前に空行が無ければ足す
local function ensure_blank_before(out, at)
  if at > 1 and not out[at - 1]:match("^%s*$") then
    table.insert(out, at, "")
    return at + 1
  end
  return at
end

-- 移動系は常に移動先の行番号を返す（カーソルを項目に追従させる）
---@param lines string[]
---@param row integer 1-based
---@return string[] new_lines, integer new_row
function M.toggle(lines, row)
  local out = vim.deepcopy(lines)
  local task = M.parse(out[row])
  if not task then
    return out, row
  end
  table.remove(out, row)

  if task.done then
    local at = M.open_area_end(out) + 1
    table.insert(out, at, "- [ ] " .. task.text)
    return out, at
  end

  local heading = M.find_done_heading(out)
  if not heading then
    table.insert(out, M.DONE_HEADING)
    heading = ensure_blank_before(out, #out)
  end
  table.insert(out, heading + 1, "- [x] " .. task.text)
  return out, heading + 1
end

-- 未完了 ⇄ 待ち を移動する。完了済み・タスク以外の行は何もしない。
---@return string[] new_lines, integer new_row
function M.toggle_wait(lines, row)
  local out = vim.deepcopy(lines)
  local task = M.parse(out[row])
  if not task or task.done then
    return out, row
  end
  local wait = M.find_wait_heading(out)
  local in_wait = wait ~= nil and row > wait
  table.remove(out, row)

  if in_wait then
    local at = M.open_area_end(out) + 1
    table.insert(out, at, "- [ ] " .. task.text)
    return out, at
  end

  if not wait then
    local done = M.find_done_heading(out)
    if done then
      table.insert(out, done, M.WAIT_HEADING)
      wait = ensure_blank_before(out, done)
      table.insert(out, wait + 1, "")
    else
      table.insert(out, M.WAIT_HEADING)
      wait = ensure_blank_before(out, #out)
    end
  end
  local at = M.wait_area_end(out) + 1
  table.insert(out, at, "- [ ] " .. task.text)
  return out, at
end

return M
