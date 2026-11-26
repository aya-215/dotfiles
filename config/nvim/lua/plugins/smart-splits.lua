return {
  'smart-splits-nvim/smart-splits.nvim',
  version = '^3',
  lazy = false,
  -- v3 から tmux 連携は別プラグイン。tmux.nix の M-hjkl が見る @pane-is-vim はこれが立てる
  dependencies = {
    { 'smart-splits-nvim/backend-tmux', main = 'smart-splits-backend-tmux' },
  },
  opts = {
    mux = { backend = 'smart-splits-backend-tmux' },
    move = { at_edge = 'stop' },
  },
  config = function(_, opts)
    require('smart-splits').setup(opts)
    vim.keymap.set({ 'n', 'i', 't' }, '<M-h>', require('smart-splits').move_cursor_left, { desc = '左へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-j>', require('smart-splits').move_cursor_down, { desc = '下へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-k>', require('smart-splits').move_cursor_up, { desc = '上へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-l>', require('smart-splits').move_cursor_right, { desc = '右へ移動' })
    -- 矢印両対応（大西配列レイヤーのAlt+矢印を受ける）
    vim.keymap.set({ 'n', 'i', 't' }, '<M-Left>', require('smart-splits').move_cursor_left, { desc = '左へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-Down>', require('smart-splits').move_cursor_down, { desc = '下へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-Up>', require('smart-splits').move_cursor_up, { desc = '上へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-Right>', require('smart-splits').move_cursor_right, { desc = '右へ移動' })
  end,
}
