return {
  -- plenary.nvim - Telescopeの必須依存関係
  {
    "nvim-lua/plenary.nvim",
    lazy = true,
  },

  -- telescope-fzf-native.nvim - ネイティブfzfソーターでパフォーマンス向上
  {
    "nvim-telescope/telescope-fzf-native.nvim",
    build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release",
    lazy = true,
  },

  -- telescope.nvim - ファジーファインダー
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.8",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-fzf-native.nvim",
    },
    cmd = "Telescope",
    keys = {
      -- ファイル検索
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "ファイル検索" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "文字列検索 (Grep)" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "バッファ一覧" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "ヘルプタグ検索" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "最近使用したファイル" },

      -- Git関連
      { "<leader>gc", "<cmd>Telescope git_commits<cr>", desc = "Gitコミット履歴" },
      { "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git変更状態" },
      { "<leader>gb", "<cmd>Telescope git_branches<cr>", desc = "Gitブランチ" },

      -- LSP関連
      { "<leader>ld", "<cmd>Telescope diagnostics<cr>", desc = "診断情報" },
      { "<leader>lr", "<cmd>Telescope lsp_references<cr>", desc = "LSP参照" },
      { "<leader>ls", "<cmd>Telescope lsp_document_symbols<cr>", desc = "ドキュメントシンボル" },

      -- その他
      { "<leader>fc", "<cmd>Telescope commands<cr>", desc = "コマンド一覧" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>", desc = "キーマップ一覧" },
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")

      telescope.setup({
        defaults = {
          -- デフォルト設定
          prompt_prefix = "🔍 ",
          selection_caret = "➤ ",
          path_display = { "truncate" },

          -- ファイルフィルタリング
          file_ignore_patterns = {
            "node_modules/.*",
            "build/.*",
            "%.git/.*",
            "%.env$",
            "%.env%..*",
            "lazy%-lock%.json",
          },

          -- キーマップ
          mappings = {
            i = {
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["<Esc>"] = actions.close,
            },
            n = {
              ["q"] = actions.close,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
            },
          },

          -- レイアウト設定
          layout_strategy = "horizontal",
          layout_config = {
            horizontal = {
              prompt_position = "top",
              preview_width = 0.55,
            },
            width = 0.87,
            height = 0.80,
          },
          sorting_strategy = "ascending",
        },

        pickers = {
          -- find_files設定
          find_files = {
            hidden = true,
            respect_gitignore = true,
          },

          -- live_grep設定
          live_grep = {
            additional_args = function()
              return { "--hidden", "--no-ignore" }
            end,
          },

          -- buffers設定
          buffers = {
            sort_lastused = true,
            mappings = {
              i = {
                ["<C-d>"] = actions.delete_buffer,
              },
              n = {
                ["dd"] = actions.delete_buffer,
              },
            },
          },
        },

        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },
        },
      })

      -- fzf-native拡張を読み込み (cmake未インストールのためコメントアウト)
      -- telescope.load_extension("fzf")
    end,
  },
}
