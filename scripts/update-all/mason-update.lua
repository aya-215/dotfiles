-- update-all スキル用: インストール済みの Mason パッケージを最新版に上げる。
--   nvim --headless -c "luafile ~/.dotfiles/scripts/update-all/mason-update.lua"
-- 結果は「名前: 旧 -> 新」「名前 updated / FAILED」を1行ずつ出す。
require('lazy').load({ plugins = { 'mason.nvim' } })
local mr = require('mason-registry')
local pending = 0

local function finish()
  if pending == 0 then
    vim.schedule(function() vim.cmd('qa!') end)
  end
end

mr.refresh(function()
  for _, p in ipairs(mr.get_installed_packages()) do
    local cur, latest = p:get_installed_version(), p:get_latest_version()
    if cur == latest then
      io.write(p.name .. ': up-to-date ' .. tostring(cur) .. '\n')
    else
      pending = pending + 1
      io.write(p.name .. ': ' .. tostring(cur) .. ' -> ' .. tostring(latest) .. '\n')
      p:install({ version = latest }, function(ok, err)
        io.write(p.name .. (ok and ' updated' or (' FAILED ' .. tostring(err))) .. '\n')
        pending = pending - 1
        finish()
      end)
    end
  end
  finish()
end)

vim.defer_fn(function()
  io.write('timeout\n')
  vim.cmd('qa!')
end, 240000)
