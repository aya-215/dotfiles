# lualine.nvim

高速でカスタマイズしやすい Neovim 用ステータスラインプラグイン。

設定ファイル: `config/nvim/lua/plugins/lualine.lua`

---

## クイックリファレンス

| コマンド / API | 説明 |
|---|---|
| `:LualineBuffersJump {番号}` | バッファジャンプ（buffers コンポーネント使用時） |
| `:LualineRenameTab {名前}` | タブ名変更（tabs コンポーネント使用時） |
| `require('lualine').refresh()` | ステータスラインを手動リフレッシュ |
| `require('lualine').hide()` | ステータスラインを非表示 |

---

## 詳細

### ステータスラインのセクション構成

```
[ A | B | C          X | Y | Z ]
```

| セクション | 位置 | 現在の設定 |
|---|---|---|
| `lualine_a` | 左端 | `mode`（ノーマル/インサート等） |
| `lualine_b` | 左 | `branch`, `diff`, `diagnostics` |
| `lualine_c` | 左中 | `filename`（相対パス表示） |
| `lualine_x` | 右中 | `encoding`, `fileformat`, `filetype` |
| `lualine_y` | 右 | `progress`（ファイル内の進捗 %） |
| `lualine_z` | 右端 | `location`（行:列） |

### 主要コンポーネント

| コンポーネント | 説明 |
|---|---|
| `mode` | 現在のモード（NORMAL / INSERT 等） |
| `branch` | Git ブランチ名 |
| `diff` | Git 差分（追加/変更/削除行数） |
| `diagnostics` | LSP 診断数（エラー/警告/情報/ヒント） |
| `filename` | ファイル名（path で相対/絶対パス切替） |
| `encoding` | ファイルエンコーディング |
| `fileformat` | 改行コード（unix/dos/mac） |
| `filetype` | ファイルタイプ |
| `progress` | ファイル内カーソル位置（%） |
| `location` | 行番号:列番号 |
| `searchcount` | 検索マッチ数 |
| `lsp_status` | LSP サーバー状態 |

### 現在の設定ポイント

- `theme = "auto"` — カラースキームに自動追従
- `globalstatus = false` — ウィンドウごとに個別ステータスライン
- セパレータは `` と `` を使用（Nerd Font 必須）
- 非表示対象 filetype: `dashboard`, `alpha`, `starter`
- 拡張機能: `nvim-tree`, `quickfix`, `fugitive`, `oil`
- `filename.path = 1` — 相対パス表示
- `filename.symbols` — `[+]` 変更, `[-]` 読み取り専用, `[No Name]` 無名バッファ

### 拡張機能（extensions）

lualine は各プラグイン向けに最適化された拡張機能を内蔵している。

| 拡張機能 | 対応プラグイン |
|---|---|
| `nvim-tree` | ファイルツリー表示時にステータスを変更 |
| `quickfix` | quickfix/location list 用表示 |
| `fugitive` | Git 操作ウィンドウ用表示 |
| `oil` | ファイラー用表示 |
| その他 | lazy, mason, trouble, toggleterm 等 |

---

## 注意事項

- Nerd Font が必要（セパレータ文字 ``, `` を使用）
- `globalstatus = true` にすると Neovim 0.7+ でウィンドウ全体で1本のステータスラインになる
