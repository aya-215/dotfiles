# dotfiles

個人用 dotfiles 管理リポジトリ。WSL/Linux は **Nix Flakes + Home Manager**、Windows は **chezmoi** で宣言的に管理する。

このREADMEは入口です。詳細は各章のリンク先か、設定のソースファイルを参照してください。

## 構成

```
dotfiles/
├── flake.nix              # Nix Flake（エントリーポイント）
├── home.nix               # Home Manager メイン設定。modules/ を import する
├── nvim -> config/nvim/    # Neovim設定へのショートカット
├── modules/               # 機能別Nixモジュール（パッケージ・zsh・tmux・neovim 等）
├── config/                # 手書き設定ファイル（nvim, wezterm, starship, lazygit,
│                          #   yazi, zeno, nb, zsh, gh-dash）
├── windows/               # Windows専用設定（chezmoi管理）
│   ├── Documents/PowerShell/   # PowerShell profile・モジュール
│   ├── AutoHotkey/             # AutoHotkey設定（.tmpl・テンプレート変数あり）
│   ├── dot_claude/             # Claude Code設定（Windows用）
│   └── dot_config/             # その他Windows設定
├── bootstrap/             # Windows初回セットアップ（chezmoi経路）
├── scripts/               # 自動化サブシステム群（→「サブシステム」章）
├── docs/                  # ドキュメント（→「ドキュメント」章）
├── .claude/               # Claude Code プロジェクト設定
└── .claude-global/        # Claude Code グローバルルール・スキル
```

`modules/` と `config/` の中身は個別に列挙しない。`ls modules/` で確認できるほうが確実です。

## セットアップ

### WSL / Linux（Nix + Home Manager）

```bash
# 1. Nix をインストール（マルチユーザーモード）
sh <(curl -L https://nixos.org/nix/install) --daemon
exec $SHELL

# 2. Flakes を有効化
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf

# 3. clone
git clone git@github-aya215:aya-215/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 4. 環境を構築（初回）
nix run home-manager/master -- switch --flake .
```

インストールされるものは `modules/packages.nix` を参照。

`flake.nix` は nixpkgs（nixos-unstable）と home-manager のほか、外部flakeとして
`glauncher`（`git+ssh://git@github-aya215/aya-215/glauncher`）を参照する。

### Windows（chezmoi）

**前提**: Windows 11 + PowerShell 7+（pwsh）、winget、SSHキー（`github-aya215` エイリアス）設定済み。

Windows 側は WSL 側とは別に clone する（WSL の `~/.dotfiles` を参照するのではなく、
Windows のファイルシステム上に独立した clone を置く）。

```powershell
# 1. clone（配置先は任意）
git clone git@github-aya215:aya-215/dotfiles.git <clone先>
cd <clone先>

# 2. 依存ツールとフォントを導入（初回のみ）
pwsh -File .\scripts\setup\install-dependencies.ps1
pwsh -File .\scripts\setup\install-fonts.ps1      # HackGen Nerd Font

# 3. 設定を適用（chezmoi導入・XDG_CONFIG_HOME設定・chezmoi apply までを行う）
pwsh -ExecutionPolicy Bypass -File .\bootstrap\install.ps1
```

WSL 側で設定を変更した場合、Windows アプリに反映するには Windows 側の clone で `git pull` が必要。
chezmoi 管理の `windows/` を変更した場合は加えて `chezmoi apply --source .\windows` を実行する。

#### 管理対象ファイル

| ファイル | ソース | 配置先 |
|---|---|---|
| PowerShell profile | `windows/Documents/PowerShell/` | `%USERPROFILE%\Documents\PowerShell\` |
| AutoHotkey | `windows/AutoHotkey/` | `%USERPROFILE%\AutoHotkey\` |
| WezTerm | `config/wezterm/`（WSL共通） | `%USERPROFILE%\.config\wezterm\` |
| Neovim | `config/nvim/`（WSL共通） | `%USERPROFILE%\.config\nvim\` |

WezTerm と Neovim は chezmoi 管理外で WSL/Windows 共通。chezmoi テンプレート変数を使わず、
Lua のランタイムチェックで環境差異を吸収しているため `git pull` だけで反映される。

AutoHotkey は `{{ .hasDriveD }}` 等のテンプレート変数を含むため `chezmoi apply` での展開が必須。
変更時は `run_onchange_install-autohotkey.ps1.tmpl` が連動発火し、Startup のシンボリックリンクを更新する。

## 日常運用

```bash
cd ~/.dotfiles

# 設定を編集（Nixモジュール or config/ 配下）
nvim modules/zsh.nix

# 変更を適用
home-manager switch --flake .

