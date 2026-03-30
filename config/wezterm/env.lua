-- ========================================
-- 環境変数ローダー
-- ========================================
--
-- .env ファイルから環境変数を読み込むユーティリティ
--
-- ========================================

local wezterm = require 'wezterm'

local M = {}

--- .envファイルから環境変数を読み込む
--- @param filepath string .envファイルのパス
--- @return table 環境変数のテーブル
function M.load_env_file(filepath)
  local env = {}
  local file = io.open(filepath, "r")

  if not file then
    wezterm.log_warn("Could not open .env file: " .. filepath)
    return env
  end

  for line in file:lines() do
    -- コメント行と空行をスキップ
    if not line:match("^%s*#") and not line:match("^%s*$") then
      -- KEY=VALUE 形式をパース
      local key, value = line:match("^%s*([^=]+)%s*=%s*(.+)%s*$")
      if key and value then
        -- 前後の空白を削除
        key = key:gsub("^%s*(.-)%s*$", "%1")
        value = value:gsub("^%s*(.-)%s*$", "%1")
        -- クォートを削除（もしあれば）
        value = value:gsub("^['\"](.+)['\"]$", "%1")
        env[key] = value
      end
    end
  end

  file:close()
  return env
end

--- 環境変数を読み込み、デフォルト値を返す
--- @param env_table table 環境変数テーブル
--- @param key string 環境変数のキー
--- @param default any デフォルト値
--- @return any 環境変数の値またはデフォルト値
function M.get_env(env_table, key, default)
  return env_table[key] or default
end

return M
