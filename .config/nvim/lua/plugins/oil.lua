return {
  "stevearc/oil.nvim",
  lazy = false, -- lazy loadingは推奨されない（公式ドキュメントより）
  dependencies = {
    { "echasnovski/mini.icons", opts = {} },
    { "refractalize/oil-git-status.nvim" },
  },
  keys = {
    { "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
    { "<leader>e", "<cmd>Oil<cr>", desc = "Open file explorer" },
  },
  opts = {
    -- デフォルトのファイルエクスプローラーとして設定
    default_file_explorer = true,

    -- ディレクトリバッファのカラム表示設定
    columns = {
      "icon",
      -- "permissions",
      -- "size",
      -- "mtime",
    },

    -- バッファ管理設定
    buf_options = {
      buflisted = false,
      bufhidden = "hide",
    },

    -- ウィンドウ設定
    win_options = {
      wrap = false,
      signcolumn = "yes:2",
      cursorcolumn = false,
      foldcolumn = "0",
      spell = false,
      list = false,
      conceallevel = 3,
      concealcursor = "nvic",
    },

    -- 削除確認設定
    delete_to_trash = true,
    skip_confirm_for_simple_edits = false,

    -- プロンプト設定
    prompt_save_on_select_new_entry = true,

    -- 外部プログラムで開く設定（Windowsの場合）
    use_default_keymaps = true,

    -- カスタムキーマップ（デフォルトに追加）
    keymaps = {
      ["?"] = "actions.show_help",
      ["<CR>"] = "actions.select",
      ["<C-s>"] = { "actions.select", opts = { vertical = true }, desc = "Open in vertical split" },
      ["<C-h>"] = { "actions.select", opts = { horizontal = true }, desc = "Open in horizontal split" },
      ["<C-t>"] = { "actions.select", opts = { tab = true }, desc = "Open in new tab" },
      ["<C-p>"] = {
        callback = function()
          require("oil").open_preview({ vertical = true, split = "botright" })
        end,
        desc = "Open preview (right side)",
      },
      ["<esc>"] = "actions.close",
      ["<C-l>"] = "actions.refresh",
      ["-"] = "actions.parent",
      ["_"] = "actions.open_cwd",
      ["`"] = "actions.cd",
      ["~"] = { "actions.cd", opts = { scope = "tab" }, desc = "Change tab directory" },
      ["gs"] = "actions.change_sort",
      ["gx"] = "actions.open_external",
      ["g."] = "actions.toggle_hidden",
      ["g\\"] = "actions.toggle_trash",
      -- ファイルパスコピー
      ["y"] = "actions.copy_entry_path",
      ["Y"] = "actions.copy_entry_filename",
      -- Telescope連携
      ["<C-f>"] = {
        callback = function()
          local oil = require("oil")
          local dir = oil.get_current_dir()
          if dir then
            require("telescope.builtin").find_files({ cwd = dir })
          end
        end,
        desc = "Find files in current directory",
      },
      ["<C-g>"] = {
        callback = function()
          local oil = require("oil")
          local dir = oil.get_current_dir()
          if dir then
            require("telescope.builtin").live_grep({ cwd = dir })
          end
        end,
        desc = "Grep in current directory",
      },
      -- クイックジャンプ
      ["gh"] = {
        callback = function()
          require("oil").open(vim.fn.expand("~"))
        end,
        desc = "Go to home directory",
      },
      ["gd"] = {
        callback = function()
          require("oil").open(vim.fn.expand("~/.dotfiles"))
        end,
        desc = "Go to dotfiles",
      },
      -- Neo-tree連携
      ["go"] = {
        callback = function()
          local oil = require("oil")
          local entry = oil.get_cursor_entry()
          local current_dir = oil.get_current_dir() or vim.fn.getcwd()

          if entry then
            local reveal_path = current_dir .. entry.name
            -- ファイルの場合はreveal、ディレクトリの場合は開く
            if vim.fn.isdirectory(reveal_path) == 1 then
              vim.cmd("Neotree " .. vim.fn.fnameescape(reveal_path))
            else
              vim.cmd("Neotree reveal " .. vim.fn.fnameescape(reveal_path))
            end
          else
            vim.cmd("Neotree " .. vim.fn.fnameescape(current_dir))
          end
        end,
        desc = "Open in Neo-tree",
      },
    },

    -- ビュー設定
    view_options = {
      show_hidden = true,
      is_hidden_file = function(name, bufnr)
        return vim.startswith(name, ".")
      end,
      is_always_hidden = function(name, bufnr)
        local ignore_list = { ".DS_Store", "Thumbs.db", "desktop.ini" }
        return vim.tbl_contains(ignore_list, name)
      end,
      natural_order = true,
      case_insensitive = false,
      sort = {
        { "type", "asc" },
        { "name", "asc" },
      },
    },

    -- フロートウィンドウ設定（:Oil --float 使用時）
    float = {
      padding = 2,
      max_width = 0,
      max_height = 0,
      border = "rounded",
      win_options = {
        winblend = 0,
      },
      override = function(conf)
        return conf
      end,
    },

    -- プレビューウィンドウ設定
    preview = {
      max_width = 0.9,
      min_width = { 40, 0.4 },
      width = nil,
      max_height = 0.9,
      min_height = { 5, 0.1 },
      height = nil,
      border = "rounded",
      win_options = {
        winblend = 0,
      },
      update_on_cursor_moved = true,
    },

    -- プログレス表示設定
    progress = {
      max_width = 0.9,
      min_width = { 40, 0.4 },
      width = nil,
      max_height = { 10, 0.9 },
      min_height = { 5, 0.1 },
      height = nil,
      border = "rounded",
      minimized_border = "none",
      win_options = {
        winblend = 0,
      },
    },

    -- SSH設定
    ssh = {
      border = "rounded",
    },

    -- キーマップモード設定
    keymaps_help = {
      border = "rounded",
    },
  },
  config = function(_, opts)
    require("oil").setup(opts)
    require("oil-git-status").setup()
  end,
}
