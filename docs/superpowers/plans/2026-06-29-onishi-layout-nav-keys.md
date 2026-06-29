# 大西配列対応：ナビゲーションキー矢印両対応 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** vim/tmux/WezTerm/AutoHotkeyのナビゲーションバインドに `矢印`（Alt+矢印 / prefix+矢印 / Ctrl+Shift+矢印）を追加し、大西配列でもQWERTYでも移動できる両対応にする。

**Architecture:** 既存の `hjkl` バインドは一切消さず、対応する `矢印` バインドを各層に「追加」する。ペイン移動は WezTerm→tmux→Neovim の3層連動で全て文字h/j/k/lで繋がっているため、3層すべてに矢印の受け口を足す。キーボード(.vil)側は既に矢印が正しい物理位置に配置済みのため変更不要。

**Tech Stack:** tmux (Nix/Home Manager), WezTerm (Lua), Neovim (Lua/smart-splits.nvim), AutoHotkey v2 (chezmoiテンプレート)

## Global Constraints

- 既存の `hjkl` バインドは削除しない（QWERTY時のデグレ防止）。すべて「追加」のみ。
- tmux/Neovim設定は `modules/*.nix` / `config/nvim/` のソースを編集する。生成物は直接編集しない。
- WSL反映: `home-manager switch --flake .`（nvimはシンボリックリンクのため即時反映）。
- Windows反映: `chezmoi apply --source .\windows`（Windows側で実行）。
- コミットメッセージ prefix: `feat:` を使用。
- コミット後は最後に `git push`。

---

### Task 1: Neovim smart-splits に矢印バインド追加

**Files:**
- Modify: `config/nvim/lua/plugins/smart-splits.lua:9-12`

**Interfaces:**
- Consumes: `require('smart-splits').move_cursor_left/down/up/right`（既存）
- Produces: `<M-Left>/<M-Down>/<M-Up>/<M-Right>` のキーマップ（Task 2のtmuxが `send-keys M-Left` 等で送る先）

- [ ] **Step 1: 矢印バインドを追加**

`config/nvim/lua/plugins/smart-splits.lua` の `config = function` 内、既存の `<M-l>` 行（12行目）の直後に追記:

```lua
    vim.keymap.set({ 'n', 'i', 't' }, '<M-Left>', require('smart-splits').move_cursor_left, { desc = '左へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-Down>', require('smart-splits').move_cursor_down, { desc = '下へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-Up>', require('smart-splits').move_cursor_up, { desc = '上へ移動' })
    vim.keymap.set({ 'n', 'i', 't' }, '<M-Right>', require('smart-splits').move_cursor_right, { desc = '右へ移動' })
```

- [ ] **Step 2: 反映と検証**

nvimはシンボリックリンクのため即時反映。Neovimを再起動（または `:Lazy reload smart-splits.nvim`）。
nvimで縦分割を作る: `:vsplit`
ターミナルでキー入力を確認するため `:verbose imap <M-Left>` 相当として、まず Normal モードで:
Run（nvim内で実行）: `:nmap <M-Left>`
Expected: `n  <M-Left>     * <Lua function ...>`（マッピングが存在する）

実際の移動確認: 縦分割した状態で `Alt+Left`/`Alt+Right` を押してカーソルが左右ペインを移動すること。
（QWERTYキーボードで `Alt+矢印` を直接押して確認。大西配列レイヤーは後でまとめて確認）

- [ ] **Step 3: Commit**

```bash
cd /home/aya/.dotfiles && git add config/nvim/lua/plugins/smart-splits.lua
git commit -m "feat: smart-splitsにAlt+矢印バインドを追加（大西配列対応）"
```

---

### Task 2: tmux にペイン移動とウィンドウ移動の矢印バインド追加

**Files:**
- Modify: `modules/tmux.nix:110-113`（ペイン移動 Alt+hjkl の直後に追加）
- Modify: `modules/tmux.nix:116-119`（ウィンドウ/セッション移動 prefix+hjkl の直後に追加）

**Interfaces:**
- Consumes: `@pane-is-vim`（smart-splits連携で設定される変数、既存）、Task 1の `<M-Left>` 等のnvimマップ
- Produces: tmuxの `M-Left/M-Down/M-Up/M-Right` ルートバインド（Task 3のWezTermが `SendKey` で送る先）、`prefix + 矢印` のウィンドウ/セッション移動

- [ ] **Step 1: ペイン移動の矢印バインドを追加**

`modules/tmux.nix` の113行目（`bind-key -n M-l ...` の行）の直後に追記:

```
      # ペイン移動 矢印両対応（大西配列対応）
      bind-key -n M-Up    if-shell -F "#{@pane-is-vim}" 'send-keys M-Up'    'select-pane -U'
      bind-key -n M-Down  if-shell -F "#{@pane-is-vim}" 'send-keys M-Down'  'select-pane -D'
      bind-key -n M-Left  if-shell -F "#{@pane-is-vim}" 'send-keys M-Left'  'select-pane -L'
      bind-key -n M-Right if-shell -F "#{@pane-is-vim}" 'send-keys M-Right' 'select-pane -R'
```

