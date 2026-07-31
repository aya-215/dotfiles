# tmux復元時のClaude Code会話復元 — 設計ドキュメント

`wsl --shutdown` 後にtmuxセッションを復元したとき、各ペインで開いていた
Claude Codeの**会話**まで復元する仕組み。設計の理由と、修正時に踏まないための
制約をまとめる。

同じディレクトリで複数ペインを開いていても、**ペインごとに元の会話**へ戻る。
`claude -c` は「そのディレクトリの直近の会話」しか開けないため、それだけでは
全ペインが同一会話になってしまう。

- 操作方法は [tmux-guide.md](tmux-guide.md) を参照
- 関連コミット（時系列）:
  - `c963610` continuum自動保存の修復（status-right上書き問題）
  - `1fa01e4` 会話復元の実装
  - `e3d71f5` pane_indexズレ修正（パス主キー + rank方式へ）
  - `f7f92b0` ペイン閉鎖時のズレ修正（tombstone導入）
  - `0f8cf97` tombstoneの永久化を修正（再記録で復活）
  - `7cfeb7c` 同一session_idが複数枠を占有する問題（後に9296a77で不要化）
  - `869ef1e` order配列の二重登録を修正
  - `9296a77` tombstoneに座標を持たせる
  - `9d797fd` 自動起動の競合 + restore.shのプロセス残留
  - `49cde79` 復元を明示的に実行（continuumの推測を回避）
  - `be5bcb9` 復元をrun-shell経由に（ソケット未指定の修正）

## 全体構成

```
起動時 (SessionStart hook)  record.sh  → マップに記録行を追記
終了時 (SessionEnd hook)    forget.sh  → マップに無効化行を追記
復元時 (resurrect)          restore.sh → マップから引いて claude -r <id>
```

| ファイル | 役割 |
|---|---|
| `scripts/claude-pane-session/record.sh` | SessionStart hook。ペイン座標→session_idを記録 |
| `scripts/claude-pane-session/forget.sh` | SessionEnd hook。終了した会話を無効化 |
| `scripts/claude-pane-session/restore.sh` | resurrectの復元コマンド。会話を引き当てて起動 |
| `.claude-global/settings.json` | hookの配線（SessionStart / SessionEnd） |
| `modules/tmux.nix` | `@resurrect-processes` / `@continuum-restore off` / 保存トークン |
| `modules/zsh.nix` | tmux自動起動。サーバ生成の直列化と復元の明示実行 |

マップの実体: `~/.local/share/claude-pane-session/map.tsv`（TSV・**追記のみ**）

## マップのフォーマット

2種類の行が混在する。1列目が `END` かどうかで区別する。

**記録行（5列）**

```
セッション名 <TAB> window_index <TAB> pane_index <TAB> パス <TAB> session_id
AI_dev  1  1  /home/aya/.dotfiles  030d51d7-9ded-4bd9-81b9-18878a639cf7
```

**無効化行（tombstone・6列）**

```
END <TAB> セッション名 <TAB> window_index <TAB> pane_index <TAB> パス <TAB> session_id
END  AI_dev  1  1  /home/aya/.dotfiles  030d51d7-...
```

**無効化行（旧形式・2列）**

tmux外での終了など座標が取れない場合はこの形式で書かれる。座標不明のため
**全枠に効く**。過去のマップに残っている旧形式も同じ扱い（後方互換）。

```
END <TAB> session_id
```

## 引き当てアルゴリズム

パスを主キーにし、同一パス内の順位（rank）で区別する。

```
1. 自分のパスと、同一window内で同じパスを持つペインのうち
   pane_index 順で自分が何番目か（rank）を求める
2. マップを同じ (セッション名, window_index, パス) で絞る
3. pane_index ごとに最新の session_id へ畳む
   ・記録行を読んだ時点で、その (pane_index, session_id) の無効化を打ち消す
4. 無効化されている枠を落として詰める
5. rank 番目を採用する → claude -r <session_id>
```

各ペインで**独立に**実行される（resurrectがsend-keysで各ペインに送る）。
ペイン間で調整する余地はないため、判定は自ペインから見える情報のみで行う。

会話ファイルの存在を事前に確認し、無ければ `claude -c` にフォールバックする。

## 設計判断の理由

### なぜペインID（`%0`）を使わないか

tmux-resurrectの `pane_format`（`save.sh:28`）は固定フィールドのみで、
**ペインIDを保存しない**。復元後は別のIDが割り当てられるため紐付かない。

### なぜ座標（pane_index）だけでは駄目か

`pane_index` は下位indexのペインを閉じると繰り上がる。座標だけをキーにすると
別ペインの会話を引く。

