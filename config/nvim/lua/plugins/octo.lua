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
    { '<leader>gor', '<cmd>Octo review<cr>',          desc = 'レビュー開始/再開' },
    { '<leader>gos', '<cmd>Octo review submit<cr>',  desc = 'レビュー送信' },
    { '<leader>gok', '<cmd>Octo pr checkout<cr>',    desc = 'PRチェックアウト' },
    { '<leader>gox', '<cmd>Octo pr checks<cr>',      desc = 'CIチェック確認' },
    { '<leader>goe', '<cmd>Octo pr reload<cr>',      desc = 'PR再読込' },
    { '<leader>gom', '<cmd>Octo pr merge commit delete<cr>', desc = 'PRマージ(commit+削除)' },
    { '<leader>goa', '<cmd>Octo comment add<cr>',            desc = 'コメント追加' },
  },
  opts = {
    picker = 'telescope',
    enable_builtin = true,
    default_merge_method = 'squash',
    snippet_context_lines = 4,
    mappings = {
      issue = {
        add_comment     = { lhs = '<localleader>c', desc = 'add comment' },
        delete_comment  = { lhs = '<localleader>d', desc = 'delete comment' },
        add_reply       = { lhs = '<localleader>w', desc = 'add reply' },
        react_thumbs_up = { lhs = '<localleader>g', desc = 'react thumbs up' },
      },
      pull_request = {
        add_comment     = { lhs = '<localleader>c', desc = 'add comment' },
        delete_comment  = { lhs = '<localleader>d', desc = 'delete comment' },
        add_reply       = { lhs = '<localleader>w', desc = 'add reply' },
        react_thumbs_up = { lhs = '<localleader>g', desc = 'react thumbs up' },
      },
      review_thread = {
        add_comment     = { lhs = '<localleader>c', desc = 'add comment' },
        delete_comment  = { lhs = '<localleader>d', desc = 'delete comment' },
        add_reply       = { lhs = '<localleader>w', desc = 'add reply' },
        resolve_thread  = { lhs = '<localleader>t', desc = 'resolve thread' },
        react_thumbs_up = { lhs = '<localleader>g', desc = 'react thumbs up' },
      },
      review_diff = {
        add_review_comment = { lhs = '<localleader>c', desc = 'add review comment', mode = { 'n', 'x' } },
      },
      submit_win = {
        approve_review   = { lhs = '<C-a>',  desc = 'approve review',         mode = { 'n', 'i' } },
        comment_review   = { lhs = '<C-p>',  desc = 'comment review',         mode = { 'n', 'i' } },
        request_changes  = { lhs = '<C-r>',  desc = 'request changes review', mode = { 'n', 'i' } },
        close_review_tab = { lhs = '<C-c>',  desc = 'close review tab',       mode = { 'n', 'i' } },
      },
    },
  },
  config = function(_, opts)
    require('octo').setup(opts)
    vim.treesitter.language.register('markdown', 'octo')

    -- review submit windowでもblink-cmp-gitのメンション補完を有効にする
    vim.api.nvim_create_autocmd('BufWinEnter', {
      pattern = '*',
      callback = function(ev)
        local bufnr = ev.buf
        -- submit windowは syntax=octo だが filetype が未設定
        if vim.bo[bufnr].syntax == 'octo' and vim.bo[bufnr].filetype == '' then
          vim.bo[bufnr].filetype = 'octo'
        end
      end,
    })
  end,
}