- [ ] **Step 2: ウィンドウ/セッション移動の矢印バインドを追加**

`modules/tmux.nix` の119行目（`bind-key k switch-client -p` の行）の直後に追記:

```
      # ウィンドウ/セッション移動 矢印両対応（大西配列対応）
      bind-key Left  previous-window
      bind-key Right next-window
      bind-key Down  switch-client -n
      bind-key Up    switch-client -p
```

- [ ] **Step 3: 反映**

Run: `cd /home/aya/.dotfiles && home-manager switch --flake .`
Expected: ビルド成功（`Activating ...` まで完走、エラーなし）

生成された設定を反映するためtmux内で設定リロード:
Run（tmux内）: `prefix + r`（= `C-q r`）
Expected: `Reloaded!` 表示

- [ ] **Step 4: 検証**

tmuxで横にペイン分割（`prefix + v`）し、2ペインにする。
- `Alt+Left`/`Alt+Right` でペイン間を移動できること（QWERTYキーボードで確認）
- `prefix + Right`（`C-q` → `Right`）で次のウィンドウに移動できること（複数ウィンドウがある場合）
- 既存の `Alt+h`/`Alt+l` も従来どおり動くこと（デグレ確認）

バインド登録の確認:
Run（tmux内）: `tmux list-keys -T root | grep -i "M-Left\|M-Right"`
Expected: `M-Left` `M-Right` のバインドが表示される

- [ ] **Step 5: Commit**

```bash
cd /home/aya/.dotfiles && git add modules/tmux.nix
git commit -m "feat: tmuxにAlt+矢印・prefix+矢印のナビゲーションを追加（大西配列対応）"
```

---

### Task 3: WezTerm にペイン移動の Alt+矢印バインド追加

**Files:**
- Modify: `config/wezterm/keys.lua:189-195`（Alt+hjkl smart_pane_navigate の直後に追加）

**Interfaces:**
- Consumes: `smart_pane_navigate(direction, key)`（既存、keys.lua:22-30）。第2引数 `key` は委譲時に `act.SendKey{ key = key, mods = 'ALT' }` で送られる（keys.lua:27）。
- Produces: WezTermの `Alt+矢印` キーバインド（Task 2のtmuxの `M-Left` 等へ委譲）

**重要（未確認事項）:** WezTerm公式ドキュメント上、`key = 'LeftArrow'` で矢印キーを「捕捉」できることは確認済み。一方 `SendKey{ key = 'LeftArrow', mods = 'ALT' }` で矢印を「送出」できるかはドキュメントに明示例がない。Step 3の検証で送出が機能しない場合、Step 4のフォールバックを適用する。

- [ ] **Step 1: Alt+矢印バインドを追加**

`config/wezterm/keys.lua` の195行目（`{ key = 'l', mods = 'ALT', action = smart_pane_navigate('Right', 'l') },`）の直後に追記:

```lua
    -- スマートペイン移動 矢印両対応（大西配列対応）
    { key = 'LeftArrow',  mods = 'ALT', action = smart_pane_navigate('Left', 'LeftArrow') },
    { key = 'DownArrow',  mods = 'ALT', action = smart_pane_navigate('Down', 'DownArrow') },
    { key = 'UpArrow',    mods = 'ALT', action = smart_pane_navigate('Up', 'UpArrow') },
    { key = 'RightArrow', mods = 'ALT', action = smart_pane_navigate('Right', 'RightArrow') },
```

- [ ] **Step 2: 反映**

WezTermは設定ファイル保存で自動リロードされる。リロードされない場合は手動リロード（`Ctrl+Shift+R` 相当、またはWezTerm再起動）。

- [ ] **Step 3: 検証（送出可否の判定）**

WezTermで複数ペインを開かない状態（=委譲ルートを通す）で、tmuxを起動し横分割する。
- `Alt+Left`/`Alt+Right` を押してtmuxペイン間を移動できるか確認
- 移動できれば `SendKey{key='LeftArrow', mods='ALT'}` → tmux `M-Left` の経路が機能している（成功）
- 移動できなければ Step 4 のフォールバックへ

- [ ] **Step 4: （Step 3が失敗した場合のみ）フォールバック適用**

`SendKey` で矢印キー名が送れない場合、委譲時の送出キーを文字 `h/j/k/l` のままにする
（捕捉は矢印、送出は文字）。Step 1で追記した4行を以下に修正:

```lua
    -- スマートペイン移動 矢印両対応（捕捉は矢印・送出は文字でフォールバック）
    { key = 'LeftArrow',  mods = 'ALT', action = smart_pane_navigate('Left', 'h') },
    { key = 'DownArrow',  mods = 'ALT', action = smart_pane_navigate('Down', 'j') },
    { key = 'UpArrow',    mods = 'ALT', action = smart_pane_navigate('Up', 'k') },
    { key = 'RightArrow', mods = 'ALT', action = smart_pane_navigate('Right', 'l') },
```

