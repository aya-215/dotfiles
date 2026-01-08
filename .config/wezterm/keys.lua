-- ========================================
-- キーバインディング設定 (Vim風)
-- ========================================

local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

function M.setup(config)
  -- ========================================
  -- Leaderキー設定 (tmux/Vim風)
  -- ========================================
  config.leader = { key = 's', mods = 'CTRL', timeout_milliseconds = 2000 }

  config.keys = {
    -- ========================================
    -- シェル環境切り替え (Ctrl+Alt+W/P)
    -- ========================================
    {
      key = 'w',
      mods = 'CTRL|ALT',
      action = act.SpawnCommandInNewTab {
        domain = { DomainName = 'WSL:Ubuntu-22.04' },
      },
    },
    {
      key = 'p',
      mods = 'CTRL|ALT',
      action = act.SpawnCommandInNewTab {
        args = { 'pwsh.exe', '-NoLogo' },
        domain = { DomainName = 'local' },
        cwd = 'D:\\',
      },
    },

    -- ========================================
    -- タブ操作 (Leader経由)
    -- ========================================
    {
      key = 'c',
      mods = 'LEADER',
      action = act.SpawnTab 'CurrentPaneDomain'
    },
    {
      key = 'p',
      mods = 'LEADER',
      action = act.SpawnCommandInNewTab {
        args = { 'pwsh.exe', '-NoLogo' },
        domain = { DomainName = 'local' },
        cwd = 'D:\\',
      },
    },
    {
      key = '&',
      mods = 'LEADER|SHIFT',
      action = act.CloseCurrentTab { confirm = true }
    },

    -- ========================================
    -- ペイン分割 (Vim風: s=split, v=vsplit)
    -- ========================================
    {
      key = 's',
      mods = 'LEADER',
      action = act.SplitPane {
        direction = 'Down',
        size = { Percent = 50 },
      }
    },
    {
      key = 'v',
      mods = 'LEADER',
      action = act.SplitPane {
        direction = 'Right',
        size = { Percent = 50 },
      }
    },

    -- ========================================
    -- ペイン移動 (Vim風: h/j/k/l)
    -- ========================================
    {
      key = 'h',
      mods = 'LEADER',
      action = act.ActivatePaneDirection 'Left'
    },
    {
      key = 'j',
      mods = 'LEADER',
      action = act.ActivatePaneDirection 'Down'
    },
    {
      key = 'k',
      mods = 'LEADER',
      action = act.ActivatePaneDirection 'Up'
    },
    {
      key = 'l',
      mods = 'LEADER',
      action = act.ActivatePaneDirection 'Right'
    },

    -- ========================================
    -- ペインサイズ調整 (Vim風: Shift+H/J/K/L)
    -- ========================================
    {
      key = 'H',
      mods = 'LEADER|SHIFT',
      action = act.AdjustPaneSize { 'Left', 5 }
    },
    {
      key = 'J',
      mods = 'LEADER|SHIFT',
      action = act.AdjustPaneSize { 'Down', 5 }
    },
    {
      key = 'K',
      mods = 'LEADER|SHIFT',
      action = act.AdjustPaneSize { 'Up', 5 }
    },
    {
      key = 'L',
      mods = 'LEADER|SHIFT',
      action = act.AdjustPaneSize { 'Right', 5 }
    },

    -- ========================================
    -- ペイン操作
    -- ========================================
    {
      key = 'x',
      mods = 'LEADER',
      action = act.CloseCurrentPane { confirm = true }
    },
    {
      key = 'z',
      mods = 'LEADER',
      action = act.TogglePaneZoomState
    },

    -- ========================================
    -- コピーモード (Vim風スクロール)
    -- ========================================
    {
      key = 'y',
      mods = 'LEADER',
      action = act.ActivateCopyMode
    },

    -- ========================================
    -- Quick Select Mode (ラベルベース選択)
    -- ========================================
    {
      key = 'u',
      mods = 'LEADER',
      action = act.QuickSelect
    },

    -- ========================================
    -- タブ直接移動 (Alt+数字)
    -- ========================================
    { key = '1', mods = 'ALT', action = act.ActivateTab(0) },
    { key = '2', mods = 'ALT', action = act.ActivateTab(1) },
    { key = '3', mods = 'ALT', action = act.ActivateTab(2) },
    { key = '4', mods = 'ALT', action = act.ActivateTab(3) },
    { key = '5', mods = 'ALT', action = act.ActivateTab(4) },
    { key = '6', mods = 'ALT', action = act.ActivateTab(5) },
    { key = '7', mods = 'ALT', action = act.ActivateTab(6) },
    { key = '8', mods = 'ALT', action = act.ActivateTab(7) },
    { key = '9', mods = 'ALT', action = act.ActivateTab(8) },

    -- Leader経由でもタブ番号移動可能
    { key = '1', mods = 'LEADER', action = act.ActivateTab(0) },
    { key = '2', mods = 'LEADER', action = act.ActivateTab(1) },
    { key = '3', mods = 'LEADER', action = act.ActivateTab(2) },
    { key = '4', mods = 'LEADER', action = act.ActivateTab(3) },
    { key = '5', mods = 'LEADER', action = act.ActivateTab(4) },
    { key = '6', mods = 'LEADER', action = act.ActivateTab(5) },
    { key = '7', mods = 'LEADER', action = act.ActivateTab(6) },
    { key = '8', mods = 'LEADER', action = act.ActivateTab(7) },
    { key = '9', mods = 'LEADER', action = act.ActivateTab(8) },

    -- ========================================
    -- フォントサイズ調整
    -- ========================================
    {
      key = '+',
      mods = 'CTRL',
      action = act.IncreaseFontSize
    },
    {
      key = '-',
      mods = 'CTRL',
      action = act.DecreaseFontSize
    },
    {
      key = '0',
      mods = 'CTRL',
      action = act.ResetFontSize
    },

    -- ========================================
    -- コピー＆ペースト
    -- ========================================
    {
      key = 'c',
      mods = 'CTRL|SHIFT',
      action = act.CopyTo 'Clipboard'
    },
    {
      key = 'v',
      mods = 'CTRL|SHIFT',
      action = act.PasteFrom 'Clipboard'
    },
    {
      key = 'v',
      mods = 'CTRL',
      action = act.PasteFrom 'Clipboard'
    },

    -- ========================================
    -- 検索
    -- ========================================
    {
      key = 'f',
      mods = 'CTRL|SHIFT',
      action = act.Search 'CurrentSelectionOrEmptyString'
    },

    -- ========================================
    -- スクロール
    -- ========================================
    {
      key = 'PageUp',
      mods = 'SHIFT',
      action = act.ScrollByPage(-1)
    },
    {
      key = 'PageDown',
      mods = 'SHIFT',
      action = act.ScrollByPage(1)
    },

    -- ========================================
    -- ユーティリティ
    -- ========================================
    {
      key = 'r',
      mods = 'CTRL|SHIFT',
      action = act.ReloadConfiguration
    },
    {
      key = 'p',
      mods = 'CTRL|SHIFT',
      action = act.ActivateCommandPalette
    },
    {
      key = 'l',
      mods = 'CTRL|SHIFT',
      action = act.ShowDebugOverlay
    },
  }

  -- ========================================
  -- コピーモード内のキーバインディング (Vim風)
  -- ========================================
  config.key_tables = {
    copy_mode = {
      -- 移動 (Vim風)
      { key = 'h', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
      { key = 'j', mods = 'NONE', action = act.CopyMode 'MoveDown' },
      { key = 'k', mods = 'NONE', action = act.CopyMode 'MoveUp' },
      { key = 'l', mods = 'NONE', action = act.CopyMode 'MoveRight' },

      -- 単語移動
      { key = 'w', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
      { key = 'b', mods = 'NONE', action = act.CopyMode 'MoveBackwardWord' },
      { key = 'e', mods = 'NONE', action = act.CopyMode 'MoveForwardWordEnd' },

      -- 行移動
      { key = '0', mods = 'NONE', action = act.CopyMode 'MoveToStartOfLine' },
      { key = '$', mods = 'SHIFT', action = act.CopyMode 'MoveToEndOfLineContent' },
      { key = '^', mods = 'SHIFT', action = act.CopyMode 'MoveToStartOfLineContent' },

      -- ページ移動
      { key = 'g', mods = 'NONE', action = act.CopyMode 'MoveToScrollbackTop' },
      { key = 'G', mods = 'SHIFT', action = act.CopyMode 'MoveToScrollbackBottom' },
      { key = 'u', mods = 'CTRL', action = act.CopyMode 'PageUp' },
      { key = 'd', mods = 'CTRL', action = act.CopyMode 'PageDown' },

      -- 画面内移動 (Vim H/M/L)
      { key = 'H', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportTop' },
      { key = 'M', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportMiddle' },
      { key = 'L', mods = 'SHIFT', action = act.CopyMode 'MoveToViewportBottom' },

      -- 選択開始
      { key = 'v', mods = 'NONE', action = act.CopyMode { SetSelectionMode = 'Cell' } },
      { key = 'V', mods = 'SHIFT', action = act.CopyMode { SetSelectionMode = 'Line' } },
      -- 注意: Ctrl+Vは通常のペーストに割り当てられているため、矩形選択は別のキーを使用してください

      -- ヤンク (コピーしてモード終了)
      { key = 'y', mods = 'NONE', action = act.Multiple {
        { CopyTo = 'ClipboardAndPrimarySelection' },
        { CopyMode = 'Close' },
      }},

      -- 検索
      { key = '/', mods = 'NONE', action = act.Search 'CurrentSelectionOrEmptyString' },
      { key = 'n', mods = 'NONE', action = act.CopyMode 'NextMatch' },
      { key = 'N', mods = 'SHIFT', action = act.CopyMode 'PriorMatch' },

      -- 文字ジャンプ (Vim f/t/F/T)
      { key = 'f', mods = 'NONE', action = act.CopyMode { JumpForward = { prev_char = false } } },
      { key = 'F', mods = 'SHIFT', action = act.CopyMode { JumpBackward = { prev_char = false } } },
      { key = 't', mods = 'NONE', action = act.CopyMode { JumpForward = { prev_char = true } } },
      { key = 'T', mods = 'SHIFT', action = act.CopyMode { JumpBackward = { prev_char = true } } },
      { key = ';', mods = 'NONE', action = act.CopyMode 'JumpAgain' },
      { key = ',', mods = 'NONE', action = act.CopyMode 'JumpReverse' },

      -- モード終了
      { key = 'q', mods = 'NONE', action = act.CopyMode 'Close' },
      { key = 'Escape', mods = 'NONE', action = act.CopyMode 'Close' },
    },

    search_mode = {
      { key = 'Enter', mods = 'NONE', action = act.CopyMode 'PriorMatch' },
      { key = 'Escape', mods = 'NONE', action = act.CopyMode 'Close' },
      { key = 'n', mods = 'CTRL', action = act.CopyMode 'NextMatch' },
      { key = 'p', mods = 'CTRL', action = act.CopyMode 'PriorMatch' },
      { key = 'u', mods = 'CTRL', action = act.CopyMode 'ClearPattern' },
    },
  }

  -- ========================================
  -- マウスバインディング
  -- ========================================
  config.mouse_bindings = {
    -- Ctrl+クリックでURLを開く
    {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'CTRL',
      action = act.OpenLinkAtMouseCursor,
    },
  }
end

return M
