# 大西配列対応：ペイン/ウィンドウ移動キーの矢印両対応 設計

## 背景・課題

QWERTYと大西配列（Vialの`TO(1)`で切替）を併用している。vim/tmux/WezTermのナビゲーション
バインドは `hjkl`（文字ベース）で組まれているため、大西配列では `hjkl` の物理位置から
`ktns` が出てしまい、ペイン移動・ウィンドウ移動が破綻する。

特に **`Alt + hjkl`（ペイン移動）を多用**しているため対応必須。

## 方針

**両対応（hjkl と 矢印の両方をバインド）**を採用する。

- QWERTY時：従来どおり `Alt+hjkl` で移動
- 大西配列時：キーボードのレイヤー矢印（`LT2`/`LT3` ホールド＋右手hjkl位置＝矢印）で
  `Alt+矢印` を出し、それを各層が受ける
- 既存の `hjkl` バインドは消さず残す（QWERTYでもそのまま使える）

採用根拠（deep-research調査）：大西配列ユーザー fools_gold の「キーボードレイヤーに矢印を置く」
方式が実績・相性ともに最良。vim内リマップ派（umen）は3週間で挫折。リマップ回避がColemak/Dvorak
経験者の主流推奨でもある。

## アーキテクチャ：ペイン移動は3層連動

```
WezTerm(keys.lua) → tmux(tmux.nix) → Neovim(smart-splits.lua)
```

- **WezTerm** `Alt+h` 押下 → その方向にWezTermペインがあれば内部移動、なければ
  `SendKey{Alt+h}` で中身(tmux/nvim)へ委譲（`smart_pane_navigate`）
- **tmux** `M-h` 受信 → `@pane-is-vim` が真ならnvimへ`send-keys`、偽なら`select-pane`
- **Neovim** `<M-h>` 受信 → smart-splits の `move_cursor_left`

この連鎖は全て**文字h/j/k/l**で繋がっている。よって3層すべてに
「`Alt+矢印` も同じ動作にバインドする」口を増やす必要がある。

## 変更対象（フル対応：3層＋AHK）

### 1. WezTerm `config/wezterm/keys.lua`

現状（189-195行）の `Alt+hjkl` 4バインドに加え、`Alt+矢印` 4バインドを追加。
`smart_pane_navigate(direction, key)` の第2引数 `key` は委譲時に `SendKey{key, ALT}` で
送られるため、矢印版では `key` に矢印キー名（`LeftArrow`等）を渡す。

```lua
-- 既存（残す）
{ key = 'h', mods = 'ALT', action = smart_pane_navigate('Left', 'h') },
{ key = 'j', mods = 'ALT', action = smart_pane_navigate('Down', 'j') },
{ key = 'k', mods = 'ALT', action = smart_pane_navigate('Up', 'k') },
{ key = 'l', mods = 'ALT', action = smart_pane_navigate('Right', 'l') },
-- 追加（矢印両対応）
{ key = 'LeftArrow',  mods = 'ALT', action = smart_pane_navigate('Left', 'LeftArrow') },
{ key = 'DownArrow',  mods = 'ALT', action = smart_pane_navigate('Down', 'DownArrow') },
{ key = 'UpArrow',    mods = 'ALT', action = smart_pane_navigate('Up', 'UpArrow') },
{ key = 'RightArrow', mods = 'ALT', action = smart_pane_navigate('Right', 'RightArrow') },
```

### 2. tmux `modules/tmux.nix`

現状（110-113行）の `Alt+hjkl` に加え、`Alt+矢印` のバインドを追加。
委譲先のnvimへ送るキーも矢印（`M-Up`等）にする。

```
# 既存（残す）
bind-key -n M-h if-shell -F "#{@pane-is-vim}" 'send-keys M-h' 'select-pane -L'
... (j/k/l同様)
# 追加（矢印両対応）
bind-key -n M-Up    if-shell -F "#{@pane-is-vim}" 'send-keys M-Up'    'select-pane -U'
bind-key -n M-Down  if-shell -F "#{@pane-is-vim}" 'send-keys M-Down'  'select-pane -D'
bind-key -n M-Left  if-shell -F "#{@pane-is-vim}" 'send-keys M-Left'  'select-pane -L'
bind-key -n M-Right if-shell -F "#{@pane-is-vim}" 'send-keys M-Right' 'select-pane -R'
```

