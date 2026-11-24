---
name: update-all
description: dotfiles と自分の開発環境で使っているもの（Nix flake・Neovim プラグインと Mason・zeno.zsh・tmux-agent-sidebar・scripts の Python 依存・uv/coderabbit/dotenvx・Claude Code プラグイン・archify スキル）をまとめて最新にする。「全部アップデートして」「まとめて更新」「環境を最新にして」「更新あるか見て」「/update-all」等で使用。Nix だけなら nix-update スキル。
allowed-tools: Read, Edit, Bash, AskUserQuestion, Skill
---

# update-all

更新できるものを一覧にして、選んだものを「更新 → 動作確認 → コミット」の順に1つずつ上げる。
版の一覧は `scripts/update-all/status.sh` が決定的に集める。Claude は一覧を作り直さない。

## 原則

- **確認を取ってから実行するもの**: メジャー更新（`更新あり(メジャー)`）、設定ファイルの修正、第三者プラグインの更新、何かを削除する操作、固定の解除。ユーザーが「確認なしで」と言っても省かない。代わりに、手順1で前もって聞ける分を1回の質問にまとめる。途中で聞くのは、更新してみて初めて分かったことだけにする（設定名の変更、固定を外せる見込み、第三者プラグインの差分にある気になる処理、dotenvx の読み込み結果の不一致）。
- **壊れたらまず元に戻す**: 動作確認で壊れたと分かったら、原因を調べる前に更新前の状態へ戻す（lock を `git checkout` して入れ直す等）。今動いている Claude セッションや新しく開くシェルが使うものは、壊れたまま置かない。
- **動作確認は実物で**: 「読み込めた」「エラーが出ない」ではなく、その道具の本来の動作（略語の展開、MCP のツール一覧、`.env` の読み込み結果）で確かめる。
- **コミットは対象ごと**: 更新は `chore:`、設定の修正は `fix:` で別コミットにする。作業ツリーにある無関係な変更は add しない。nix-update スキルは自分で push する。それ以外は最後にまとめて push する。dotfiles の外にあるもの（zeno・sidebar・dotenvx・uv 等の単体コマンド・プラグイン）はコミットが無い。

## 手順

### 1. 一覧を出して、やるものと確認事項をまとめて決める

```bash
bash ~/.dotfiles/scripts/update-all/status.sh | column -t -s $'\t'
```

30秒〜1分かかる（git fetch・Lazy の check・プラグインのカタログ更新を含む）。対象を絞るなら引数に `nix nvim zeno sidebar python tools plugins archify` から並べる。

表は切り詰めずにそのまま見せる。そのうえで **AskUserQuestion（multiSelect）** で、`更新あり` `更新あり(メジャー)` `要確認` の行を選んでもらう。

- 選択肢には今と最新の版を書く。メジャー更新・第三者プラグイン・archify（ファイルが入れ替わる）は、選んだ時点でその確認も済んだことにする。dotenvx は「比べて一致したら入れ替える」と書いておく。
- `固定` の行は選択肢に出さない。
- `要確認` は版が分からない行（coderabbit、版の無い公式カタログのプラグイン）。選ばれたら更新コマンドに判定させる。

### 2. 選ばれた対象を下の順で上げる

Nix → Neovim → 残りの順にする（Nix で Neovim 本体や tree-sitter の版が変わるため）。

| 対象 | 更新 | 動作確認 | 既知の罠 |
|---|---|---|---|
| nix | `nix-update` スキルを呼ぶ（戻り先の記録・switch・警告検知・コミット・push まで任せる。未コミットの変更を聞かれたら「続行」） | 下の「起動確認」 | 下の「deno の固定」 |
| nvim | `nvim --headless "+Lazy! sync" +qa` → `nvim --headless "+lua require('lazy').load({plugins={'nvim-treesitter'}})" "+TSUpdateSync" +qa` → `nvim --headless -c "luafile ~/.dotfiles/scripts/update-all/mason-update.lua"` | 起動時メッセージが空か（下の「起動確認」）。警告が出たら下の「設定名の変更」 | 設定項目の改名は警告だけで、古い設定は**黙って無視される**（smart-splits の `at_edge` → `move.at_edge` で端の動作が変わっていた） |
| zeno | `git -C ~/src/github.com/yuki-yano/zeno.zsh pull --ff-only`（前の HEAD を控える） | 使い捨て tmux で略語展開・Enter・Tab（下の「zsh のテスト」） | 壊れていたら控えた HEAD に `checkout` |
| sidebar | agent-memory の `tmux/agent-sidebar-update.md` の手順（`local-patches` を rebase → `cargo build --release` → `bin/` にコピー） | `bin/tmux-agent-sidebar version` | 一覧で PR #159/#167 が `MERGED` ならパッチを捨てて main に戻せる。動いているサイドバーは作り直さない（新しいウィンドウから順に替わる） |
| python | `更新あり` の行がある `scripts/*/` だけ、`uv lock --upgrade` → `uv sync`。`固定` の行しか無いなら触らない | gitbucket-mcp: `uv run python -m unittest -q test_server` と、MCP の tools/list で **11個** 返るか（下の「MCP のテスト」） | `uv lock --upgrade` は表に出ない間接依存も上げる。`mcp` は v2 で `FastMCP` が `MCPServer` に改名され起動しないので `<2` に固定済み。v2 移行は「MCP をやめて gitbucket-api スキルへ一本化」とまとめて検討する予定 |
| tools | 選ばれた行だけ: uv → `uv self update`、`uv tool: <名前>` → `uv tool upgrade <名前>`、coderabbit → `coderabbit update` | `--version` と `--help` が動くか | dotenvx は下の「dotenvx の入れ替え」 |
| plugins | 第三者のものは先に下の「第三者プラグイン」で差分を見る → `claude plugin update <id> -y`（一括更新コマンドは無い） | 反映は次のセッションか `/reload-plugins` と伝える | 公式（`claude-plugins-official`）と `ebase-claude-marketplace` 以外が第三者 |
| archify | 下の「archify の入れ替え」 | `SKILL.md` の差分を見せ、`node bin/archify.mjs --help` が動くか | |

