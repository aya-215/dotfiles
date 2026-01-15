return {
  "y3owk1n/undo-glow.nvim",
  event = "VeryLazy",
  opts = {
    animation = {
      enabled = true,
      duration = 400,
      animation_type = "fade",
      fps = 60,
      window_scoped = true,
    },
    highlights = {
      undo = { hl_color = { bg = "#693232" } },
      redo = { hl_color = { bg = "#2F4640" } },
      yank = { hl_color = { bg = "#7A683A" } },
      paste = { hl_color = { bg = "#325B5B" } },
      search = { hl_color = { bg = "#5C475C" } },
      comment = { hl_color = { bg = "#4A4A5A" } },
    },
  },
  config = function(_, opts)
    require("undo-glow").setup(opts)
    -- yank時のハイライトはautocmdで処理
    vim.api.nvim_create_autocmd("TextYankPost", {
      desc = "Highlight when yanking text",
      callback = function()
        require("undo-glow").yank()
      end,
    })
  end,
  keys = {
    { "u", function() require("undo-glow").undo() end, desc = "Undo with glow" },
    { "U", function() require("undo-glow").redo() end, desc = "Redo with glow" },
    { "p", function() require("undo-glow").paste_below() end, desc = "Paste below with glow" },
    { "P", function() require("undo-glow").paste_above() end, desc = "Paste above with glow" },
    { "<C-r>", function() require("undo-glow").paste_below() end, desc = "Paste register with glow", mode = "i" },
    { "n", function() require("undo-glow").search_next() end, desc = "Search next with glow" },
    { "N", function() require("undo-glow").search_prev() end, desc = "Search prev with glow" },
    { "*", function() require("undo-glow").search_star() end, desc = "Search word forward with glow" },
    { "#", function() require("undo-glow").search_hash() end, desc = "Search word backward with glow" },
    { "gc", function() require("undo-glow").comment() end, desc = "Comment with glow", mode = { "n", "x" } },
    { "gcc", function() require("undo-glow").comment_line() end, desc = "Comment line with glow" },
  },
}
