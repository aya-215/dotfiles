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

# 3. トークンを ~/.claude/gitbucket/credentials.json に保存（ebase-infra の gitbucket-api スキルと共用）
CRED_PATH="$HOME/.claude/gitbucket/credentials.json"
ORIGIN=$(python3 -c 'import sys, urllib.parse as u; p = u.urlsplit(sys.argv[1]); print(f"{p.scheme}://{p.netloc}")' "${GITBUCKET_URL:-http://192.168.208.80:8080/gitbucket}")
if python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get(sys.argv[2]) else 1)' "$CRED_PATH" "$ORIGIN" 2>/dev/null; then
    echo ">>> $CRED_PATH に $ORIGIN のトークンがあります（スキップ）"
else
    echo ""
    echo ">>> GitBucket Personal Access Token を入力してください（画面には表示されません）"
    echo "    発行場所: GitBucket UI → Account Settings → Applications"
    echo -n "    Token: "
    read -rs token
    echo ""
    if [[ -z "$token" ]]; then
        echo "エラー: トークンが入力されていません"
        exit 1
    fi
    mkdir -p "$(dirname "$CRED_PATH")"
    # トークンは引数に載せず stdin で渡す（プロセス一覧に出さないため）
    printf '%s' "$token" | python3 -c '
import json, os, pathlib, sys
path, origin = pathlib.Path(sys.argv[1]), sys.argv[2]
try:
    creds = json.loads(path.read_text()) if path.exists() else {}
except ValueError:
    sys.exit(f"エラー: {path} が JSON として読めません。直してからやり直してください")
if not isinstance(creds, dict):
    sys.exit(f"エラー: {path} の中身がオブジェクトではありません")
creds[origin] = sys.stdin.read()
# 書き込む前から 600 にする（一瞬でも他人が読める状態にしない）
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.fchmod(fd, 0o600)
with os.fdopen(fd, "w") as f:
    f.write(json.dumps(creds, ensure_ascii=False, indent=2) + "\n")
' "$CRED_PATH" "$ORIGIN"
    echo "    $CRED_PATH に保存しました（権限 600）"
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
tools=$( (bash "$SCRIPT_DIR/smoke.sh" || true) | wc -l)
if (( tools > 0 )); then
    echo "    起動テスト: OK（ツール ${tools} 個）"
else
    echo "    起動テスト: ツール一覧が返りませんでした。bash $SCRIPT_DIR/smoke.sh を確認してください"
    exit 1
fi

echo ""
echo "=== セットアップ完了 ==="
echo ""
echo "次のステップ:"
echo "  1. Claude Code を再起動してMCPサーバーを認識させてください"
echo "  2. 「matsumoto-hisa/docs-hub のPR一覧を見せて」と話しかけてみてください"
echo ""
echo "トークンを変更したい場合:"
echo "  $CRED_PATH の \"$ORIGIN\" を書き換えてください（環境変数 GITBUCKET_TOKEN があればそちらが優先）"
