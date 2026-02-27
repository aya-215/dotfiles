# User CLAUDE.md

## 環境

- WSL + zsh
- エディタ: Neovim
- dotfiles: Nix/Home Manager で管理。tmux.conf, .claude.json 等の設定ファイルは生成物なので直接編集しないこと。設定変更は必ず dotfiles 内の Nix ソースファイルを確認・編集すること。
- GitHub CLI: 2つのアカウント（eBASE-Mori, aya-215）で認証済み。`gh` コマンドが認証エラーで失敗した場合は `gh auth switch` でアカウントを切り替えること。
- SSH: デフォルトキーは`~/.ssh/id_ed25519_ebase`（eBASE-Mori）。aya-215用は`github-aya215`エイリアス（`~/.ssh/id_ed25519_aya215`）を使用。dotfilesリポジトリのremoteは`git@github-aya215:aya-215/dotfiles.git`に設定すること。push失敗時は`git remote set-url origin git@github-aya215:aya-215/dotfiles.git`で修正すること。

## コミュニケーションルール

不明点がある場合は、解消されるまで `AskUserQuestion` で再帰的に質問すること。

## Memory 管理ルール

記憶・メモリに関連する操作は **必ず `agent-memory` スキルを使用する**。

### プロアクティブ使用

以下の場面では、ユーザーの指示がなくても agent-memory への保存を検討すること：

- 調査に時間がかかった発見
- 非自明なバグや回避策
- 難しい問題の解決策
- アーキテクチャ決定とその理由
- 中断する可能性のある進行中の作業

関連作業を開始するときは、既存のメモリを確認すること。
