return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  lazy = true,
  cmd = "Neotree",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  keys = {
    { "<leader>E", "<cmd>Neotree toggle<cr>", desc = "Toggle Neo-tree" },
    { "<leader>ge", "<cmd>Neotree git_status<cr>", desc = "Git Explorer" },
    { "<leader>be", "<cmd>Neotree buffers<cr>", desc = "Buffer Explorer" },
  },
  opts = {
    close_if_last_window = true,
    popup_border_style = "rounded",
    enable_git_status = true,
    enable_diagnostics = true,
    sort_case_insensitive = false,

    default_component_configs = {
      indent = {
        indent_size = 2,
        with_markers = true,
        indent_marker = "│",
        last_indent_marker = "└",
        with_expanders = true,
        expander_collapsed = "",
        expander_expanded = "",
      },
      name = {
        use_git_status_colors = true,
      },
      git_status = {
        symbols = {
          added = "",
          modified = "",
          deleted = "✖",
          renamed = "󰁕",
          untracked = "",
          ignored = "",
          unstaged = "󰄱",
          staged = "",
          conflict = "",
        },
      },
    },

    filesystem = {
      follow_current_file = { enabled = true },
      hijack_netrw_behavior = "disabled",
      use_libuv_file_watcher = true,
      filtered_items = {
        visible = false,
        hide_dotfiles = false,
        hide_gitignored = true,
        hide_by_name = {
          ".DS_Store",
          "thumbs.db",
          "desktop.ini",
        },
        never_show = {
          ".DS_Store",
          "thumbs.db",
          "desktop.ini",
        },
      },
    },

    window = {
      position = "left",
      width = 35,
      mappings = {
        ["<space>"] = { "toggle_node", nowait = false },
        ["P"] = { "toggle_preview", config = { use_float = true } },
        ["H"] = "toggle_hidden",
        ["/"] = "fuzzy_finder",
        ["[g"] = "prev_git_modified",
        ["]g"] = "next_git_modified",
        ["s"] = "none", -- flash.nvimの's'を使えるように無効化
        ["S"] = "none", -- flash.nvimの'S'を使えるように無効化
      },
    },
  },
}
