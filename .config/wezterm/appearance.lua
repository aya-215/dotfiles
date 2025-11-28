-- ========================================
-- 外観設定（Appearance Configuration）
-- ========================================

local wezterm = require 'wezterm'

local M = {}

function M.setup(config)
  -- ========================================
  -- ウィンドウ設定
  -- ========================================
  -- 透明度（0.85に設定）
  config.window_background_opacity = 0.85

  -- ウィンドウ装飾（タイトルバー非表示、リサイズ可能）
  config.window_decorations = "RESIZE"

  -- ウィンドウパディング
  config.window_padding = {
    left = 8,
    right = 8,
    top = 8,
    bottom = 8,
  }

  config.window_frame = {
    inactive_titlebar_bg = "none",
    active_titlebar_bg = "none",
  }

  config.window_background_gradient = {
    colors = { "#000000" },
  }

  -- ========================================
  -- フォント設定
  -- ========================================
  -- フォントサイズ（ユーザー指定により10.5を維持）
  config.font_size = 10.5

  -- フォント（フォールバック対応、太字で見やすく）
  config.font = wezterm.font_with_fallback({
    {family = "HackGen Console NF", weight = "Regular"},
    {family = "Cascadia Code NF", weight = "Regular"},
    {family = "JetBrains Mono", weight = "Regular"},
  })

  -- イタリック体を無効化（日本語フォント対応）
  config.font_rules = {
    {
      italic = true,
      font = wezterm.font_with_fallback({
        {family = "HackGen Console NF", weight = "Regular", italic = false},
        {family = "Cascadia Code NF", weight = "Regular", italic = false},
        {family = "JetBrains Mono", weight = "Regular", italic = false},
      }),
    },
  }

  -- 行間設定
  config.line_height = 1.2

  -- ========================================
  -- カーソル設定
  -- ========================================
  config.default_cursor_style = "BlinkingBlock"
  config.cursor_blink_rate = 500
  config.force_reverse_video_cursor = true

  -- ========================================
  -- カラースキーム
  -- ========================================
  config.color_scheme = "catppuccin-mocha"

  -- ========================================
  -- タブバー設定
  -- ========================================
  config.hide_tab_bar_if_only_one_tab = true
  config.show_new_tab_button_in_tab_bar = false
  config.show_close_tab_button_in_tabs = false
  config.use_fancy_tab_bar = false
  config.tab_bar_at_bottom = false

  -- ========================================
  -- タブバーの色設定
  -- ========================================
  config.colors = {
    tab_bar = {
      -- タブバーの背景
      background = '#0b0022',

      -- アクティブなタブ（明るい青）
      active_tab = {
        bg_color = '#2b7de9',
        fg_color = '#ffffff',
        intensity = 'Bold',
      },

      -- 非アクティブなタブ（暗い青系）
      inactive_tab = {
        bg_color = '#1a1b26',
        fg_color = '#7aa2f7',
      },

      -- ホバー時
      inactive_tab_hover = {
        bg_color = '#3b4261',
        fg_color = '#c0caf5',
      },

      -- 新規タブボタン
      new_tab = {
        bg_color = '#1a1b26',
        fg_color = '#7aa2f7',
      },

      inactive_tab_edge = "none",
    },
    -- ビジュアルベルの色
    visual_bell = "#202020",
    compose_cursor = "rgba(255, 255, 255, 0.0)",  -- IME入力中のカーソル色（透明）
    cursor_bg = "rgba(255, 255, 255, 0.0)",        -- 通常時のカーソル背景色（透明）
    cursor_border = "rgba(255, 255, 255, 0.0)",    -- カーソル枠線色（透明）
  }

  -- ========================================
  -- ベル設定
  -- ========================================
  config.audible_bell = "Disabled"
  config.visual_bell = {
    fade_in_function = "EaseIn",
    fade_in_duration_ms = 150,
    fade_out_function = "EaseOut",
    fade_out_duration_ms = 150,
  }

  -- ========================================
  -- スクロール設定
  -- ========================================
  config.scrollback_lines = 10000
  config.enable_scroll_bar = true
end

-- ========================================
-- タブタイトルのカスタマイズ（PowerLine風）
-- ========================================
function M.setup_tab_title()
  wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
    -- カレントディレクトリのパスを取得
    local cwd_uri = tab.active_pane.current_working_dir
    local cwd = ''

    if cwd_uri then
      if type(cwd_uri) == "userdata" then
        -- Windowsの場合、file_pathプロパティを使用
        cwd = cwd_uri.file_path
      else
        -- 文字列の場合はそのまま使用
        cwd = cwd_uri
      end
    end

    -- cwdが取得できない場合はタイトルを使用
    if not cwd or cwd == '' then
      cwd = tab.active_pane.title
    end

    -- 最後のディレクトリ名を抽出（Windows/Unix両対応）
    local dir_name = cwd:gsub('[/\\]$', ''):match("([^/\\]+)$") or cwd

    -- タブ番号（1から始まる）
    local index = tab.tab_index + 1

    -- 表示テキスト: "1: Documents" 形式
    local title = string.format(' %d: %s ', index, dir_name)

    -- PowerLine矢印記号
    local SOLID_LEFT_ARROW = wezterm.nerdfonts.pl_right_hard_divider
    local SOLID_RIGHT_ARROW = wezterm.nerdfonts.pl_left_hard_divider

    local edge_background = '#0b0022'  -- タブバーの背景色

    -- アクティブなタブの場合
    if tab.is_active then
      return {
        { Background = { Color = edge_background } },
        { Foreground = { Color = '#2b7de9' } },
        { Text = SOLID_LEFT_ARROW },
        { Background = { Color = '#2b7de9' } },
        { Foreground = { Color = '#ffffff' } },
        { Text = title },
        { Background = { Color = edge_background } },
        { Foreground = { Color = '#2b7de9' } },
        { Text = SOLID_RIGHT_ARROW },
      }
    end

    -- 非アクティブなタブの場合
    return {
      { Background = { Color = edge_background } },
      { Foreground = { Color = '#1a1b26' } },
      { Text = SOLID_LEFT_ARROW },
      { Background = { Color = '#1a1b26' } },
      { Foreground = { Color = '#7aa2f7' } },
      { Text = title },
      { Background = { Color = edge_background } },
      { Foreground = { Color = '#1a1b26' } },
      { Text = SOLID_RIGHT_ARROW },
    }
  end)
end

-- ========================================
-- 起動時動作（ウィンドウを最大化）
-- ========================================
function M.setup_startup()
  wezterm.on('gui-startup', function()
    local _, _, window = wezterm.mux.spawn_window({})
    window:gui_window():maximize()
  end)
end

return M
