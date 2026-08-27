-- 実行: nvim --headless -u NONE -l config/nvim/tests/memo_core_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local core = require("memo.core")
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

-- title: 先頭の非空行、# は剥がす
eq(core.title({ "# 見出し", "本文" }), "見出し", "title strips heading marker")
eq(core.title({ "", "  ", "ただの一行 ", "x" }), "ただの一行", "title skips blank lines and trims")
eq(core.title({ "### deep" }), "deep", "title strips multiple #")
eq(core.title({ "#hashtag" }), "#hashtag", "title keeps #tag without space")
eq(core.title({ "", "   " }), nil, "title of blank -> nil")
eq(core.title({}), nil, "title of empty -> nil")

-- is_blank
eq(core.is_blank({ "", "  ", "\t" }), true, "is_blank whitespace only")
eq(core.is_blank({ "", "a" }), false, "is_blank with content")
eq(core.is_blank({}), true, "is_blank empty")

-- stamp: ファイル名から日時表示
eq(core.stamp("20260827-091530.md"), "2026-08-27 09:15", "stamp from filename")
eq(core.stamp("/home/x/memo/quick/20260827-091530.md"), "2026-08-27 09:15", "stamp from full path")
eq(core.stamp("self-introduction.md"), "self-introduction", "stamp falls back to basename")

-- label: タイトル優先、無ければ日時
eq(core.label("20260827-091530.md", { "# メモ" }), "メモ", "label prefers title")
eq(core.label("20260827-091530.md", { "" }), "2026-08-27 09:15", "label falls back to stamp")

-- filename: 日時から生成
eq(core.filename(os.time({ year = 2026, month = 8, day = 27, hour = 9, min = 15, sec = 30 })), "20260827-091530.md", "filename from time")

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all passed")
