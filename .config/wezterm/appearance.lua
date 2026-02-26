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
  config.window_background_opacity = 0.3

  -- 黒ベースの半透明グラデーション（Acrylicぼかしの上に重ねる）
  config.window_background_gradient = {
    colors = { "#000000" },
  }

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

  -- Acrylicぼかし（Windows 11）
  config.win32_system_backdrop = "Acrylic"
  config.win32_acrylic_accent_color = "#000000"

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
  config.tab_max_width = 60

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

    -- プロセス名からアイコンに変換
    local process_icons = {
      ['pwsh'] = '\u{e70f}',      -- nf-dev-terminal_badge (PowerShell)
      ['powershell'] = '\u{e70f}',
      ['cmd'] = '\u{e629}',       -- nf-fae-windows
      ['zsh'] = '\u{e795}',       -- nf-dev-terminal
      ['bash'] = '\u{e795}',
      ['fish'] = '\u{e795}',
      ['nvim'] = '\u{e62b}',      -- nf-seti-vim
      ['vim'] = '\u{e62b}',
      ['node'] = '\u{e718}',      -- nf-dev-nodejs_small
      ['python'] = '\u{e73c}',    -- nf-dev-python
      ['git'] = '\u{e702}',       -- nf-dev-git
      ['lazygit'] = '\u{e702}',
      ['claude'] = '\u{e66f}',    -- nf-dev-code
      ['ssh'] = '\u{f489}',       -- nf-oct-terminal
      ['docker'] = '\u{e7b0}',    -- nf-dev-docker
      ['make'] = '\u{e673}',      -- nf-dev-gnu
      ['cargo'] = '\u{e7a8}',     -- nf-dev-rust
      ['go'] = '\u{e627}',        -- nf-fae-go
    }

    -- pane_titleからプロセス名を取得、tmuxの場合はforeground_process_nameにフォールバック
    local pane_title = tab.active_pane.title or ''
    local raw_name = pane_title:match('([^/\\]+)$') or pane_title
    raw_name = raw_name:gsub('%.exe$', '')

    if raw_name == 'tmux' or raw_name == '' then
      local fg = tab.active_pane.foreground_process_name or ''
      raw_name = fg:match('([^/\\]+)$') or raw_name
      raw_name = raw_name:gsub('%.exe$', '')
    end

    local icon = process_icons[raw_name] or raw_name

    local title = string.format(' %s %s ', dir_name, icon)

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
-- フォーカス変更時の透明度調整
-- Acrylic非フォーカス時の明るさ変化を軽減する
-- ========================================
function M.setup_focus_handler()
  local focused_opacity = 0.3
  local unfocused_opacity = 0.7

  wezterm.on('window-focus-changed', function(window, pane)
    local overrides = window:get_config_overrides() or {}
    if window:is_focused() then
      overrides.window_background_opacity = focused_opacity
    else
      overrides.window_background_opacity = unfocused_opacity
    end
    window:set_config_overrides(overrides)
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
