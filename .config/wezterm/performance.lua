-- ========================================
-- パフォーマンス設定（Performance Configuration）
-- ========================================

local M = {}

function M.setup(config)
  -- ========================================
  -- グラフィックスAPI設定
  -- ========================================
  -- Windows推奨順: WebGpu > Dx12 > Vulkan > OpenGL
  config.front_end = "WebGpu"
  config.webgpu_power_preference = "HighPerformance"

  -- ========================================
  -- アニメーション設定
  -- ========================================
  -- スムーズなアニメーション
  config.animation_fps = 60

  -- 高リフレッシュレートディスプレイ対応
  config.max_fps = 120

  -- ========================================
  -- 更新確認設定
  -- ========================================
  -- 自動更新確認（必要に応じて無効化）
  config.check_for_updates = true

  -- ========================================
  -- その他のパフォーマンス設定
  -- ========================================
  -- 設定の自動リロード
  config.automatically_reload_config = true

  -- IME設定（日本語入力）
  config.use_ime = true
end

return M
