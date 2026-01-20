# Neovim設定スタイルガイド

## ファイル構成
```
.config/nvim/
├── init.lua           # エントリーポイント(最小限)
├── lua/
│   ├── config/        # コア設定
│   │   ├── options.lua
│   │   ├── keymaps.lua
│   │   └── autocmds.lua
│   └── plugins/       # プラグイン設定(1ファイル1プラグイン)
└── lazy-lock.json     # プラグインロック
```

## コーディング規約
- インデント: 2スペース
- 文字列: シングルクォート優先
- vim.keymap.set使用(vim.api.nvim_set_keymapではなく)
- 条件分岐は早期リターン
