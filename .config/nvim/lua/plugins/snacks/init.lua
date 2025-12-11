return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    scroll = {
      enabled = true,
      -- ターミナルバッファでは完全に無効化（ペースト時の文字欠落防止）
      -- https://github.com/folke/snacks.nvim/issues/384
      filter = function(buf)
        local buftype = vim.bo[buf].buftype
        if buftype == "prompt" or buftype == "terminal" then
          return false
        end
        return true
      end,
    },
    dashboard = require("plugins.snacks.dashboard"),
    styles = {
      terminal = {
        wo = {
          winblend = 15,  -- ターミナルの透過度
        },
      },
    },
  },
}
