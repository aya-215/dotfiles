return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    scroll = {
      enabled = true,
      -- promptバッファ以外、またはターミナルのNormalモード時のみスムーズスクロールを有効化
      filter = function(buf)
        local buftype = vim.bo[buf].buftype
        if buftype == "prompt" then
          return false
        end
        -- ターミナルバッファの場合、Normalモード時のみ有効
        if buftype == "terminal" then
          local mode = vim.api.nvim_get_mode().mode
          return mode == "n" or mode == "nt"
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
