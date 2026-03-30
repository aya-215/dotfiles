return {
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = {
      cmdline = {
        view = "cmdline_popup", -- コマンドラインをポップアップ表示
      },
      presets = {
        bottom_search = false, -- 検索を中央に表示
        command_palette = true, -- コマンドパレットスタイル
        long_message_to_split = true, -- 長いメッセージを分割
      },
    },
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
  },
}
