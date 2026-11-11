-- todo.md の行操作（純関数）。バッファには一切触らない。
-- セクション順は ## 確認待ち → ## やる → ## 待ち → ## 完了 を前提とする（旧形式は 未完了(先頭) → 待ち → 完了）。
local M = {}

M.CONFIRM_HEADING = "## 確認待ち"
M.TODO_HEADING = "## やる"
M.WAIT_HEADING = "## 待ち"
M.DONE_HEADING = "## 完了"
M.HEADING = M.DONE_HEADING

-- テストで日付を固定するための差し替え口
function M.today()
  return os.date("%Y-%m-%d")
end

local DONE_SUFFIX = "%s%(done: %d+%-%d+%-%d+%)$"

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

function M.find_todo_heading(lines)
  return find_heading(lines, "やる")
end

function M.find_confirm_heading(lines)
  return find_heading(lines, "確認待ち")
end

-- row が ## 確認待ち 見出しから次の見出しまでの間にあるか
function M.in_confirm_area(lines, row)
  local start = M.find_confirm_heading(lines)
  if not start or row < start then
    return false
  end
  for i = start + 1, row do
    if lines[i] and lines[i]:match("^##%s") then
      return false
    end
  end
  return true
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
-- ## やる があればその次の行から数える（## 確認待ち の番号付き行を巻き込まない）。
---@return integer row (0 = 先頭に挿入)
function M.open_area_end(lines)
  local stop = M.find_wait_heading(lines) or M.find_done_heading(lines) or #lines + 1
  local todo = M.find_todo_heading(lines)
  return trimmed_end(lines, todo and todo + 1 or 1, stop)
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

M.CONFIRM_KINDS = { "policy", "before_share", "manual", "conflict", "is_task", "still_needed" }
M.NEXT_SEP = " — next: "
M.NEXT_ARROW = "→"
local KIND_SET = {}
for _, k in ipairs(M.CONFIRM_KINDS) do
  KIND_SET[k] = true
end

-- 確認待ちの問いの末尾タグ ` [<kind> <ref>]` の開始位置（1-based、先頭の空白）。apply.py の _TAG と同じく最初の候補を取る
local function tag_start(line)
  if not line:match("^%d+%. ") or line:sub(-1) ~= "]" then
    return nil
  end
  local init = 1
  while true do
    local s = line:find(" [", init, true)
    if not s then
      return nil
    end
    local kind = line:match("^ %[([%l_]+) .", s)
    if kind and KIND_SET[kind] then
      return s
    end
    init = s + 1
  end
end

-- 表示で隠す範囲。{ 開始, 終了 } は 0-based の半開区間（byte）、3番目があればその文字を代わりに見せる。
-- ファイルの中身は変えず、nvim の conceal に渡すためだけに使う。
---@param line string
---@return { [1]: integer, [2]: integer, [3]: string|nil }[]
function M.conceal_ranges(line)
  local out = {}
  local tag = tag_start(line)
  local init = 1
  while true do
    local s, e, paren = line:find("%[[^%[%]]*%]()%([^%s()]+%)", init)
    if not s or (tag and s >= tag) then
      break
    end
    table.insert(out, { s - 1, s })
    table.insert(out, { paren - 2, e })
    init = e + 1
  end
  if tag then
    table.insert(out, { tag - 1, #line })
  end
  if M.parse(line) then
    local last
    local i = line:find(M.NEXT_SEP, 1, true)
    while i do
      last = i
      i = line:find(M.NEXT_SEP, i + 1, true)
    end
    if last then
      table.insert(out, { last, last + #M.NEXT_SEP - 2, M.NEXT_ARROW })
    end
  end
  table.sort(out, function(a, b)
    return a[1] < b[1]
  end)
  return out
end

function M.skeleton()
  return { "# TODO", "", M.CONFIRM_HEADING, "", M.TODO_HEADING, "", M.WAIT_HEADING, "", M.DONE_HEADING }
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
    table.insert(out, at, "- [ ] " .. task.text:gsub(DONE_SUFFIX, ""))
    return out, at
  end

  local heading = M.find_done_heading(out)
  if not heading then
    table.insert(out, M.DONE_HEADING)
    heading = ensure_blank_before(out, #out)
  end
  table.insert(out, heading + 1, "- [x] " .. task.text:gsub(DONE_SUFFIX, "") .. " (done: " .. M.today() .. ")")
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