### 3. まとめを報告する

```markdown
## 更新結果
| 対象 | 版 | 確認 | コミット |
|---|---|---|---|
| nixpkgs | 2026-10-20 → 2026-11-21 | switch 成功・警告なし | 95c0237 |
| dotenvx | 1.61.0 → 2.38.2 | 読み込み結果のハッシュ3種が一致 | -（dotfiles 外） |

**見送り**: <対象>（<理由>）
**直したもの**: <設定修正の内容>（<コミット>）
**自分でやってほしいこと**: <例: Claude Code の再起動、消せなかったファイルの削除コマンド（クリップボード済み）>
```

## 個別の手順

### 起動確認

```bash
zsh -i -c 'echo zsh-ok' 2>&1 | tail -1                 # 端末なしで出る "can't change option: zle" は無視してよい
tmux source-file -n ~/.config/tmux/tmux.conf && echo tmux-ok   # -n は解析だけ。今の tmux の設定は変えない
nvim --headless "+lua vim.defer_fn(function() local m=vim.api.nvim_exec2('messages',{output=true}).output print(m=='' and 'no-messages' or m) vim.cmd('qa!') end, 4000)" 2>&1 | tail -5
```

### 設定名の変更

起動時に「`X` moved to `Y`」のような警告が出たら、設定ファイルを直すのを先にする（戻すのは、直し方が分からないか、ユーザーが断ったとき）。

1. `checkhealth <プラグイン名>` で、今効いている値を確かめる。checkhealth が無いプラグインは、そのプラグインの config モジュールを `vim.inspect` で出す。
2. 警告に出たキーと同じブロックの他のキーも移っていないか、プラグインの変更履歴で確かめる。範囲は `git -C ~/.dotfiles diff config/nvim/lazy-lock.json` に出る旧と新のコミットで、`git -C ~/.local/share/nvim/lazy/<名前> log --oneline <旧>..<新>`。
3. 修正の差分を見せて確認を取り、`fix:` でコミットする（lazy-lock.json の `chore:` とは別）。
4. 直さないなら `git checkout config/nvim/lazy-lock.json` のあと `nvim --headless "+Lazy! restore" +qa` で戻す。

### deno の固定

`flake.nix` は `nixpkgs-deno` を deno 2.9.2 の rev に固定している。2.9.7〜2.9.8 は zeno.zsh が使う `@db/sqlite` の読み込みでセグフォするため。
Nix を上げたら、新しい nixpkgs の deno で直ったかを確かめる:

```bash
D=$(nix build --no-link --print-out-paths --inputs-from ~/.dotfiles nixpkgs#deno)
bash ~/.dotfiles/scripts/update-all/deno-sqlite-check.sh "$D/bin/deno"   # 0 なら固定を外せる候補、139 はセグフォ
```

- 139（セグフォ）: 固定を残し、まとめの「見送り」に版を書く。`flake.nix` のコメントの版の範囲を広げる修正は、確認を取って `docs:` でコミットする。
- 0 でも 139 でもない（タイムアウト・JSR の取得失敗など）: 判定できなかったとして固定を残し、出力をそのまま報告する。壊れた版として記録しない。
- 0: 固定を外す提案をして確認を取る。外す箇所は次のとおりで、どれか1つでも残すと評価エラーになる。
  - `flake.nix`: `inputs` の `nixpkgs-deno`（とコメント）、`outputs` の引数の `nixpkgs-deno`、`let` の `pkgs-deno = ...`、`extraSpecialArgs` の `inherit glauncher pkgs-deno;` から `pkgs-deno`
  - `modules/packages.nix`: 引数の `pkgs-deno` を消し、`pkgs-deno.deno` を `pkgs.deno` に替えてコメントも直す
  - そのあと `nix flake lock` → `home-manager switch` → 「zsh のテスト」で zeno を確かめ、`fix:` でコミットする

