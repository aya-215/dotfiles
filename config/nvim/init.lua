-- Leader キーは最初に設定する必要がある
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- PATH設定 (起動時間最適化: vim.scheduleで遅延実行)
vim.schedule(function()
  local nvm_node_path = vim.fn.expand("$HOME/.nvm/versions/node/v24.11.1/bin")
  -- WSL環境: nvmとsystem32のripgrepを優先
  vim.env.PATH = nvm_node_path .. ":" .. "C:\\Windows\\System32;" .. (vim.env.PATH or "")
end)

-- プロジェクト固有の.nvimrcを自動読み込み
vim.opt.exrc = true
vim.opt.secure = true

-- 設定ファイルの読み込み
require("config.options")
require("config.keymaps")

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
