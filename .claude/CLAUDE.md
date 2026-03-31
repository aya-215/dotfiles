# プロジェクト固有の指示

## フォルダ構造

```
dotfiles/
├── nvim -> config/nvim/    # Neovim設定（ショートカット）
├── config/                 # 手書き設定ファイルをすべてここに集約
│   ├── nvim/               # Neovim設定
│   │   ├── after/          # ftplugin, syntax
│   │   ├── lua/            # Lua設定
│   │   │   ├── config/    # 設定ファイル
│   │   │   └── plugins/   # プラグイン設定
│   │   └── tools/          # 補助ツール
│   ├── wezterm/            # WezTerm設定
│   ├── starship/           # Starshipプロンプト
│   ├── lazygit/            # LazyGit
│   ├── yazi/               # Yaziファイラー
│   ├── zeno/               # Zenoスニペット
│   ├── zsh/                # Zshカスタム関数
│   ├── nb/                 # nbノート管理
│   └── gh-dash/            # GitHub Dashboard
├── modules/               # Nixモジュール（WSL/Nix管理）
├── windows/               # Windows専用設定（chezmoi管理）
│   ├── Documents/PowerShell/  # PowerShell設定
│   ├── AutoHotkey/            # AutoHotkey設定
│   └── dot_config/            # その他Windows設定
├── scripts/               # 各種スクリプト
└── README.md             # プロジェクトドキュメント
```

## dotfiles管理の仕組み

このリポジトリはWSLとWindowsで役割が分かれとる：

| 環境 | ツール | 対象ファイル |
|---|---|---|
| WSL (Linux) | Nix / Home Manager | `modules/*.nix`, `flake.nix` |
| Windows | chezmoi | `windows/` 配下 |

### WSL（Nix管理）

- 設定変更は `modules/*.nix` や `flake.nix` を編集する
- 反映するには `home-manager switch --flake .` を実行する
- `chezmoi` コマンドはWSLでは**使わない**

### Windows（chezmoi管理）

- 設定変更は `windows/` 配下のファイルを編集する
- 反映するには `chezmoi apply --source .\windows` を実行する（Windowsで）

### Neovim設定

- `config/nvim/` がソースファイル（WSL/Windows共通）
- Home Managerが `~/.config/nvim` → `.dotfiles/config/nvim/` のシンボリックリンクを作成
- **nvimの設定変更はシンボリックリンク経由で即座に反映**される（home-manager switch不要）
- リポジトリルートの `nvim` → `config/nvim/` のショートカットでも直接アクセス可能

### WezTerm設定

- `config/wezterm/` がソースファイル（WSL/Windows共通）
- chezmoiテンプレート変数は使わずLuaのランタイムチェックで環境差異を吸収している

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
