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

-- scripts/todo-ai/todo_md.py の KEY_RE と同じ種類。行末のリンクのうち中身が key のものだけを key とみなす
local KEY_PATTERNS = {
  "^epc#%d+$", "^emm#%d+$", "^eae#%d+$", "^eas#%d+$",
  "^gb:[^%s%[%]()#]+#%d+$",
  "^rc:[%w_%-]+$", "^rc:[%w_%-]+#%d+$",
  "^mail:[^%s%[%]()]+$", "^wt:[^%s%[%]()]+$",
  "^ebpm:No%d+$",
}

local function is_key(s)
  for _, p in ipairs(KEY_PATTERNS) do
    if s:match(p) then
      return true
    end
  end
  return false
end

-- タスク行の key のリンクと next をまとめて隠す範囲と、代わりにカーソル行の下へ出す文字列。
-- { 開始, 終了 } は 0-based の半開区間（byte）。末尾の (done: 日付) は範囲に含めない。
---@param line string
---@return { [1]: integer, [2]: integer, [3]: string }|nil
function M.detail(line)
  if not M.parse(line) then
    return nil
  end
  local body_start = #line:match("^%s*%- %[[ xX]%]%s?") + 1
  local stop = #line
  local d = line:find(" %(done: %d%d%d%d%-%d%d%-%d%d%)$")
  if d then
    stop = d - 1
  end
  local head = line:sub(1, stop)
  local cut, nxt
  local i = head:find(M.NEXT_SEP, body_start, true)
  while i do
    cut = i - 1
    i = head:find(M.NEXT_SEP, i + 1, true)
  end
  if cut then
    nxt = head:sub(cut + #M.NEXT_SEP + 1)
    head = head:sub(1, cut)
  end
  local key
  local s, k = head:match("()%[([^%[%]]*)%]%([^%s()]+%)$")
  if s and is_key(k) and (s == body_start or head:sub(s - 1, s - 1) == " ") then
    key = k
    cut = s == body_start and s - 1 or s - 2
  end
  if not cut then
    return nil
  end
  local text = key or ""
  if nxt then
    text = (key and key .. " " or "") .. M.NEXT_ARROW .. " " .. nxt
  end
  return { cut, stop, text }
end

-- 表示で隠す範囲。{ 開始, 終了 } は 0-based の半開区間（byte）。
-- ファイルの中身は変えず、nvim の conceal に渡すためだけに使う。
---@param line string
---@return { [1]: integer, [2]: integer }[]
function M.conceal_ranges(line)
  local out = {}
  local tag = tag_start(line)
  local detail = M.detail(line)
  local limit = (tag and tag - 1) or (detail and detail[1]) or #line
  local init = 1
  while true do
    local s, e, paren = line:find("%[[^%[%]]*%]()%([^%s()]+%)", init)
    if not s or s > limit then
      break
    end
    table.insert(out, { s - 1, s })
    table.insert(out, { paren - 2, e })
    init = e + 1
  end
  if tag then
    table.insert(out, { tag - 1, #line })
  end
  if detail then
    table.insert(out, { detail[1], detail[2] })
  end
  return out
end

-- 行末まで続く隠し範囲の開始（0-based byte）。無ければ nil
---@param line string
---@return integer|nil
function M.visible_end(line)
  for _, r in ipairs(M.conceal_ranges(line)) do
    if r[2] == #line then
      return r[1]
    end
  end
  return nil
end

-- 確認待ちの問いごとの行番号（1-based）。opt は選択肢の行、ans は回答の行、options は選択肢の文（前後の空白を除く）
---@param lines string[]
---@return { q: integer, opt: integer|nil, ans: integer|nil, options: string|nil }[]
function M.confirm_blocks(lines)
  local out = {}
  local start = M.find_confirm_heading(lines)
  if not start then
    return out
  end
  local cur
  for i = start + 1, #lines do
    local line = lines[i]
    if line:match("^##%s") then
      break
    end
    if line:match("^%d+%. ") then
      cur = { q = i }
      table.insert(out, cur)
    elseif cur and not cur.opt and line:match("^%s+A%s") then
      cur.opt = i
      cur.options = vim.trim(line)
    elseif cur and not cur.ans and line:match("^%s+回答:") then
      cur.ans = i
    end
  end
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