```
3ペイン (idx1=.dotfiles, idx2=/tmp, idx3=/var) の idx1 を閉じる
→ /tmp が idx1 に繰り上がる
→ /tmp のペインが .dotfiles の会話を開く（cwdが全く違う会話が開く）
```

### なぜパスだけでも駄目か

同一パスに複数ペインがあると区別できず、全ペインが同じ会話になる。
これは `claude -c` の挙動そのもので、解決したかった元の問題に戻る。

### なぜ SessionEnd（tombstone）が必要か

rank方式は**同一パスのペイン枚数が変わるとズレる**。

```
2ペイン (rank0=会話A, rank1=会話B) のうち会話A側を閉じる
→ 残ったペインが rank0 になる
→ マップの rank0 = 会話A を引く（隣の会話が開く）
```

ペインを閉じればclaudeも終了しSessionEndが発火する。つまり
**ズレる契機（枚数変化）と直す契機（claude終了）が一致する**。
終了した会話を無効化すれば rank は常に整合する。

### なぜ tombstone に座標が必要か

session_idだけで無効化すると、**同じ会話を複数ペインで開いていた場合に
片方が離脱しただけで両方の記録が死ぬ**。

```
claude -c で両ペインが同じ会話(073fd4e1)を開く
  rec idx=1 073fd4e1
  rec idx=2 073fd4e1
片方で /resume して別会話へ移る
  END       073fd4e1   ← 座標が無いと両方の枠が死ぬ
  rec idx=1 86a3f1a7
→ idx=2 は生きているのに claude -c に落ちる
```

これは `claude -c` で開いてから片方を `/resume` するという**通常の運用**で
必ず踏む。座標つきで記録し `(pane_index, session_id)` の組で照合する。

### なぜ tombstone を永久扱いにしないか

会話を閉じてから `-c` や `/resume` で再開すると、**同じ session_id が
END の後に再記録される**。tombstoneを永久扱いにすると生きている会話を
抑止してしまう。マップは追記のみなのでファイル順＝時系列であり、
後に来た記録行が最新の事実になる（last-writer-wins）。

### なぜ削除ではなく追記（tombstone）か

`record.sh` と `forget.sh` は複数ペインで同時に発火しうる。ファイルを読んで
書き戻す方式（`awk > tmp && mv`）だと、その間に来た追記を取りこぼす。
追記のみなら競合しない。

### なぜ出現順の配列を持たないか

かつて「同じsession_idを持つ他の枠を捨てる（evict）」処理があったが、
evict後に同じ枠が再登録されると出現順の配列に枠が二重登録され、
別々のrankが同じ枠を指した（複数ペインが同一会話を引く）。
座標つきtombstoneの導入でevict自体が不要になり、集計は
`latest[]` のキー（常に一意）から集める形にした。

### なぜ畳んでから rank を取るか

マップは追記のみなので、同じ枠に世代が溜まる（`/clear` や resume ごとに
新しい session_id が発行される）。畳む前に並べると、世代違いの記録が
別ペインの枠を埋めてしまう。**この順序を逆にすると静かに誤動作する。**

### なぜ hook stdin の `.cwd` ではなく `pane_current_path` か

resurrectが保存・復元するのは `pane_current_path` であり、`restore.sh` が
実行時に参照できるのもそちら。実測では両者は一致したが、Claude Code側の
cwd概念と乖離する可能性を避けた。

### なぜ claude を必ず exec で起動するか

`claude -r "$sid" || exec claude -c` のように `-r` 側を exec しないと
`restore.sh` がプロセスツリーに残る。すると resurrect が次回保存時に
フルコマンドを `bash .../restore.sh` として記録し、これは `^claude` に
マッチしないため**2回目以降の復元でclaudeが一切起動しなくなる**。

そのため `||` によるフォールバックは使えない。会話ファイルの存在を
事前確認して分岐する。

## 起動時に復元を発火させる仕組み（modules/zsh.nix）

**ここが最も壊れやすい。** 会話の引き当てが完璧でも、復元自体が走らなければ
何も起きない。

### continuum の自動復元は使わない（`@continuum-restore off`）

continuumは `another_tmux_server_running_on_startup()` でtmuxプロセス数を数え、
2以上なら「別サーバがある」と判断して復元を抑止する。しかしこの数は
**構造的に2以上になる**。

```
9399 tmux new-session -ds main   ← クライアント側
9401 tmux new-session -ds main   ← サーバ側
```

`tmux new-session` は常にクライアントとサーバの2プロセスになる（実測）。
さらに他シェルの `tmux attach` がサーバ生成より先に起動して待機している
（実測: attach が 14:05:28、サーバが 14:05:31）。attach はロック外で
実行するため、flockで直列化しても数は減らない。

→ プロセス数の推測に頼らず、サーバを作ったシェル自身が復元を呼ぶ。

### 復元は run-shell 経由で呼ぶ

