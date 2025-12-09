return {
  "vim-scripts/vim-auto-save",
  event = { "InsertLeave", "TextChanged" },
  config = function()
    -- 自動保存を有効化
    vim.g.auto_save = 1

    -- インサートモード中の自動保存を無効化
    vim.g.auto_save_in_insert_mode = 0

    -- サイレントモード（保存通知を表示しない）
    vim.g.auto_save_silent = 1

    -- updatetime（200ms）の変更を防ぐ
    vim.g.auto_save_no_updatetime = 1

    -- ClaudeCodeのdiffバッファを自動保存から除外
    local function check_and_set_autosave()
      local bufname = vim.api.nvim_buf_get_name(0)
      local buftype = vim.bo.buftype

      -- 現在のバッファがClaudeCodeのdiffバッファか（proposedまたはacwriteタイプ）
      local is_proposed = bufname:match("%(proposed%)") or
                         buftype == "acwrite" or
                         vim.b.claudecode_diff_tab_name ~= nil

      -- 既にdiffバッファと判定された場合は早期リターン
      if is_proposed then
        vim.g.auto_save = 0
        return
      end

      -- 現在のタブ内にproposedバッファが存在するかチェック（元ファイル検出用）
      local wins = vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
      for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("%(proposed%)") then
          vim.g.auto_save = 0
          return
        end
      end

      -- 通常バッファでは有効化
      vim.g.auto_save = 1
    end

    -- vim-auto-saveが監視する全イベントをカバー
    vim.api.nvim_create_autocmd({"BufEnter", "CursorHold", "CursorHoldI", "InsertLeave", "TextChanged"}, {
      callback = check_and_set_autosave,
      desc = "ClaudeCodeのdiffバッファで自動保存を無効化",
    })
  end,
  keys = {
    { "<leader>ts", "<cmd>AutoSaveToggle<cr>", desc = "Toggle Auto Save" },
  },
}
