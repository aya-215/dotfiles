# TODO リスト（todo.md）

tmux からワンキーで開く、markdown 1ファイルの雑メモ用 TODO リスト。
窓の管理は tmux、編集は Neovim、データはプレーンな markdown、と役割を分けている。

## 開き方

| 操作 | 動き |
|---|---|
| `C-q t`（tmux prefix + t） | ポップアップ（中央 60%×70%）で `~/memo/todo.md` を nvim で開く |

Neovim 側から開く導線は意図的に持たない（tmux のどこからでも同じキーで開けることを優先）。
ポップアップは `-E` 付きなので nvim を終了すればそのまま消える。

## ファイル形式

```markdown
# TODO

## 確認待ち
1. 方針を決める（PR が2本） [policy epc#1202]
   A まとめる★ / B 分ける
   回答:

## やる
- [ ] 今動けるタスク [epc#1163](https://github.com/...) — next: N1,N2 を直して push
- [ ] リンクの無いタスク

## 待ち
- [ ] 相手の返答や別作業の完了を待っているタスク

## 完了
- [x] 終わったタスク (done: 2026-11-10)
```

- セクション順は `## 確認待ち` → `## やる` → `## 待ち` → `## 完了`。旧形式（見出し無しの未完了 → `## 待ち` → `## 完了`）は `scripts/todo-ai/migrate.py` で一度だけ変換する（`docs/todo-ai.md`）
- `- [ ]` / `- [x]` 行だけを「タスク」として扱う。末尾のリンク `[<key>](<url>)` と ` — next: ` は任意
- 待ちのタスクもマーカーは `- [ ]` のまま（セクションで区別する）
- `## 確認待ち` は AI が書く問いの欄。人は `回答:` の後ろだけ書く（`docs/todo-ai.md`）
- 見出しが無い場合は、必要になった時点で自動生成する（`## 待ち` は `## 完了` の直前、`## 完了` は末尾）
- 新規ファイルなら上記の見出し4つの骨組みを自動生成する
- 完了にすると末尾に ` (done: YYYY-MM-DD)` が付き、未完了に戻すと外れる。30日を過ぎた完了行は apply が `~/memo/todo-archive/YYYY-MM.md` へ移す

nvim の操作は押した行だけを動かすが、todo.md 全体は `scripts/todo-ai/apply.py` も書き換える（AI・GitHub 同期の変更、確認待ちの更新、アーカイブ）。
人の行の文言・完了は apply が守る。仕組みは `docs/todo-ai.md`。

保存先は `~/memo/`（雑メモ `memo/quick` と同じ置き場、`docs/memo-quick.md`）。nb は経由しない。

`~/memo` は git リポジトリで、**`q` で閉じるとき・Neovim 終了時に `todo.md` だけを自動コミット**する
（`<CR>`/`<Tab>` ごとの保存ではコミットしない）。同じディレクトリの他ファイルは add しない。
人のコミットは `todo: YYYY-MM-DD HH:MM`、AI と同期は `todo(ai): ` / `todo(sync): `。
当初は `~/.nb/notes/todo.md` に置いていたが、nb は nb コマンド実行時にしかコミットしないため
nvim から直接書いた変更が長く未コミットのまま残る問題があり、移動した。

## バッファ内キー（`todo.md` を開いたときだけ有効）

| キー | 動き |
|---|---|
| `<CR>` | `[ ]`⇄`[x]` を切り替えて移動。未完了/待ち → `## 完了` の直下（完了日を付ける）、完了 → `## やる` の末尾（完了日を外す） |
| `<Tab>` | 未完了 ⇄ `## 待ち` を往復。移動先の末尾に付く。完了済みの行では何もしない |
| `o` / `O` | `- [ ] ` 付きの新規行を開いて挿入モード（`## 確認待ち`・`## 完了` エリアでは素の `o`/`O`） |
| `q` | 保存して閉じ、変更があれば git commit |
| `dd` 等 | 通常の vim 操作。vim-auto-save が自動保存する |

軸は直交している: `<CR>` は「終わったか」、`<Tab>` は「今動けるか」。
待ちの行で `<CR>` を押せばそのまま完了へ行く。

すべての移動操作で、カーソルは移動した項目に追従する。移動のたびに即保存される。

## 表示（ファイルの中身は変えない）

`todo.md` を開いた窓だけ `conceallevel=2`・`concealcursor=`（空）にし、extmark の conceal で次を隠す。カーソル行には付けないので、カーソルを置いた行は生の文字が見え、そのまま編集できる。

- リンク `[text](url)` は `text` だけ見せる（AI の key のリンクも人の行のリンクも）
- 確認待ちの問いの末尾タグ ` [<kind> <ref>]` を隠す
- タスク行の ` — next: ` を ` → ` で見せる

render-markdown が通常モードで `conceallevel` を 3 にし conceal の代わりの文字（cchar）が出なくなるため、→ はインラインの仮想文字で出している。仮想文字は conceal と違い `conceallevel=0` でも出るので、窓の `conceallevel` が 0 の間は付けない（モードの切り替え・`conceallevel` の変更で付け直す）。
隠した文字も折り返しの幅には数えられる（Neovim の挙動）ので、長い URL のある行は折り返し位置がずれることがある。行を短くするのは `/todo` の題・next の書き方（`docs/todo-ai.md`）の役割。

## 安全装置

- `<CR>` / `<Tab>` の結果で**非空行が減る変更は反映しない**（移動操作で行が減ることは無いため、減る = バグと断定できる）。検出時はエラー通知だけ出して何もしない
- nvim で todo.md を開いている間は `~/memo/.todo.lock` に nvim の PID を置く（閉じてコミットした後に消す）。apply はこれがあると書かずにスキップし、次回に回す。nvim が落ちて残ったロックは、PID が生きていなければ無視して消す
- テスト・検証は `TODO_MD_PATH` 環境変数でパスを差し替え、実ファイルには触らない

## 実装

| ファイル | 役割 |
|---|---|
| `config/nvim/lua/todo/core.lua` | 行操作の純関数（パース・セクション検索・移動・表示で隠す範囲 `conceal_ranges`）。バッファに触らない |
| `config/nvim/lua/todo/init.lua` | `BufRead`/`BufNewFile` でバッファローカルのキーと表示の conceal を付ける薄い層。`init.lua` から `require("todo").setup()` |
| `config/nvim/tests/todo_core_spec.lua` | core のテスト |
| `modules/tmux.nix` | `bind t display-popup ...` |

テスト実行:

```sh
nvim --headless -u NONE -l config/nvim/tests/todo_core_spec.lua
```

対話的な挙動を確かめたいときは、実ファイルのコピーに対して `TODO_MD_PATH` を指定して開く:

```sh
cp ~/memo/todo.md /tmp/todo_test.md
TODO_MD_PATH=/tmp/todo_test.md nvim /tmp/todo_test.md
```

## やっていないこと

- dashboard への件数表示
- nb `tasks` ノートブック（`nb todos`）との連携
- Neovim 内からのトグル表示（サイドバー/フロート）。一度実装したが使わないので削除した
