return {
  {
    "saghen/blink.cmp",
    event = { "InsertEnter", "CmdlineEnter" }, -- LazyVim公式推奨: 編集開始時に読み込み
    version = "*",
    dependencies = {
      "rafamadriz/friendly-snippets",
      {
        "L3MON4D3/LuaSnip",
        version = "v2.*",
      },
      "Kaiser-Yang/blink-cmp-git",
    },
    opts = {
      keymap = {
        preset = "default",
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-e>"] = { "hide" },
        ["<C-y>"] = { "select_and_accept" },

        ["<C-p>"] = { "select_prev", "fallback" },
        ["<C-n>"] = { "select_next", "fallback" },

        ["<C-b>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },

        ["<Tab>"] = {
          function(cmp)
            if cmp.snippet_active() then
              return cmp.accept()
            else
              return cmp.select_and_accept()
            end
          end,
          "snippet_forward",
          "fallback",
        },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
      },

      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = "mono",
      },

      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        per_filetype = {
          octo = { "lsp", "path", "snippets", "buffer", "git" },
          gitcommit = { "lsp", "path", "snippets", "buffer", "git" },
        },
        providers = {
          buffer = {
            max_items = 4,
            min_keyword_length = 4,
            score_offset = -3,
          },
          git = {
            module = "blink-cmp-git",
            name = "Git",
            score_offset = 100,
            async = true,
            opts = {
              -- octo.nvim のコメントバッファ(buftype=prompt)でもキャッシュリロードを許可
              should_reload_cache = function()
                local utils = require("blink-cmp-git.utils")
                if not utils.source_provider_enabled() then
                  return false
                end
                -- octo バッファでは常にリロード許可
                if vim.bo.filetype == "octo" then
                  return true
                end
                -- prompt バッファはデフォルト通りスキップ
                if vim.bo.buftype == "prompt" then
                  return false
                end
                return true
              end,
            },
          },
        },
      },

      snippets = {
        preset = "luasnip",
      },

      completion = {
        accept = {
          auto_brackets = {
            enabled = true,
          },
        },
        menu = {
          draw = {
            treesitter = { "lsp" },
          },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
        },
        ghost_text = {
          enabled = true,
        },
      },

      signature = {
        enabled = true,
      },
    },
    opts_extend = { "sources.default" },
  },
}
