# User CLAUDE.md

振る舞いのルールは `~/.claude/rules/`、作業ごとの手順はスキルにある。ここには環境の事実だけを書く。

## 環境

- WSL + zsh
- エディタ: Neovim
- dotfiles: Nix/Home Manager で管理。tmux.conf, .claude.json 等の設定ファイルは生成物なので直接編集しないこと。設定変更は必ず dotfiles 内の Nix ソースファイルを確認・編集すること。
- GitHub CLI: 2つのアカウント（eBASE-Mori, aya-215）で認証済み。`gh` コマンドが認証エラーで失敗した場合は `gh auth switch` でアカウントを切り替えること。
- SSH: デフォルトキーは`~/.ssh/id_ed25519_ebase`（eBASE-Mori）。aya-215用は`github-aya215`エイリアス（`~/.ssh/id_ed25519_aya215`）を使用。
- Git on /mnt/: `/mnt/` 配下のリポジトリで `index.lock` エラーが発生した場合は `git-index-lock` スキルを使うこと。
- Windows側で見たいファイル（Excel、画像、HTML等）を渡したい場合は `D:\temp_wsl`（WSLからは `/mnt/d/temp_wsl`）に置くこと。ここはWindows側で開くための受け渡し専用フォルダであり、永続保存場所ではない。最後の更新から14日で自動削除される（`scripts/temp-wsl-cleanup.sh`、cron 毎日12:30）ため、繰り返し使うWindows用スクリプト等は dotfiles の `scripts/` に置き、Windows側からは `D:\git\dotfiles\scripts\` で参照すること。
