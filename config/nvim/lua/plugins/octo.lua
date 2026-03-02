return {
  'pwntester/octo.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  cmd = 'Octo',
  keys = {
    { '<leader>gop', '<cmd>Octo pr list<cr>', desc = 'PR一覧' },
    { '<leader>goi', '<cmd>Octo issue list<cr>', desc = 'Issue一覧' },
    { '<leader>goc', '<cmd>Octo pr create<cr>', desc = 'PR作成' },
    { '<leader>gor', '<cmd>Octo review start<cr>', desc = 'レビュー開始' },
  },
  opts = {
    picker = 'telescope',
    enable_builtin = true,
    default_merge_method = 'squash',
    snippet_context_lines = 4,
    mappings = {
      submit_win = {
        approve_review   = { lhs = '<C-a>',  desc = 'approve review',         mode = { 'n', 'i' } },
        comment_review   = { lhs = '<C-CR>', desc = 'comment review',         mode = { 'n', 'i' } },
        request_changes  = { lhs = '<C-r>',  desc = 'request changes review', mode = { 'n', 'i' } },
        close_review_tab = { lhs = '<C-c>',  desc = 'close review tab',       mode = { 'n', 'i' } },
      },
    },
  },
  config = function(_, opts)
    require('octo').setup(opts)
    vim.treesitter.language.register('markdown', 'octo')
  end,
}