この場合、委譲先は既存の `M-h` 等（Task 2で追加した `M-Left` は使われないが、害はないので残す）。
修正後、再度 Step 3 の検証を行い、tmuxペイン移動とnvim split移動が動くことを確認。

- [ ] **Step 5: Commit**

```bash
cd /home/aya/.dotfiles && git add config/wezterm/keys.lua
git commit -m "feat: WezTermにAlt+矢印のスマートペイン移動を追加（大西配列対応）"
```

---

### Task 4: AutoHotkey に Ctrl+Shift+矢印 のウィンドウ移動追加

**Files:**
- Modify: `windows/AutoHotkey/AutoHotkey.ahk.tmpl:143-146`（Ctrl+Shift+hjkl の直後に追加）

**Interfaces:**
- Consumes: なし（独立したホットキー定義）
- Produces: `Ctrl+Shift+矢印` のWindowsウィンドウ移動ホットキー

- [ ] **Step 1: Ctrl+Shift+矢印バインドを追加**

`windows/AutoHotkey/AutoHotkey.ahk.tmpl` の末尾（146行目 `<^<+l::Send "#{Right}"` の直後）に追記:

```ahk

; ctrl + shift + 矢印でwindowの移動（大西配列対応）
<^<+Left::Send  "#{Left}"
<^<+Down::Send  "#{Down}"
<^<+Up::Send    "#{Up}"
<^<+Right::Send "#{Right}"
```

- [ ] **Step 2: 反映（Windows側で実行）**

WindowsのPowerShellで:
Run: `chezmoi apply --source .\windows`
Expected: `AutoHotkey.ahk` が更新される。
AutoHotkeyスクリプトをリロード（タスクトレイのAHKアイコン → Reload Script、またはスクリプト再実行）。

- [ ] **Step 3: 検証（Windows側で実行）**

任意のウィンドウをアクティブにし、`Ctrl+Shift+Left`/`Ctrl+Shift+Right` を押す。
Expected: Windowsのウィンドウが画面左半分/右半分にスナップする（`Win+矢印` と同じ挙動）。
既存の `Ctrl+Shift+h`/`Ctrl+Shift+l` も従来どおり動くこと（デグレ確認）。

- [ ] **Step 4: Commit**

```bash
cd /home/aya/.dotfiles && git add windows/AutoHotkey/AutoHotkey.ahk.tmpl
git commit -m "feat: AHKにCtrl+Shift+矢印のウィンドウ移動を追加（大西配列対応）"
```

---

### Task 5: 大西配列レイヤーでの統合検証と push

**Files:**
- なし（検証のみ）

**Interfaces:**
- Consumes: Task 1-4 のすべての変更

- [ ] **Step 1: 大西配列レイヤーで実機統合検証**

Vialで `TO(1)` を押して大西配列レイヤーに切替え。親指で `LT2` または `LT3` をホールドした状態で、
右手のQWERTY-hjkl物理位置（H行 col2〜col5）を押すと `Alt+矢印` が出ることを利用し、以下を確認:

1. **tmuxペイン移動**: tmuxで横分割 → 大西レイヤーで `LT2/LT3`ホールド + 右手hjkl位置 → ペイン移動できる
2. **Neovim split移動**: nvimで `:vsplit` → 同上の操作でsplit間移動できる
3. **WezTermペイン移動**: WezTermでペイン分割 → 同上で移動できる
4. **tmuxウィンドウ移動**: `prefix + 矢印`（大西レイヤーで矢印を出す）でウィンドウ移動できる
5. **Windowsウィンドウ移動**: `Ctrl+Shift+矢印`（大西レイヤーで矢印を出す）でウィンドウスナップできる

すべてのシーンで QWERTY時の `hjkl` も引き続き動くこと（デグレなし）を確認。

- [ ] **Step 2: 設計書の未確認事項を結果で更新**

`docs/superpowers/specs/2026-06-29-onishi-layout-nav-keys-design.md` の「未確認・要検証事項」
セクションに、Task 3 Step 3 の結果（`SendKey`矢印送出が機能したか/フォールバックを使ったか）を追記する。

- [ ] **Step 3: push**

```bash
cd /home/aya/.dotfiles && git push
```

Expected: リモート（`git@github-aya215:aya-215/dotfiles.git`）へpush成功。
push失敗時は `git remote set-url origin git@github-aya215:aya-215/dotfiles.git` で修正後再push。

- [ ] **Step 4: Commit（設計書更新分）**

```bash
cd /home/aya/.dotfiles && git add docs/superpowers/specs/2026-06-29-onishi-layout-nav-keys-design.md
git commit -m "docs: ナビキー矢印対応の検証結果を設計書に反映"
git push
```
