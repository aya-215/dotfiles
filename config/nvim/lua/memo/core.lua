-- 雑メモ (memo/quick) の純関数。ファイルにもバッファにも触らない。
local M = {}

function M.is_blank(lines)
  for _, l in ipairs(lines) do
    if not l:match("^%s*$") then
      return false
    end
  end
  return true
end

-- 先頭の非空行をタイトルとする。見出し記号 ("# ") は剥がす
---@return string|nil
function M.title(lines)
  for _, l in ipairs(lines) do
    if not l:match("^%s*$") then
      return (l:gsub("^%s*#+%s+", ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end
  end
  return nil
end

---@param t integer os.time()
function M.filename(t)
  return os.date("%Y%m%d-%H%M%S", t) .. ".md"
end

-- ファイル名 YYYYMMDD-HHMMSS.md を "YYYY-MM-DD HH:MM" に。形式外なら拡張子なしの basename
function M.stamp(path)
  local base = vim.fn.fnamemodify(path, ":t:r")
  local y, mo, d, h, mi = base:match("^(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)%d%d$")
  if not y then
    return base
  end
  return ("%s-%s-%s %s:%s"):format(y, mo, d, h, mi)
end

function M.label(path, lines)
  return M.title(lines) or M.stamp(path)
end

return M
