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
    {family = "Symbols Nerd Font Mono", weight = "Regular"},
    {family = "JetBrains Mono", weight = "Regular"},
  })

  -- イタリック体を無効化（日本語フォント対応）
  config.font_rules = {
    {
      italic = true,
      font = wezterm.font_with_fallback({
        {family = "HackGen Console NF", weight = "Regular", italic = false},
        {family = "Symbols Nerd Font Mono", weight = "Regular", italic = false},
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
      -- Catppuccin Mocha
      background = '#181825',  -- mantle

      active_tab = {
        bg_color = '#cba6f7',  -- mauve
        fg_color = '#11111b',  -- crust
        intensity = 'Bold',
      },

      inactive_tab = {
        bg_color = '#313244',  -- surface_0
        fg_color = '#9399b2',  -- overlay_2
      },

      inactive_tab_hover = {
        bg_color = '#45475a',  -- surface_1
        fg_color = '#cdd6f4',  -- fg
      },

      new_tab = {
        bg_color = '#313244',  -- surface_0
        fg_color = '#9399b2',  -- overlay_2
      },

      inactive_tab_edge = "none",
    },
    visual_bell = "#202020",
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
  -- プロセス名 → Nerd Fontアイコン
  local process_icons = {
    ['zsh']    = wezterm.nerdfonts.md_console,
    ['bash']   = wezterm.nerdfonts.md_console,
    ['fish']   = wezterm.nerdfonts.md_console,
    ['nvim']   = wezterm.nerdfonts.custom_vim,
    ['vim']    = wezterm.nerdfonts.custom_vim,
    ['node']   = wezterm.nerdfonts.dev_nodejs_small,
    ['python'] = wezterm.nerdfonts.dev_python,
    ['python3'] = wezterm.nerdfonts.dev_python,
    ['git']    = wezterm.nerdfonts.dev_git,
    ['claude'] = wezterm.nerdfonts.md_robot,
    ['docker'] = wezterm.nerdfonts.linux_docker,
    ['lua']    = wezterm.nerdfonts.seti_lua,
    ['cargo']  = wezterm.nerdfonts.dev_rust,
    ['go']     = wezterm.nerdfonts.seti_go,
    ['make']   = wezterm.nerdfonts.seti_makefile,
    ['ssh']    = wezterm.nerdfonts.md_server,
    ['top']    = wezterm.nerdfonts.md_chart_line,
    ['htop']   = wezterm.nerdfonts.md_chart_line,
    ['btop']   = wezterm.nerdfonts.md_chart_line,
  }
  local default_icon = wezterm.nerdfonts.md_console

  wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
    -- カレントディレクトリのパスを取得
    local cwd_uri = tab.active_pane.current_working_dir
    local cwd = ''

    if cwd_uri then
      if type(cwd_uri) == "userdata" then
        cwd = cwd_uri.file_path
      else
        cwd = cwd_uri
      end
    end

    if not cwd or cwd == '' then
      cwd = tab.active_pane.title
    end

    -- 最後のディレクトリ名を抽出（Windows/Unix両対応）
    local dir_name = cwd:gsub('[/\\]$', ''):match("([^/\\]+)$") or cwd

    -- プロセスアイコン
    local process = tab.active_pane.foreground_process_name or ''
    process = process:gsub('(.*/)', '')  -- パスを除去
    local icon = process_icons[process] or default_icon

    -- タブ番号（1から始まる）
    local index = tab.tab_index + 1

    -- サフィックス（ペイン数 + ズーム）
    local suffix = ''
    local pane_count = #tab.panes_with_info
    if pane_count > 1 then
      suffix = suffix .. ' [' .. pane_count .. ']'
    end
    if tab.active_pane.is_zoomed then
      suffix = suffix .. ' ' .. wezterm.nerdfonts.md_arrow_expand_all
    end

    local title = string.format(' %d: %s %s%s ', index, icon, dir_name, suffix)

    -- 丸角セパレーター (tmux catppuccin rounded風)
    local LEFT_CIRCLE = wezterm.nerdfonts.ple_left_half_circle_thick
    local RIGHT_CIRCLE = wezterm.nerdfonts.ple_right_half_circle_thick

    local edge_background = '#181825'  -- mantle

    if tab.is_active then
      return {
        { Background = { Color = edge_background } },
        { Foreground = { Color = '#cba6f7' } },  -- mauve
        { Text = LEFT_CIRCLE },
        { Background = { Color = '#cba6f7' } },  -- mauve
        { Foreground = { Color = '#11111b' } },   -- crust
        { Text = title },
        { Background = { Color = edge_background } },
        { Foreground = { Color = '#cba6f7' } },  -- mauve
        { Text = RIGHT_CIRCLE },
      }
    end

    return {
      { Background = { Color = edge_background } },
      { Foreground = { Color = '#313244' } },    -- surface_0
      { Text = LEFT_CIRCLE },
      { Background = { Color = '#313244' } },    -- surface_0
      { Foreground = { Color = '#9399b2' } },    -- overlay_2
      { Text = title },
      { Background = { Color = edge_background } },
      { Foreground = { Color = '#313244' } },    -- surface_0
      { Text = RIGHT_CIRCLE },
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