resurrectの `restore.sh` は `tmux_socket()` が `$TMUX` からソケットパスを
取得する実装になっている。

```
scripts/restore.sh:104  echo $TMUX | cut -d',' -f1
scripts/restore.sh:149  TMUX="" tmux -S "$(tmux_socket)" new-session ...
```

tmuxの外から直接起動すると `$TMUX` が空のため `tmux -S "" new-session` と
なり、**全セッションの復元が失敗する**。

```
実測された残存プロセス（-S の値が空）:
  539 tmux -S  new-session -d -s ebase-middleware-mcp -c /home/aya/src/...
```

`tmux run-shell "$restore_script"` なら tmux が `$TMUX` を設定した状態で
実行されるため、ソケットパスが正しく解決される。

### main は足場なので復元後に削除する

`restore.sh` は既存サーバに対してしか動かないため、先にサーバを起動する
必要がある。その手段が `tmux new-session -ds main`。

復元が成功して他のセッションが立ったら `main` は用済みなので削除する。
残すと**再起動ごとに `main` が増えていく**（2セッション保存 → 復元後3つ、
というように累積する）。

復元対象が無かった場合は `main` が唯一のセッションなので残す。
判定は `grep -cxv main` で完全一致の除外（`main-project` のような
名前は別セッションとして数える）。

### flock -o でサーバ生成を直列化する

WezTermが複数ペイン/タブを同時に開くと複数のzshが同時に自動起動へ来る。
直列化しないと `main` が重複したり、サーバ生成が競合する。

**`-o`（close-on-exec）が必須。** tmuxサーバはロックfdを継承したまま常駐する
ため、`-o` が無いとロックが永久に解放されず後続シェルがハングする（実測）。

## 実測で確認した事実

推測ではなく実機で確認した挙動。修正時の前提として使える。

| 項目 | 結果 |
|---|---|
| hookへの `TMUX_PANE` 継承 | される |
| hook stdin | `session_id` / `cwd` / `source` / `reason` を含む |
| `/resume` でSessionStart | 発火する（`source=resume`、同じsession_id） |
| `tmux kill-pane` でSessionEnd | 発火する（`reason=other`） |
| `/clear` でSessionEnd | 発火しない |
| `claude --session-id <既存UUID>` | `already in use` エラー。**再開には使えない** |
| `claude -r <存在しないUUID>` | 終了コード **1**（`-p` 有無どちらも） |
| `tmux new-session` のプロセス数 | 常に2（クライアント + サーバ） |
| `run-shell` 内の `$TMUX` | 設定される（ソケットパスが取れる） |
| resurrectのペイン変数(`@xxx`)保存 | **されない** |
| resurrectの `pane_title` | 保存・復元される（が下記の理由で使えない） |
| claude終了後のペイン | フルコマンドが空欄で保存され、restore.shは呼ばれない |

## 棄却した案

### ペイン変数（`@claude_pane_uid`）にIDを持たせる

resurrectがペイン変数を保存しないため不成立。

### `pane_title` にIDを埋める

保存・復元はされるが2つの理由で使えない。

1. Claude Code自身がタスク要約を書き込み続ける（保存データに
   `✳ 指摘内容の修正検討と対応方針` 等が実際に入っている）
2. `modules/tmux.nix` の `set-titles-string '#T'` によりWezTermの
   タブタイトルに出る。UUIDが見えるのは明確な劣化

### `--session-id` でUUIDを事前割り当て

`claude --session-id <既存UUID>` は `already in use` で失敗する。
復元は同じコマンドの再実行なので、2回目以降が必ずエラーになる。
再開は `-r` のみ。

### `@resurrect-processes` でペインごとに別コマンドを割り当てる

resurrectの `_process_on_the_restore_list` / `_get_inline_strategy` は
`pane_full_command` だけをキーに判定する。`restore_pane_process` は
ペインindexを受け取るがstrategy解決には使わない。よって
「ペイン1は `-c`、ペイン2は `-r`」は表現できない。

→ 復元コマンド自体をスクリプトにして、スクリプト側でペインを見る形にした。

### flockでcontinuumの判定を満たす

`tmux new-session` が常に2プロセスになるため原理的に不可能。
復元を明示的に呼ぶ方式に切り替えた。

## fail-soft

どの経路で失敗しても `claude -c` に落ちる。空ペインは残さない。

| 状況 | 結果 |
|---|---|
| claudeを閉じていた | restore.shが呼ばれない（zshのみ復元） |
| マップが無い | `claude -c` |
| 座標・パスが不一致 | `claude -c` |
| UUIDが壊れている | `claude -c` |
| 列不足（4列以下） | `claude -c` |
| tmux外で実行 | `claude -c` |
| rank超過（記録が足りない） | `claude -c` |
| 会話ファイルが存在しない | `claude -c` |

