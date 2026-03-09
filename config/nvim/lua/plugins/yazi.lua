return {
  'mikavilpas/yazi.nvim',
  version = '*',
  event = 'VeryLazy',
  dependencies = {
    { 'nvim-lua/plenary.nvim', lazy = true },
  },
  keys = {
    { '<leader>y', '<cmd>Yazi<cr>', desc = 'Open yazi at current file' },
    { '<leader>Y', '<cmd>Yazi cwd<cr>', desc = 'Open yazi in cwd' },
    { '<c-up>', '<cmd>Yazi toggle<cr>', desc = 'Resume last yazi session' },
  },
  opts = {
    open_for_directories = false,
  },
}
