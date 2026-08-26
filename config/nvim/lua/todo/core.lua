-- todo.md の行操作（純関数）。バッファには一切触らない。
local M = {}

M.HEADING = "## 完了"

---@param line string
---@return { done: boolean, text: string }|nil
function M.parse(line)
  local mark, text = line:match("^%s*%- %[([ xX])%]%s?(.*)$")
  if not mark then
    return nil
  end
  return { done = mark ~= " ", text = text }
end

---@param lines string[]
---@return integer|nil row (1-based)
function M.find_done_heading(lines)
  for i, line in ipairs(lines) do
    if line:match("^##%s+完了%s*$") then
      return i
    end
  end
  return nil
end

-- 未完了エリアの最終行（末尾の空行は含まない）。新規タスクはこの直後に挿入する。
---@param lines string[]
---@return integer row (0 = 先頭に挿入)
function M.open_area_end(lines)
  local last = (M.find_done_heading(lines) or #lines + 1) - 1
  while last > 0 and lines[last]:match("^%s*$") do
    last = last - 1
  end
  return last
end

function M.skeleton()
  return { "# TODO", "", M.HEADING }
end

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
    if #out > 0 and not out[#out]:match("^%s*$") then
      table.insert(out, "")
    end
    table.insert(out, M.HEADING)
    heading = #out
  end
  table.insert(out, heading + 1, "- [x] " .. task.text)
  return out, math.min(row, #out)
end

return M
