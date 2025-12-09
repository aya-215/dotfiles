-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- 基本表示設定
vim.opt.number = true
vim.opt.relativenumber = true

-- クリップボード設定：ヤンク時にシステムクリップボードにコピー
vim.opt.clipboard = "unnamedplus"

-- 検索設定
vim.opt.ignorecase = true   -- 検索時に大文字・小文字を区別しない
vim.opt.smartcase = true    -- 検索文字列に大文字が含まれている場合は区別する
vim.opt.hlsearch = true     -- 検索結果をハイライト表示
vim.opt.wrapscan = true     -- 検索時、ファイルの末尾まで行ったら先頭に戻る

-- LSP パフォーマンス改善設定
vim.opt.updatetime = 300  -- LSP応答性改善
vim.opt.maxmempattern = 2000  -- メモリ使用量制限

-- タブ設定：タブ文字4個分の幅
vim.opt.tabstop = 4        -- タブ文字の幅
vim.opt.shiftwidth = 4     -- インデント幅
vim.opt.expandtab = false  -- タブ文字を使用
vim.opt.softtabstop = 0    -- タブ文字を使用

-- 自動フォーマッター無効化
vim.g.autoformat = false

-- ウィンドウ透過設定
vim.opt.winblend = 15  -- フロートウィンドウ・ターミナルの透過度（0-100）

-- OS検出によるシェル設定
if vim.fn.has("wsl") == 1 or vim.fn.has("unix") == 1 then
	-- WSL/Linux環境
	vim.opt.shell = vim.env.SHELL or "/usr/bin/zsh"
	vim.opt.shellcmdflag = "-c"
else
	-- Windows環境
	vim.opt.shell = "pwsh"
	vim.opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
end

-- ターミナル透過設定
vim.api.nvim_create_autocmd("TermOpen", {
	callback = function()
		vim.cmd("setlocal winblend=15")
		-- ターミナル背景を透明に設定
		vim.cmd("highlight Terminal guibg=NONE ctermbg=NONE")
		vim.cmd("highlight TerminalNormal guibg=NONE ctermbg=NONE")
	end,
})
