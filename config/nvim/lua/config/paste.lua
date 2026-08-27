-- tmux popup 内で貼り付けると、tmux が LF を拡張キー (\e[27;5;106~ / \e[106;5u) に
-- エンコードして bracketed paste の中に混ぜてしまう (tmux popup.c は paste を1キーずつ
-- input_key に流すため。通常ペインは window_pane_paste で生バイトを書くので起きない)。
-- nvim は paste 中の内容を解釈せず挿入するので、ここで改行に戻す。
local M = {}

-- 拡張キーの改行表現。xterm 形式 (\e[27;mod;code~) と CSI u 形式 (\e[code;modu) の両方
local NEWLINE_PATTERNS = {
  "\27%[27;%d+;106~", -- Ctrl+J (LF), xterm
  "\27%[106;%d+u", -- Ctrl+J (LF), csi-u
  "\27%[27;%d+;13~", -- Enter (CR), xterm
  "\27%[13;%d+u", -- Enter (CR), csi-u
}

---@param text string
---@return string
function M.decode(text)
  -- CR+LF が両方エンコードされていた場合に改行が二重にならないよう、先に対で潰す
  text = text:gsub("\27%[27;%d+;13~\27%[27;%d+;106~", "\n"):gsub("\27%[13;%d+u\27%[106;%d+u", "\n")
  for _, pat in ipairs(NEWLINE_PATTERNS) do
    text = text:gsub(pat, "\n")
  end
  return text
end

---@param lines string[]
---@return string[]
function M.decode_lines(lines)
  local joined = table.concat(lines, "\n")
  if not joined:find("\27%[") then
    return lines
  end
  return vim.split(M.decode(joined), "\n", { plain = true })
end

function M.setup()
  local orig = vim.paste
  vim.paste = function(lines, phase)
    return orig(M.decode_lines(lines), phase)
  end
end

return M
