-- ========================================
-- WezTerm メイン設定ファイル
-- ========================================
--
-- 設定は以下のモジュールに分割されています:
--   - performance.lua: パフォーマンス設定
--   - appearance.lua:  外観設定
--   - keys.lua:        キーバインディング設定
--
-- ========================================

local wezterm = require 'wezterm'

-- モジュールの読み込み
local performance = require 'performance'
local appearance = require 'appearance'
local keys = require 'keys'
local env_loader = require 'env'

-- 設定オブジェクトの作成
local config = wezterm.config_builder()

-- ========================================
-- 各モジュールの設定を適用
-- ========================================

-- パフォーマンス設定
performance.setup(config)

-- 外観設定
appearance.setup(config)

-- タブタイトルのカスタマイズ
appearance.setup_tab_title()

-- 起動時動作（ウィンドウ最大化）
appearance.setup_startup()

-- キーバインディング設定
keys.setup(config)

-- ========================================
-- 環境変数の読み込み
-- ========================================
local config_dir = wezterm.config_dir
local env_file = config_dir .. '\\.env'
local env = env_loader.load_env_file(env_file)

-- ========================================
-- 環境変数設定
-- ========================================
config.set_environment_variables = {
  FORCE_COLOR = "1",
  COLORTERM = "truecolor",
  FZF_DEFAULT_OPTS = "--height 40% --reverse --border --margin=1 --padding=1",
}

-- ========================================
-- デフォルトシェル設定
-- ========================================
-- localドメインのデフォルトシェル（Ctrl+Shift+T対策）
config.default_prog = { 'pwsh.exe', '-NoLogo' }

-- WSLをデフォルトに設定（シェル統合とディレクトリ追跡を有効化）
config.default_domain = 'WSL:Ubuntu-22.04'

-- WSLドメインのカスタマイズ
config.wsl_domains = {
  {
    name = 'WSL:Ubuntu-22.04',
    distribution = 'Ubuntu-22.04',
    default_cwd = '~',
  },
}

-- 複数のシェル環境を選択可能にする
config.launch_menu = {
  {
    label = 'PowerShell 7',
    args = { 'pwsh.exe', '-NoLogo' },
    domain = { DomainName = 'local' },
    cwd = 'D:\\',
  },
  {
    label = 'WSL Ubuntu',
    domain = { DomainName = 'WSL:Ubuntu-22.04' },
  },
}

-- ワークスペースタイプに応じて起動ディレクトリを設定
local workspace_type = env_loader.get_env(env, 'WORKSPACE_TYPE', 'home')
local start_dir = env_loader.get_env(env, 'START_DIR', nil)

if start_dir then
  -- START_DIR が明示的に指定されている場合はそれを使用
  config.default_cwd = start_dir
elseif workspace_type == 'work' then
  -- 会社PC: D:\ で起動
  config.default_cwd = 'D:\\'
else
  -- 自宅PC: ホームディレクトリで起動
  config.default_cwd = wezterm.home_dir
end

-- ========================================
-- 設定を返す
-- ========================================
return config
