return {
  "folke/flash.nvim",
  event = "VeryLazy",
  ---@type Flash.Config
  opts = {
    labels = "asdfghjklqwertyuiopzxcvbnm",
    search = {
      multi_window = true, -- 全ウィンドウで検索
      forward = true,
      wrap = true,
      mode = "exact", -- 最も高速
      incremental = false,
    },
    jump = {
      jumplist = true, -- ジャンプ履歴に追加
      pos = "start",
      autojump = false, -- 1つでも確認（誤操作防止）
    },
    label = {
      distance = true, -- カーソル近くを優先
      reuse = "lowercase",
      current = true,
      after = true,
      style = "overlay",
    },
    highlight = {
      backdrop = true, -- 背景を暗くして見やすく
      matches = true,
      priority = 5000,
    },
    modes = {
      char = {
        enabled = true, -- f/t モーションも強化
        autohide = true,
        multi_line = false, -- f/tは同一行のみ
        jump_labels = true, -- f/tでもラベル表示
        config = function(opts)
          -- マクロ記録/実行中はラベル非表示
          opts.jump_labels = opts.jump_labels
            and vim.fn.mode(true):find("no") == nil
            and vim.v.count == 0
            and vim.fn.reg_executing() == ""
            and vim.fn.reg_recording() == ""
        end,
      },
      search = {
        enabled = true,
        highlight = { backdrop = false },
        jump = { history = true, register = true, nohlsearch = true },
      },
      treesitter = {
        labels = "abcdefghijklmnopqrstuvwxyz",
        jump = { pos = "range" },
        label = { before = true, after = true, style = "inline" },
      },
    },
  },
  keys = {
    {
      "s",
      mode = { "n", "x", "o" },
      function()
        require("flash").jump()
      end,
      desc = "Flash jump",
    },
    {
      "S",
      mode = { "n", "x", "o" },
      function()
        require("flash").treesitter()
      end,
      desc = "Flash treesitter",
    },
    {
      "r",
      mode = "o",
      function()
        require("flash").remote()
      end,
      desc = "Remote flash",
    },
    {
      "R",
      mode = { "o", "x" },
      function()
        require("flash").treesitter_search()
      end,
      desc = "Treesitter search",
    },
    {
      "<C-s>",
      mode = "c",
      function()
        require("flash").toggle()
      end,
      desc = "Toggle flash search",
    },
  },
}
