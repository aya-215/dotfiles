# プロジェクト固有の指示

## フォルダ構造

```
dotfiles/
├── .claude/                 # Claude Code設定
├── .config/                 # 各種設定ファイル
│   ├── nvim/               # Neovim設定
│   │   ├── after/          # ftplugin, syntax
│   │   ├── lua/            # Lua設定
│   │   │   ├── config/    # 設定ファイル
│   │   │   └── plugins/   # プラグイン設定
│   │   └── tools/          # 補助ツール
│   └── wezterm/            # WezTerm設定
├── AutoHotkey/             # AutoHotkey設定
├── PowerShell/             # PowerShell設定
│   ├── Modules/           # PowerShellモジュール
│   │   ├── BurntToast/   # 通知モジュール
│   │   ├── PSFzf/        # Fzf統合
│   │   └── ZLocation/    # ディレクトリジャンプ
│   └── Scripts/           # PowerShellスクリプト
├── scripts/               # 各種スクリプト
└── README.md             # プロジェクトドキュメント
```

## dotfiles管理の仕組み

このリポジトリはWSLとWindowsで役割が分かれとる：

| 環境 | ツール | 対象ファイル |
|---|---|---|
| WSL (Linux) | Nix / Home Manager | `modules/*.nix`, `flake.nix` |
| Windows | chezmoi | `chezmoi/` 配下 |

### WSL（Nix管理）

- 設定変更は `modules/*.nix` や `flake.nix` を編集する
- 反映するには `home-manager switch --flake .` を実行する
- `chezmoi` コマンドはWSLでは**使わない**

### Windows（chezmoi管理）

- 設定変更は `chezmoi/` 配下のファイルを編集する
- 反映するには `chezmoi apply` を実行する（Windowsで）

### Neovim設定（特殊）

- `chezmoi/.chezmoitemplates/nvim/` がソースファイル
- Home Managerが `~/.config/nvim` → `.dotfiles/chezmoi/.chezmoitemplates/nvim/` のシンボリックリンクを作成
- そのため **nvimの設定変更はシンボリックリンク経由で即座に反映**される（home-manager switch不要）

## Git操作

### コミット後の動作
- コミット作業が完了したら、必ず `git push` でリモートリポジトリにプッシュすること
- 複数の変更をまとめてコミットする場合は、すべてのコミットが完了した最後にプッシュすること

### コミットメッセージスタイル
このリポジトリでは以下のプレフィックスを使用：
- `feat:` - 新機能追加
- `refactor:` - リファクタリング
- `docs:` - ドキュメント更新
- `fix:` - バグ修正
