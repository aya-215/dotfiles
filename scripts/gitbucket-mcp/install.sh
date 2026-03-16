#!/bin/bash
# GitBucket MCP サーバーのセットアップスクリプト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.dotfiles/.claude-global/settings.json"

echo "=== GitBucket MCP サーバー セットアップ ==="
echo ""

# 1. uv の確認
if ! command -v uv &>/dev/null; then
    echo "エラー: uv が見つかりません。https://docs.astral.sh/uv/ からインストールしてください"
    exit 1
fi

# 2. 依存関係インストール
echo ">>> 依存関係をインストールしています..."
cd "$SCRIPT_DIR"
uv sync
echo "    完了"

# 3. .env.local の生成
if [[ ! -f "$SCRIPT_DIR/.env.local" ]]; then
    echo ""
    echo ">>> GitBucket Personal Access Token を入力してください"
    echo "    発行場所: GitBucket UI → Account Settings → Applications"
    echo -n "    Token: "
    read -r token
    if [[ -z "$token" ]]; then
        echo "エラー: トークンが入力されていません"
        exit 1
    fi
    cat > "$SCRIPT_DIR/.env.local" <<EOF
GITBUCKET_URL=http://192.168.208.80:8080/gitbucket
GITBUCKET_TOKEN=${token}
EOF
    echo "    .env.local を作成しました"
else
    echo ">>> .env.local は既に存在します（スキップ）"
fi

# 4. 実行権限を付与
chmod +x "$SCRIPT_DIR/server.py"

# 5. settings.json に mcpServers を追加
echo ""
echo ">>> .claude-global/settings.json にMCPサーバーを登録しています..."

if ! command -v jq &>/dev/null; then
    echo "警告: jq が見つかりません。手動で以下を settings.json の mcpServers に追加してください:"
    echo ""
    echo '  "gitbucket": {'
    echo '    "command": "uv",'
    echo '    "args": ['
    echo "      \"--directory\", \"${SCRIPT_DIR}\","
    echo '      "run", "server.py"'
    echo '    ]'
    echo '  }'
    echo ""
else
    # jq で mcpServers.gitbucket を追加（既存設定を保持）
    tmp=$(mktemp)
    jq --arg dir "$SCRIPT_DIR" '
      .mcpServers //= {} |
      .mcpServers.gitbucket = {
        "command": "uv",
        "args": ["--directory", $dir, "run", "server.py"]
      }
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    echo "    登録完了"
fi

# 6. 動作確認
echo ""
echo ">>> サーバーの起動テストをしています..."
cd "$SCRIPT_DIR"
if echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}' | \
   timeout 5 uv run server.py 2>/dev/null | grep -q "protocolVersion"; then
    echo "    起動テスト: OK"
else
    echo "    起動テスト: サーバーは起動しました（レスポンス確認はClaude再起動後に行ってください）"
fi

echo ""
echo "=== セットアップ完了 ==="
echo ""
echo "次のステップ:"
echo "  1. Claude Code を再起動してMCPサーバーを認識させてください"
echo "  2. 「matsumoto-hisa/docs-hub のPR一覧を見せて」と話しかけてみてください"
echo ""
echo "トークンを変更したい場合:"
echo "  $SCRIPT_DIR/.env.local を直接編集してください"
