return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    preset = "helix",
    spec = {
      {
        mode = { "n", "v" },
        { "<leader>a", group = "AI/Claude" },
        { "<leader>b", group = "バッファ" },
        { "<leader>c", group = "コード" },
        { "<leader>f", group = "ファイル" },
        { "<leader>g", group = "Git" },
        { "<leader>go", group = "Octo" },
        { "<leader>h", group = "Git hunk" },
        { "<leader>l", group = "LSP" },
        { "<leader>q", group = "セッション" },
        { "<leader>r", group = "Markdown" },
        { "<leader>s", group = "検索" },
        { "<leader>u", group = "UIトグル" },
        { "<leader>w", group = "ウィンドウ", proxy = "<c-w>" },
        { "<leader>x", group = "診断/Quickfix" },
        { "[", group = "prev" },
        { "]", group = "next" },
        { "g", group = "goto" },
        { "gs", group = "surround" },
        { "z", group = "fold" },
      },
    },
  },
  keys = {
    {
      "<leader>?",
      function()
        require("which-key").show({ global = false })
      end,
      desc = "バッファローカルのキーマップ表示",
    },
  },
}
