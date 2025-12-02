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
-- デフォルトシェル設定
-- ========================================
config.default_prog = { 'pwsh.exe' }
config.default_cwd = 'D:\\'

-- ========================================
-- 設定を返す
-- ========================================
return config
