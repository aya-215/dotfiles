return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- Git リポジトリルートを作業ディレクトリに設定
      git_repo_cwd = false,

      -- 送信後にClaudeターミナルにフォーカス
      focus_after_send = true,

     -- ターミナル設定（右分割）
      terminal = {
        split_side = "right",
        split_width_percentage = 0.35,
        provider = "snacks",
        auto_close = true,
        snacks_win_opts = {
          wo = {
            winblend = 15,  -- ターミナルの透過度（0-100）
            winhighlight = "Normal:Normal,NormalFloat:Normal",
          },
          style = "terminal",
          keys = {},  -- claudecode.nvim のデフォルトキー (<S-CR>) を無効化（WSLペースト問題対策）
        },
      },

      -- Diff設定（新しいタブで表示）
      diff_opts = {
        auto_close_on_accept = true,
        vertical_split = true,
        open_in_current_tab = true, -- 現在のタブで開く
        keep_terminal_focus = false,  -- Diff受け入れ後にClaudeにフォーカス
      },
    },
    config = function(_, opts)
      require("claudecode").setup(opts)

      -- diff表示時に他のエディタウィンドウを閉じる（ウィンドウ増加問題の回避策）
      -- Issue: https://github.com/coder/claudecode.nvim/issues/155
      vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*(proposed)*",
        callback = function()
          vim.schedule(function()
            local current_win = vim.api.nvim_get_current_win()
            local wins = vim.api.nvim_tabpage_list_wins(0)
            for _, win in ipairs(wins) do
              if win ~= current_win and vim.api.nvim_win_is_valid(win) then
                local buf = vim.api.nvim_win_get_buf(win)
                local buftype = vim.bo[buf].buftype
                local bufname = vim.api.nvim_buf_get_name(buf)
                local is_diff = vim.wo[win].diff

                -- ターミナル、diff関連バッファ、diffモードのウィンドウ以外を閉じる
                if buftype ~= "terminal"
                   and not bufname:match("%(proposed%)")
                   and not bufname:match("%(NEW FILE%)")
                   and not is_diff then
                  pcall(vim.api.nvim_win_close, win, false)
                end
              end
            end
          end)
        end,
      })
    end,
    keys = {
      -- 基本操作
      { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Claudeの表示切替" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Claudeにフォーカス" },

      -- セッション管理
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "セッション再開" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "セッション続行" },

      -- モデル選択
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "モデル選択" },

      -- コンテキスト追加
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "現在のバッファを追加" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "選択範囲をClaudeに送信" },
      {
        "<leader>as",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "ファイルを追加",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
      },

      -- Diff管理
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Diffを承認" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Diffを拒否" },
    },
  },
}