# コミットして push
git add -p && git commit && git push
```

**Neovim と WezTerm の設定はシンボリックリンク経由のため `home-manager switch` 不要**（保存で即反映）。
`modules/*.nix` や `flake.nix` を触った場合は switch が必要。

パッケージを追加する場合は `modules/packages.nix` に追記して switch する。

## サブシステム

`scripts/` 配下の自動化群。多くは Claude Code の hook や cron から自動起動する。

| サブシステム | 役割 | 詳細 |
|---|---|---|
| `claude-summarize/` | Claude Code の SessionEnd hook でセッションを Haiku で6項目要約し `~/.nb/claude/sessions/` に保存。`backfill.sh` で取りこぼしを回収。テストあり | [設計](docs/superpowers/specs/2026-06-09-claude-session-summary-design.md) / [frontmatter決定化](docs/superpowers/plans/2026-07-13-summarize-deterministic-frontmatter.md) / [backfill](docs/superpowers/specs/2026-07-24-session-summary-backfill-design.md) |
| `claude-pane-session/` | tmux 復元時に claude ペインを元の会話へ復元する。SessionStart hook でペイン座標と session_id を記録 | [設計](docs/tmux-claude-session-restore.md) |
| `daily-review/` | cron（22:10）で日報を無人生成。claude バイナリを使わずルーティンの `/fire` に POST する（SDKクレジット消費なし） | [設計](docs/superpowers/specs/2026-06-10-claude-p-migration-design.md) |
| `lib/` | 共通ライブラリ。`rocketchat.sh`（Rocket Chat の購読ルームから関連メッセージを収集）、`redact.sh`（シークレット redaction、要約書き出しと送信前の二重ガード）。両方テストあり | [複数ルーム対応](docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md) / [スレッド探索](docs/superpowers/specs/2026-07-29-rocketchat-thread-discovery-design.md) |
| `pr-diffview/` | PR の差分を Neovim DiffView で開く。Tampermonkey スクリプトがローカルサーバ（`server.py`）を叩き、`open-diffview.sh` が tmux の新ウィンドウで Neovim を起動する。GitHub と社内 GitBucket の両方に対応 | — |
| `gitbucket-mcp/` | 社内 GitBucket を Claude から操作する MCP サーバー（Python / uv 管理）。PR・Issue の取得、コメント投稿、ブランチ一覧などを提供する | — |
| `setup/` | Windows の依存ツール・フォント導入（→「セットアップ」章） | — |

単発スクリプト: `cleanup-wsl.sh`（キャッシュ・ログ・Nix store のクリーンアップ、`--dry-run` 対応）、
`nb-sync.sh`（nb リポジトリを GitHub と同期）。

## ツール構成

Nix/Home Manager が導入するものは `modules/packages.nix` が唯一の定義。
おおまかには CLI ツール（ripgrep, fd, fzf, bat, eza, jq, lazygit, yazi, zoxide, nb, delta, ghq, gh, gcalcli, sshfs）、
ランタイム（fnm, deno, bun, python3）、Nix 開発ツール（nixpkgs-fmt, statix, nil）が入る。

シェル・エディタ周りの設定は以下がソース。READMEに一覧を写すとズレるため、直接参照してください。

| 対象 | ソース | ドキュメント |
|---|---|---|
| zsh（エイリアス・fzf関数・プラグイン） | `modules/zsh.nix`, `config/zsh/` | — |
| zeno（スニペット・補完） | `config/zeno/config.yml` | — |
| Neovim | `config/nvim/` | [README](config/nvim/README.md) / [キーマップ](docs/nvim-keymaps.md) / [プラグイン](docs/nvim-plugins/) |
| tmux | `modules/tmux.nix` | [ガイド](docs/tmux-guide.md) |
| lazygit | `config/lazygit/` | — |
| starship | `config/starship/starship.toml` | — |
| nb（ノート・タスク管理） | `modules/nb.nix`, `config/nb/` | [コマンド](docs/nb-commands.md) / [使い方](docs/nb-usage.md) |
| PowerShell（Windows） | `windows/Documents/PowerShell/` | — |

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/nix-guide/](docs/nix-guide/) | Nix 学習ガイド |
| [docs/nvim-plugins/](docs/nvim-plugins/) | Neovim プラグイン別チートシート |
| [docs/nvim-keymaps.md](docs/nvim-keymaps.md) | Neovim キーマップ一覧 |
| [docs/tmux-guide.md](docs/tmux-guide.md) | tmux ガイド |
| [docs/nb-commands.md](docs/nb-commands.md) / [docs/nb-usage.md](docs/nb-usage.md) | nb リファレンス・使い方 |
| [docs/life-management.md](docs/life-management.md) / [クイックスタート](docs/life-management-quickstart.md) | GitHub を使った人生管理 |
| [docs/superpowers/](docs/superpowers/) | 各機能の設計書（`specs/`）と実装計画（`plans/`） |

上記以外に調査メモ・引き継ぎメモ・作業計画が `docs/` 直下にあるが、一時的なものなのでここには挙げない。

## トラブルシューティング

### Home Manager の更新

```bash
nix flake update
home-manager switch --flake .
```

定期更新は `/nix-update` スキルを使う。

### 設定の初期化

```bash
rm -rf ~/.config/nvim ~/.config/lazygit ~/.config/starship.toml
home-manager switch --flake .
```

### Nix ストアのクリーンアップ

```bash
nix-collect-garbage -d                      # 古い世代を削除
nix-collect-garbage --delete-older-than 30d # 30日より古いものだけ削除
```

### hunk が起動しない

`hunk` は nixpkgs 版がこの WSL 環境で SIGSEGV するため、`modules/hunk.nix` で
`buildNpmPackage` + bun wrapper 版を導入している。`pkgs.hunk` に戻すとクラッシュする。
理由は `modules/hunk.nix` の冒頭コメントに記載。

## 注意事項

- 手書き設定は `config/` に集約されている（nvim/wezterm/starship 等すべて）
- Home Manager が `~/.config/` 配下のシンボリックリンクを自動管理する
- WezTerm・Neovim 設定は WSL/Windows 共通で chezmoi 管理外
- Windows 側の chezmoi source directory は `windows/`（`chezmoi` ではない）
- Windows では `XDG_CONFIG_HOME` の設定が必須（`bootstrap/install.ps1` が自動設定する）
- `.claude/settings.local.json` は `.gitignore` で除外

## 参考資料

- [Nix公式ドキュメント](https://nixos.org/manual/nix/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
