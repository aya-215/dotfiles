return {
  'mrjones2014/smart-splits.nvim',
  lazy = false,
  opts = {
    at_edge = 'stop',
  },
  config = function(_, opts)
    require('smart-splits').setup(opts)
    vim.keymap.set({ 'n', 'i', 't' }, '<M-h>', require('smart-splits').move_cursor_left, { desc = '左へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-j>', require('smart-splits').move_cursor_down, { desc = '下へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-k>', require('smart-splits').move_cursor_up, { desc = '上へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-l>', require('smart-splits').move_cursor_right, { desc = '右へ移動' })
  end,
}
