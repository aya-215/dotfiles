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