zsh 越しのテストでは deno の版を差し替えられない（zshrc が PATH を上書きして固定版の deno が使われる）。だからこのチェックは deno を直接動かす。

### zsh のテスト

本物の tmux を汚さないよう、別ソケットの使い捨てサーバで試す。

```bash
S=uatest$$; T() { tmux -L $S -f /dev/null "$@"; }
T new-session -d -s z -x 150 -y 30 'sleep 600'
P=$(T split-window -t z -P -F '#{pane_id}' -c ~/.dotfiles zsh); sleep 10
T send-keys -t $P 'gs '; sleep 3; T capture-pane -p -t $P | tail -2   # git status --short --branch に展開されるか
T send-keys -t $P C-u 'echo ENTER-OK' Enter; sleep 2; T capture-pane -p -t $P | grep ENTER-OK
T kill-server
```

- zeno を上げた直後の1回目は依存のダウンロードで展開されない。もう一度試す。
- `send-keys` は必ず pane id に送る（セッション名に送ると自動で作られるサイドバーに入ることがある）。
- `-f /dev/null` のサーバはペイン番号が 0 から始まる（本物の設定は 1 から）。ペイン番号で動きが変わる処理を試すときは注意する。

### MCP のテスト

stdin をすぐ閉じると、mcp 1.30 は返事をする前に終わる。`sleep` で開けておく。

```bash
cd ~/.dotfiles/scripts/gitbucket-mcp
(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'; sleep 4) \
  | timeout 30 uv run server.py 2>/dev/null | jq -r 'select(.id==2) | .result.tools | length'
```

### dotenvx の入れ替え

`~/src/github.com/ebase-dev/ebase-portal-chat` で `.env` の読み込み順に頼っているので、旧版と新版の読み込み結果を比べ、一致したときだけ入れ替える。

1. 新版を空の一時ディレクトリに取得し、`checksums.txt` と照合する（`gh release download <tag> -R dotenvx/dotenvx -p 'dotenvx-<ver>-linux-x86_64.tar.gz' -p checksums.txt`）。`install.sh` は既定の版が古いので使わない。
2. ebase-portal-chat で、旧版と新版それぞれの出力のハッシュを比べる（値は表示しない）:
   - `<bin> get --format json | jq -S . | sha256sum`
   - `<bin> get -f .env.local -f .env --format json | jq -S . | sha256sum`
   - `<bin> get --format shell | sha256sum`
3. 一致したら旧版を `~/.local/share/dotenvx-backup/` に退避して `~/.local/bin/dotenvx` を置き換える。違ったら止めて報告する。
4. メジャー更新なら、上流の CHANGELOG で `-f` の順番・`--overload`・鍵の保管先の扱いが変わっていないかも確かめる。

### 第三者プラグイン

自動更新は公式と ebase のマーケットプレイスだけ有効（第三者は手動にすると 2026-11-24 に決めた）。
status.sh がカタログを更新済みなので、新しい版のソースは手元にある。**更新する前に**、入っている版と比べる:

```bash
M=~/.claude/plugins/marketplaces/<marketplace>
SRC=$(jq -r '.plugins[] | select(.name=="<plugin>") | .source' $M/.claude-plugin/marketplace.json)
diff -ru ~/.claude/plugins/cache/<marketplace>/<plugin>/<今の版> "$M/$SRC" -x .in_use -x .orphaned_at
```

フックやスクリプトなど実行されるコードの差分を要約して見せる。新しく外部と通信する処理や、`gh` 等で何かを書き込む処理が増えていたら、いつ動くか（自動か、ユーザーの操作か）を確かめて伝え、更新してよいか聞き直す。

### archify の入れ替え

`.claude-global/skills/archify/` は、上流 `~/src/github.com/tt-a1i/archify` の `archify/` をコピーしたもの。

1. `git -C ~/.dotfiles log --oneline -- .claude-global/skills/archify` と `git -C ~/.dotfiles status --short -- .claude-global/skills/archify` で、取り込み以外の手直し（コミット済み・未コミットとも）が無いか確かめる。あれば止めて相談する。
2. `git -C ~/src/github.com/tt-a1i/archify pull --ff-only`
3. `rsync -a --delete ~/src/github.com/tt-a1i/archify/archify/ ~/.dotfiles/.claude-global/skills/archify/`
4. `git -C ~/.dotfiles status --short -- .claude-global/skills/archify` で消えた・増えたファイルを見せ、`SKILL.md` の差分を要約する。`chore:` でコミットする。

## 対象外

- Claude Code 本体（自動で更新される）
- Windows 側（winget・chezmoi・WezTerm）
- `~/src` にある作業用リポジトリ（zeno.zsh・tmux-agent-sidebar・archify の上流以外）
