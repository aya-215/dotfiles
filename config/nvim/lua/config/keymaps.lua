-- キーマップはVeryLazyイベントで自動的に読み込まれます
-- デフォルトのキーマップ: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- 追加のキーマップをここに記述します


-- Visual mode: インデント後も選択を維持
vim.keymap.set("v", "<", "<gv", { desc = "インデント（選択維持）" })
vim.keymap.set("v", ">", ">gv", { desc = "インデント（選択維持）" })

-- Normal mode: Escで検索ハイライトを解除
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "検索ハイライトを解除" })


-- ターミナルモード拡張
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    -- バッファ名が正しく設定されるまで待機
    vim.defer_fn(function()
      local bufname = vim.api.nvim_buf_get_name(0)
      local is_claude = string.find(bufname:lower(), "claude") ~= nil or
                        string.find(bufname:lower(), "snacks") ~= nil
      local is_lazygit = string.find(bufname:lower(), "lazygit") ~= nil

      -- ESCキーの動作: Claude Code/LazyGitではESCをそのまま渡す、その他のターミナルではNormalモードへ
      if is_claude or is_lazygit then
        vim.keymap.set("t", "<Esc>", "<Esc>", {
          buffer = 0,
          desc = "ESCをそのまま渡す（Claude Code/LazyGit用）"
        })
		-- Ctrl+eでNormalモードへ
		vim.keymap.set("t", "<C-e>", "<C-\\><C-n>", {
			buffer = 0,
			desc = "Normalモードに移行"
		})

      else
        vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", {
          buffer = 0,
          desc = "ターミナルモードを終了"
        })
      end
    end, 50)

    -- 追加のウィンドウ操作（ターミナルモードのみ）
    vim.keymap.set("t", "<A-w>", "<C-\\><C-n><C-w>w", { buffer = 0, desc = "ウィンドウを順番に切り替え" })
    vim.keymap.set("t", "<A-v>", "<C-\\><C-n><C-w>v", { buffer = 0, desc = "縦に分割" })
    vim.keymap.set("t", "<A-s>", "<C-\\><C-n><C-w>s", { buffer = 0, desc = "横に分割" })
    vim.keymap.set("t", "<A-q>", "<C-\\><C-n><C-w>q", { buffer = 0, desc = "ウィンドウを閉じる" })

    -- Ctrl+Jでターミナルに改行を送信
    vim.keymap.set("t", "<C-j>", function()
      local lf_key = vim.api.nvim_replace_termcodes("<C-v><C-j>", true, false, true)
      vim.api.nvim_feedkeys(lf_key, "n", false)
    end, {
      buffer = 0,
      desc = "ターミナルに改行を送信"
    })
  end,
  desc = "ターミナルモードのキーバインド設定"
})

-- ===================================================
-- ヤンク・削除・ペーストの改善
-- ===================================================

-- Visual コピー時にカーソル位置を保持
vim.keymap.set('x', 'y', 'mzy`z', { desc = 'ヤンク（カーソル位置保持）' })

-- x でレジスタに入れずに削除（カット）
vim.keymap.set('n', 'x', '"_d', { desc = 'レジスタに入れず削除' })
vim.keymap.set('n', 'X', '"_D', { desc = 'レジスタに入れず行末まで削除' })
vim.keymap.set('x', 'x', '"_x', { desc = 'レジスタに入れず削除（Visual）' })
vim.keymap.set('o', 'x', 'd', { desc = 'オペレータ待機: 削除' })

-- ペースト時にインデント自動調整＋カーソルをペースト範囲末尾に配置＋glowエフェクト
vim.keymap.set('n', 'p', function()
  require('undo-glow').highlight_changes()
  vim.cmd('normal! ]p`]')
end, { desc = 'ペースト（インデント調整＋末尾＋glow）' })

vim.keymap.set('n', 'P', function()
  require('undo-glow').highlight_changes()
  vim.cmd('normal! ]P`]')
end, { desc = 'ペースト上（インデント調整＋末尾＋glow）' })

-- ===================================================
-- UIトグル (<leader>u)
-- ===================================================
vim.keymap.set('n', '<leader>uw', '<cmd>set wrap!<cr>', { desc = '折り返し表示の切替' })
vim.keymap.set('n', '<leader>un', '<cmd>set number!<cr>', { desc = '行番号の切替' })
vim.keymap.set('n', '<leader>ur', '<cmd>set relativenumber!<cr>', { desc = '相対行番号の切替' })
vim.keymap.set('n', '<leader>us', '<cmd>set spell!<cr>', { desc = 'スペルチェックの切替' })
vim.keymap.set('n', '<leader>ul', '<cmd>set list!<cr>', { desc = '不可視文字の切替' })
vim.keymap.set('n', '<leader>uc', '<cmd>set cursorline!<cr>', { desc = 'カーソル行ハイライトの切替' })

-- ===================================================
-- 診断/Quickfix (<leader>x)
-- ===================================================
vim.keymap.set('n', '<leader>xq', '<cmd>copen<cr>', { desc = 'Quickfixリストを開く' })
vim.keymap.set('n', '<leader>xl', '<cmd>lopen<cr>', { desc = 'Locationリストを開く' })
vim.keymap.set('n', '<leader>xx', vim.diagnostic.setloclist, { desc = '診断をLocationリストに送る' })
