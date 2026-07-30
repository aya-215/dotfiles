# tmux復元時のClaude Code会話復元 — 設計ドキュメント

`wsl --shutdown` 後にtmuxセッションを復元したとき、各ペインで開いていた
Claude Codeの**会話**まで復元する仕組み。設計の理由と、修正時に踏まないための
制約をまとめる。

- 関連コミット: `c963610`（continuum自動保存の修復） / `1fa01e4`（会話復元の実装） / `e3d71f5`（indexズレ修正） / `f7f92b0`（ペイン閉鎖時のズレ修正）
- 操作方法は [tmux-guide.md](tmux-guide.md) を参照

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
| `modules/tmux.nix` | `@resurrect-processes` でrestore.shを指定 |

マップの実体: `~/.local/share/claude-pane-session/map.tsv`（TSV・**追記のみ**）

## マップのフォーマット

2種類の行が混在する。1列目が `END` かどうかで区別する。

**記録行（5列）**

```
セッション名 <TAB> window_index <TAB> pane_index <TAB> パス <TAB> session_id
AI_dev  1  1  /home/aya/.dotfiles  030d51d7-9ded-4bd9-81b9-18878a639cf7
```

**無効化行（tombstone・2列）**

```
END <TAB> session_id
END  030d51d7-9ded-4bd9-81b9-18878a639cf7
```

## 引き当てアルゴリズム

パスを主キーにし、同一パス内の順位（rank）で区別する。

```
1. 自分のパスと、同一window内で同じパスを持つペインのうち
   pane_index 順で自分が何番目か（rank）を求める
2. マップを同じ (セッション名, window_index, パス) で絞る
3. pane_index ごとに最新の session_id へ畳む
4. tombstone された枠を落として詰める
5. rank 番目を採用する → claude -r <session_id>
```

各ペインで**独立に**実行される（resurrectがsend-keysで各ペインに送る）。
ペイン間で調整する余地はないため、判定は自ペインから見える情報のみで行う。

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

### なぜ削除ではなく追記（tombstone）か

`record.sh` と `forget.sh` は複数ペインで同時に発火しうる。ファイルを読んで
書き戻す方式（`awk > tmp && mv`）だと、その間に来た追記を取りこぼす。
追記のみなら競合しない。

### なぜ座標ではなく session_id で無効化するか

`/clear` や compact は新しい session_id を発行しつつペインは生き続ける。
座標で消すと生存中の会話を無効化しうる。

### なぜ畳んでから rank を取るか

マップは追記のみなので、同じ枠に世代が溜まる（`/clear` や resume ごとに
新しい session_id が発行される）。畳む前に並べると、世代違いの記録が
別ペインの枠を埋めてしまう。**この順序を逆にすると静かに誤動作する。**

### なぜ hook stdin の `.cwd` ではなく `pane_current_path` か

resurrectが保存・復元するのは `pane_current_path` であり、`restore.sh` が
実行時に参照できるのもそちら。実測では両者は一致したが、Claude Code側の
cwd概念と乖離する可能性を避けた。

## 実測で確認した事実

推測ではなく実機で確認した挙動。修正時の前提として使える。

| 項目 | 結果 |
|---|---|
| hookへの `TMUX_PANE` 継承 | される（`%0` を取得できた） |
| hook stdin | `session_id` / `cwd` / `source` / `reason` を含む |
| `tmux kill-pane` でSessionEnd | **発火する**（`reason=other`） |
| `/clear` でSessionEnd | **発火しない** |
| `claude --session-id <既存UUID>` | `already in use` エラー。**再開には使えない** |
| `claude -r <存在しないUUID>` | 終了コード **1**（`-p` 有無どちらも） |
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
| 会話が削除済み（`-r` が失敗） | `claude -c`（終了コード1でフォールバック） |

## 既知の制約

### tombstoneが付かないケース

`wsl --shutdown` はVMを即停止するためhookが走らない。この場合は記録が
丸ごと残り全ペインが復元対象になる。**これは意図した挙動**（意図せず
落ちた場合は全部戻したい）。意図的に閉じた場合だけ間引かれる。

### 同一パスでペインを増やした場合

記録が無いrankは `claude -c` になる。害はない。

### マップの肥大

`record.sh` が2000行を超えたら末尾1000行に切る。末尾が最新なので
latest-winsの探索順序は壊れない。

## 修正時の検証手順

`@resurrect-processes` の書式や引き当てロジックを変えたら、最低この4ケースを
確認する。スタブの `claude` をPATHに置けば実際に起動せずに検証できる。

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
| 同一パス2ペイン、片方をtombstone | 残ったペインが**自分の**会話を引く |
| 同一パスでpane_indexがズレた | パスが同じなら正しい会話を引く |
| 全会話をtombstone | 全ペイン `claude -c` |

### 検証時の注意

- **UUIDは16進数のみ**。`tttttttt-...` のようなダミーは正規表現で弾かれる
  （これで一度テストが空振りした）
- `TMUX_PANE` は明示的に渡す。未設定だと現在のペインを見てしまう
- 環境変数の汚染に注意。`export` した `CLAUDE_PANE_SESSION_MAP` が
  残っていると意図しないマップを読む

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

## continuum自動保存の注意（別件だが関連）

`modules/tmux.nix` の `status-right` には continuum の保存フックを
**明示的に埋め込んでいる**。

```nix
set -g status-right "#(${pkgs.tmuxPlugins.continuum}/share/.../continuum_save.sh)#{E:@catppuccin_...}"
```

continuumは本来プラグイン読み込み時に `status-right` の先頭へこれを挿入するが、
Home Managerは常にプラグインの `run-shell` を `extraConfig` より先に出力するため、
`extraConfig` 側の `set -g status-right` が後から上書きしてフックを消す。

復元は別経路（バックグラウンド）で動くので、**復元は動くのに保存だけ止まる**
という非対称な症状になる（古いスナップショットしか戻らない）。

`status-right` を編集するときはこのトークンを消さないこと。パスは `pkgs` 経由で
解決しているのでプラグイン更新時も追従する（ハッシュ直書きは禁止）。
