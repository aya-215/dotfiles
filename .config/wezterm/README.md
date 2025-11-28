# WezTerm 設定ファイル

この設定は、モジュール化されたベストプラクティスに従った構成になっています。

## ディレクトリ構造

```
C:\Users\368\.config\wezterm\
├── wezterm.lua          # メイン設定ファイル（モジュールを統合）
├── performance.lua      # パフォーマンス設定
├── appearance.lua       # 外観設定（タブ、フォント、色など）
├── keys.lua            # キーバインディング設定
├── wezterm.lua.backup  # バックアップファイル
└── README.md           # このファイル
```

## モジュールの説明

### `wezterm.lua`（メイン設定）
- 各モジュールを読み込み、統合するエントリーポイント
- デフォルトシェル（PowerShell）の設定

### `performance.lua`
- グラフィックスAPI設定（WebGpu、高性能モード）
- アニメーションFPS（60fps）
- 最大FPS（120fps）
- 自動リロード設定
- IME設定

### `appearance.lua`
- **ウィンドウ設定**
  - 透明度: 0.85（ユーザー指定）
  - ウィンドウパディング: 8px
  - ウィンドウ装飾: RESIZE（タイトルバー非表示）

- **フォント設定**
  - フォントサイズ: 10.5（ユーザー指定により維持）
  - フォント: HackGen Console NF（フォールバック対応）
  - 行間: 1.2

- **カーソル設定**
  - スタイル: BlinkingBlock（点滅ブロック）
  - 点滅速度: 500ms

- **カラースキーム**
  - catppuccin-mocha（ダークテーマ）
  - タブバー: 青系カスタムカラー

- **タブバー設定**
  - PowerLine風の矢印デザイン
  - カレントディレクトリ表示
  - 1つのタブの場合は非表示

- **その他**
  - スクロールバック: 10000行
  - スクロールバー: 有効
  - ビジュアルベル: 有効（音は無効）

### `keys.lua`
- **タブ操作**
  - `Ctrl+Shift+T`: 新規タブ
  - `Ctrl+Shift+W`: タブを閉じる
  - `Ctrl+Tab`: 次のタブへ移動
  - `Ctrl+Shift+Tab`: 前のタブへ移動
  - `Alt+1~9`: タブ1~9へ直接移動

- **ペイン操作**
  - `Ctrl+Shift+|`: 水平分割
  - `Ctrl+Shift+_`: 垂直分割
  - `Ctrl+Shift+矢印`: ペイン間移動
  - `Ctrl+Alt+矢印`: ペインサイズ調整
  - `Ctrl+Shift+X`: ペインを閉じる

- **フォントサイズ**
  - `Ctrl++`: フォントサイズ拡大
  - `Ctrl+-`: フォントサイズ縮小
  - `Ctrl+0`: フォントサイズリセット

- **その他**
  - `Ctrl+Shift+C`: コピー
  - `Ctrl+Shift+V`: ペースト
  - `Ctrl+Shift+F`: 検索
  - `Ctrl+Shift+R`: 設定リロード
  - `Shift+PageUp/Down`: スクロール

- **マウス操作**
  - `Ctrl+クリック`: URLを開く
  - `右クリック`: ペースト

## 設定の変更方法

### 設定ファイルの編集
各モジュールを個別に編集できます：

```powershell
# 外観設定を変更
nvim C:\Users\368\.config\wezterm\appearance.lua

# キーバインディングを変更
nvim C:\Users\368\.config\wezterm\keys.lua

# パフォーマンス設定を変更
nvim C:\Users\368\.config\wezterm\performance.lua
```

### 設定の反映
設定は自動的にリロードされますが、手動でリロードする場合：
- `Ctrl+Shift+R` を押す
- WeZTermを再起動する

## バックアップからの復元

元の設定に戻す場合：

```powershell
cp C:\Users\368\.config\wezterm\wezterm.lua.backup C:\Users\368\.config\wezterm\wezterm.lua
```

## カスタマイズ例

### 透明度を変更
`appearance.lua`の以下の行を編集：
```lua
config.window_background_opacity = 0.85  -- 0.0（完全透明）～ 1.0（不透明）
```

### フォントサイズを変更
`appearance.lua`の以下の行を編集：
```lua
config.font_size = 10.5  -- お好みのサイズに変更
```

### カラースキームを変更
`appearance.lua`の以下の行を編集：
```lua
config.color_scheme = "catppuccin-mocha"  -- 他のスキーム名に変更
```

利用可能なカラースキームを確認：
```powershell
wezterm ls-fonts --list-schemes
```

### キーバインディングを追加
`keys.lua`の`config.keys`配列に新しいエントリを追加：
```lua
{
  key = 'n',
  mods = 'CTRL|SHIFT',
  action = wezterm.action.SpawnWindow
},
```

## トラブルシューティング

### 設定エラーが発生した場合
WeZTermは設定エラーを表示し、デフォルト設定にフォールバックします。

エラーログを確認：
```powershell
# WeZTermのログを確認
wezterm start --always-show-tab-bar
```

### モジュールが読み込めない場合
モジュールファイル（`performance.lua`、`appearance.lua`、`keys.lua`）が同じディレクトリにあることを確認してください。

## 参考資料

- [WezTerm公式ドキュメント](https://wezterm.org/)
- [設定オプション一覧](https://wezterm.org/config/lua/config/index.html)
- [デフォルトキーバインド](https://wezterm.org/config/default-keys.html)
- [カラースキーム](https://wezterm.org/colorschemes/index.html)

## 変更履歴

- **2025-11-27**: モジュール化された設定に移行
  - `performance.lua`, `appearance.lua`, `keys.lua`を分離
  - 透明度を0.85に設定
  - フォントサイズ10.5を維持
  - 推奨設定を適用（スクロールバック10000行、キーバインディングなど）
