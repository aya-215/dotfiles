-- 実行: nvim --headless -u NONE -l config/nvim/tests/paste_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
local P = require("config.paste")
local failures = 0
local function eq(actual, expected, name)
  if vim.deep_equal(actual, expected) then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name)
    print("  expected: " .. vim.inspect(expected))
    print("  actual:   " .. vim.inspect(actual))
  end
end
local ESC = "\27"
eq(P.decode("A" .. ESC .. "[27;5;106~B"), "A\nB", "xterm LF")
eq(P.decode("A" .. ESC .. "[106;5u" .. "B"), "A\nB", "csi-u LF")
eq(P.decode("A" .. ESC .. "[13;1u" .. "B"), "A\nB", "csi-u CR (claude-code #43169 の形)")
eq(P.decode("A" .. ESC .. "[27;5;13~" .. ESC .. "[27;5;106~B"), "A\nB", "xterm CR+LF -> single newline")
eq(P.decode("A" .. ESC .. "[13;1u" .. ESC .. "[106;5u" .. "B"), "A\nB", "csi-u CR+LF -> single newline")
eq(P.decode("plain text"), "plain text", "no-op on plain text")
eq(P.decode(ESC .. "[31mred"), ESC .. "[31mred", "leaves unrelated escapes alone")
eq(P.decode_lines({ "本番環境に SSH 接続したいのですが、" .. ESC .. "[27;5;106~お手すきの際に" }), { "本番環境に SSH 接続したいのですが、", "お手すきの際に" }, "decode_lines splits into lines")
eq(P.decode_lines({ "a", "b" }), { "a", "b" }, "decode_lines passthrough")
if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
