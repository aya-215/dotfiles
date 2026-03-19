#!/bin/bash
# open-diffview.sh - tmuxで新しいウィンドウを開いてNeovim DiffViewを起動する
#
# Usage: open-diffview.sh <repo_path> <host> <pr_number> [head_ref]
#   host: "github" or "gitbucket"

set -euo pipefail

export PATH="$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

REPO_PATH="${1:?リポジトリパスが必要}"
HOST="${2:?ホストが必要}"
PR_NUMBER="${3:?PR番号が必要}"
HEAD_REF="${4:-}"

TMUX_SOCKET="/tmp/tmux-$(id -u)/default"

if [[ ! -S "$TMUX_SOCKET" ]]; then
    echo "Error: tmuxソケットが見つかりません: $TMUX_SOCKET" >&2
    exit 1
fi

REPO_NAME=$(basename "$REPO_PATH")
WINDOW_NAME="${REPO_NAME}#${PR_NUMBER}"

# tmuxの新しいウィンドウでチェックアウト＋DiffView起動
tmux -S "$TMUX_SOCKET" new-window -c "$REPO_PATH" -n "$WINDOW_NAME" "
    set -euo pipefail
    export PATH=\"$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin:\$PATH\"
    cd '$REPO_PATH'

    if [[ '$HOST' == 'github' ]]; then
        # GitHubの場合: worktreeチェックまたはgh pr checkout
        if [[ -n '$HEAD_REF' ]]; then
            WT=\$(git worktree list --porcelain | grep -B2 \"^branch refs/heads/$HEAD_REF\$\" | grep '^worktree ' | sed 's/^worktree //' || true)
        else
            WT=''
        fi

        if [[ -n \"\$WT\" ]]; then
            cd \"\$WT\"
        else
            gh pr checkout '$PR_NUMBER' || { echo 'Error: gh pr checkout failed'; read -r; exit 1; }
        fi
    else
        # GitBucketの場合: pull/N/head refspecでfetch
        if [[ -n '$HEAD_REF' ]]; then
            # head_refブランチが既にあるか確認
            if git show-ref --verify --quiet \"refs/heads/pr-${PR_NUMBER}\" 2>/dev/null; then
                git checkout \"pr-${PR_NUMBER}\"
                git fetch origin \"pull/${PR_NUMBER}/head:pr-${PR_NUMBER}\" || true
            else
                git fetch origin \"pull/${PR_NUMBER}/head:pr-${PR_NUMBER}\" || {
                    # pull/N/head が公開されていない場合はhead_refブランチで試みる
                    git fetch origin '$HEAD_REF' && git checkout '$HEAD_REF' || { echo 'Error: ブランチのフェッチに失敗'; read -r; exit 1; }
                }
                git checkout \"pr-${PR_NUMBER}\"
            fi
        else
            git fetch origin \"pull/${PR_NUMBER}/head:pr-${PR_NUMBER}\" || { echo 'Error: git fetch failed'; read -r; exit 1; }
            git checkout \"pr-${PR_NUMBER}\"
        fi
    fi

    BASE=\$(git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null)
    nvim -c \":DiffviewOpen \$BASE\"
    bash --login
"