## 既知の制約

### tombstoneが付かないケース

`wsl --shutdown` はVMを即停止するためhookが走らない。この場合は記録が
丸ごと残り全ペインが復元対象になる。**これは意図した挙動**（意図せず
落ちた場合は全部戻したい）。意図的に閉じた場合だけ間引かれる。

### 同一パスでペインを増やした場合

記録が無いrankは `claude -c` になる。害はない。

### 最大5分の取りこぼし

保存間隔は5分。`wsl --shutdown` やWindows再起動はVMを即停止するため
保存の余地がない。意図的に落とすときは `C-q W` を挟むと確実。

### マップの肥大

`record.sh` が2000行を超えたら末尾1000行に切る。末尾が最新なので
latest-winsの探索順序は壊れない。

## 修正時の検証手順

引き当てロジックを変えたら、最低この4ケースを確認する。
スタブの `claude` をPATHに置けば実際に起動せずに検証できる。

```bash
# スタブ（claudeを起動せず引数だけ表示）
mkdir -p /tmp/stub && printf '#!/usr/bin/env bash\necho "→ claude $*"\n' > /tmp/stub/claude
chmod +x /tmp/stub/claude

# 実行例（TMUX_PANEは対象ペインのIDを明示的に渡す）
env PATH="/tmp/stub:$PATH" CLAUDE_PANE_SESSION_MAP=/tmp/test.tsv \
  TMUX_PANE=%5 bash scripts/claude-pane-session/restore.sh
```

| ケース | 期待 |
|---|---|
| 同一パス2ペイン、tombstone無し | 各ペインが別の会話を引く |
| 同一パス2ペイン、片方を座標つきtombstone | 残った側が**自分の**会話を引く |
| 同一パスでpane_indexがズレた | パスが同じなら正しい会話を引く |
| 全会話をtombstone | 全ペイン `claude -c` |

### 検証時の注意（実際にハマったもの）

- **UUIDは16進数のみ**。`tttttttt-...` のようなダミーは正規表現で弾かれ、
  ロジックが正しくても失敗する
- `TMUX_PANE` は明示的に渡す。未設定だと現在のペインを見てしまう
- `export` した `CLAUDE_PANE_SESSION_MAP` が残っていると意図しない
  マップを読む。`env` で都度渡す
- 配列展開（`${PS[@]}`）が空になっていないか確認する。空の `TMUX_PANE` で
  実行すると現在のペインを見て誤った結果になる

### tmuxを絡めたテストの隔離

**`TMUX` を unset しないと隔離できない。** `TMUX` が設定されていると
tmuxはそのソケットを使い `TMUX_TMPDIR` や `-L` を無視するため、
ライブサーバに接続してしまう（実際に接続してしまった）。

```bash
env -u TMUX TMUX_TMPDIR=/tmp/testdir tmux -L testsock ...
```

ただし **resurrect の `restore.sh` は `-L` を受け取らず
`TMUX_TMPDIR/default` を見る**ため、復元処理自体は隔離テストできない。
実機の `wsl --shutdown` で確認する必要がある。

## `@resurrect-processes` の書式の罠

```nix
set -g @resurrect-processes '"claude->~/.dotfiles/scripts/claude-pane-session/restore.sh"'
```

- **内側の `"` は必須**。resurrectが `eval set` するため、無いと要素が
  バラけて無効化される
- **`->` の前後にスペースを入れない**。resurrectは `->` の左右をsedで
  切り出すだけでtrimしないため、`"claude -> ..."` だとマッチ対象が
  `claude `（末尾スペース付き）になり `^claude` + スペース2つ となって
  **一切マッチしない**
- restore.shのパスは `^claude` にマッチしないため、書き換えループしない

## continuum自動保存の注意

`modules/tmux.nix` の `status-right` には continuum の保存フックを
**明示的に埋め込んでいる**。

```nix
set -g status-right "#(${pkgs.tmuxPlugins.continuum}/share/.../continuum_save.sh)#{E:@catppuccin_...}"
```

continuumは本来プラグイン読み込み時に `status-right` の先頭へこれを挿入するが、
Home Managerは常にプラグインの `run-shell` を `extraConfig` より先に出力するため、
`extraConfig` 側の `set -g status-right` が後から上書きしてフックを消す。

復元は別経路で動くので、**復元は動くのに保存だけ止まる**という非対称な
症状になる（古いスナップショットしか戻らない）。

`status-right` を編集するときはこのトークンを消さないこと。パスは `pkgs` 経由で
解決しているのでプラグイン更新時も追従する（ハッシュ直書きは禁止）。

なお `@continuum-restore` を `off` にしても保存には影響しない。
`auto_restore_enabled` は復元のみを gate しており、保存はこのトークンで
駆動されるため。