ウィンドウ/セッション移動（116-119行の`prefix + hjkl`）にも矢印を追加する。

```
# 既存（残す）
bind-key h previous-window
bind-key l next-window
bind-key j switch-client -n
bind-key k switch-client -p
# 追加（矢印両対応）
bind-key Left  previous-window
bind-key Right next-window
bind-key Down  switch-client -n
bind-key Up    switch-client -p
```

注意：`prefix + 矢印` は tmux デフォルトで `select-pane`（ペイン移動）に割当済み。
上書きになるが、ペイン移動は `Alt+hjkl`/`Alt+矢印` 側で行うため実害なし。

### 3. Neovim `config/nvim/lua/plugins/smart-splits.lua`

現状（9-12行）の `<M-h>`等に加え、`<M-Up>`等を同じ関数にバインド。

```lua
-- 既存（残す）
vim.keymap.set({ 'n', 'i', 't' }, '<M-h>', require('smart-splits').move_cursor_left)
... (j/k/l同様)
-- 追加（矢印両対応）
vim.keymap.set({ 'n', 'i', 't' }, '<M-Left>',  require('smart-splits').move_cursor_left)
vim.keymap.set({ 'n', 'i', 't' }, '<M-Down>',  require('smart-splits').move_cursor_down)
vim.keymap.set({ 'n', 'i', 't' }, '<M-Up>',    require('smart-splits').move_cursor_up)
vim.keymap.set({ 'n', 'i', 't' }, '<M-Right>', require('smart-splits').move_cursor_right)
```

### 4. AutoHotkey `windows/AutoHotkey/AutoHotkey.ahk.tmpl`

現状（143-146行）の `Ctrl+Shift+hjkl`（Windowsウィンドウ移動 `#{矢印}`）に加え、
`Ctrl+Shift+矢印` を追加。

```ahk
; 既存（残す）
<^<+h::Send "#{Left}"
... (j/k/l同様)
; 追加（矢印両対応）
<^<+Left::Send  "#{Left}"
<^<+Down::Send  "#{Down}"
<^<+Up::Send    "#{Up}"
<^<+Right::Send "#{Right}"
```

Thunderbird限定の `Shift+h/l`（138-139行）は今回対象外（必要なら別途）。

## 衝突チェック結果

- tmux：`M-Up/M-Down/M-Left/M-Right` は現状未使用 → 衝突なし
- WezTerm：`Alt+矢印` は現状未使用（`Ctrl+Alt+矢印`はペインサイズ調整で別物） → 衝突なし
- AHK：`Ctrl+Shift+矢印` は現状未使用 → 衝突なし
- キーボード(.vil)：Layer2/Layer3 の右手hjkl位置に既に `→↑↓←` がvim方向通りに配置済み。
  親指 `LT2`/`LT3` ホールドで矢印レイヤーに乗れる。**.vil側の変更は不要**。

## 反映方法

- WSL（tmux.nix / smart-splits.lua）：`home-manager switch --flake .`
  - ただしnvimはシンボリックリンクのため smart-splits.lua は即時反映
  - tmuxは設定リロード（`prefix + r`）または再起動
- WezTerm（keys.lua）：保存で自動リロード（または設定リロード）
- AHK（.ahk.tmpl）：Windowsで `chezmoi apply --source .\windows` 後、AHKスクリプト再起動

## 検証観点

1. QWERTY時：`Alt+hjkl` で従来どおりペイン移動できる（デグレなし）
2. 大西配列時：`LT2/LT3`ホールド＋右手hjkl位置で `Alt+矢印` が出てペイン移動できる
3. WezTerm単独ペイン / tmuxペイン / nvim split の3シーンすべてで両方式が動く
4. Windowsウィンドウ移動が `Ctrl+Shift+矢印` で動く
5. tmuxウィンドウ/セッション移動が `prefix+矢印` で動く（`prefix+hjkl`もデグレなし）

## 未確認・要検証事項（実装時に確認）

- WezTerm `SendKey{ key='LeftArrow', mods='ALT' }` が tmux に `M-Left` として正しく
  届くか（キー名の正確な表記含む）。届かない場合は `send-keys` 側のキー表記調整が必要。
- tmux の extended-keys 設定（`set -s extended-keys on`）が `M-矢印` の転送に影響しないか。
```
