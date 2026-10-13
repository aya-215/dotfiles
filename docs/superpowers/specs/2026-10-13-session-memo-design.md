# セッション作業メモ mod 設計

## 目的

Claude Code の会話ごとに、自分用の作業メモ（数行の箇条書き）を Claude の画面の中で書き留められるようにする。
メモの先頭1件はプロンプトの上に常に出し、全件はパネルを開いて確認・編集する。

## 前提となる決定

- 書くのは自分。Claude はメモを書き換えない（`/note ○○` で足した行は会話に残り、Claude が読めてよい）
- 使い捨て。会話にくっつき、`/clear`、同じセッション内の `/resume`、終了で消える。`claude --resume` で戻ったら空から始まる
- 編集は Claude の画面の中だけ（パネル）。外部エディタ（nvim）経由の編集は今回は作らない
- 並べた Claude の見分けは自動命名 mod（`session-autoname`）の役目。この mod は見分けを目的にしない

## スコープ外

- resume で戻ったときのメモの復元
- 複数行テキストの一括編集、nvim 連携（プロンプト欄経由の `ctrl+k g` 案は候補として保留）
- メモの並べ替えのうち「先頭へ移す」以外の操作

## 画面

### 帯（AbovePrompt、常に表示）

- メモが1件以上あるとき、`📝 <先頭のメモ>（+N）` の1行を出す。N は先頭以外の件数で、0なら `（+N）` を付けない
- 1行に収まらない分は、メモ本文の側を切り詰める（`Text` の `wrap="truncate"`。全角の幅は本体が数える）。`（+N）` は切らずに残す
- メモが0件、またはアンケートが帯を使っている（`e.props.hasSurvey`）ときは何も描かず `next(e)` に任せる

### パネル（Pane、`/note` で開閉）

- `$.ui.open({ id: 'memo', title: 'Memo', focus: true, closeOnEscape: true, rows })` で開く。開いた時点でキーボードがパネルの入力欄に移り、矢印と Tab で行・入力欄を移動、Esc で閉じる
- 各行は1つのボタン（`row:<i>`）。矢印で1行ずつ止まる。長いメモは折り返して全文を出す
- 中身（行を選んでいるとき）:

```
 1. 認証まわりは触らんとく
 2. あとでテスト追加          ← 選択中
 e:編集 t:先頭へ x:削除
 memo> ____________________  [追加]
```

| 操作 | 動き |
|---|---|
| 入力欄で Enter | 空白だけでなければ末尾に追加し、入力欄を空に戻す（続けて書ける） |
| 行で Enter・行をクリック | そのメモを入力欄に読み込み編集モードにする。編集中は入力欄の横に `[取消]` を出す |
| 行を選んで `e` | 同上（選んだ行を編集） |
| 行を選んで `t` | 選んだメモを先頭へ移し、選択も先頭へ付いていく |
| 行を選んで `x` | 選んだメモを消す。選択は同じ位置（末尾なら1つ上）に残る。編集中のメモなら編集モードも抜ける |
| 編集モードで Enter | そのメモを書き換える（空白だけなら書き換えない）。編集モードを抜ける |
| `[取消]` | 書き換えずに編集モードを抜ける |

- 文字キー（`e` `t` `x`）はボタンの `hotkey` で受ける。同じ文字は1サイトに1つしか置けないため、行ごとではなく「選んだ行への操作」として1組だけ置く
- どの行を選んでいるかは `ui.focus`（`requestId: 'memo'`）で輪の移動を見て `$.state` に持つ。入力欄に輪がある間は操作ボタン（と hotkey）を描かず、入力中の文字が操作にならないようにする。代わりに「↑↓ で行を選ぶと e:編集 t:先頭へ x:削除」の案内を出す
- Esc は `closeOnEscape` でパネルを閉じる。編集中に閉じた場合は書き換えずに捨てる（次に開いたときは編集モードではない）
- メモが0件のときは「メモはまだありません」と入力欄だけを出す

## コマンド

コマンド名は `note`（`/memo` は本体の `/memory` と打ち始めが同じで補完が紛らわしいため）。パネルの id・見出し・plugin 名は `memo` のまま。

`session.start` で `$.command.register({ name: 'note', immediate: true, ... })` し、`command.run` hook（`{ command: 'note' }`）で答える。
`immediate` により、Claude の作業中（ターン実行中）に打ってもターン終了を待たずにすぐ動く。hook はターンの状態に依存しない。

| 打つもの | 動き | 会話に残る返事 |
|---|---|---|
| `/note ○○` | 末尾に追加 | `メモを追加（N件）` |
| `/note`（引数なし） | パネルが開いていれば閉じ、閉じていれば開く | `メモを開いた` / `メモを閉じた` |

## 状態

- `$.state`（plugin `session-memo`）に、メモの配列、編集中のメモの位置、選んでいる行の位置を持つ（入力欄を空に戻す版番号は持たない。value の再描画で空に戻るかは実機で確かめる）
- `session.end` で `reason` が `clear` か `resume` なら、メモと編集状態を空にする
- `$.store` は使わない（セッションをまたいで残さない）

## 構成

ソースは dotfiles に置く: `.claude-global/mods/session-memo/`

```
session-memo/
├── .claude-plugin/plugin.json   # name: session-memo, "types": "./types/index.d.ts"
├── hooks/hooks.json             # { "modules": ["./register.tsx"] }
├── hooks/register.tsx           # hook の登録と描画（薄いつなぎ）
├── hooks/memo.ts                # 純粋関数（追加・書き換え・先頭へ・削除・帯の1行の生成）
├── tests/*.test.ts(x)           # claude plugin test 用
├── tsconfig.json                # 型ファイル冒頭の推奨設定
├── types/index.d.ts             # $.state の型定義（PluginState）
└── .gitignore                   # 本体が書き出す .claude-plugin/types/ を除外
```

配布は `.claude-global/settings.json` の `env.CLAUDE_CODE_PLUGIN_DIRS` に `:` 区切りで
`/home/aya/.dotfiles/.claude-global/mods/session-memo` を足す。
`settings.json` にあるユーザーの未コミット変更は巻き込まず、自分の変更だけをコミットする。

## テスト

`claude plugin test` で以下を確認する。画面のテストは `$.ui.mount` で terminal と desktop の両方に対して行う。

1. 純粋関数: 追加（空白だけは無視）・書き換え・先頭へ移動・削除・全消去
2. 帯の1行: 0件で描かない、1件で `（+N）` なし、複数件で `（+N）`、本文が `wrap="truncate"` で `（+N）` は別要素、アンケート中は描かない
3. パネル: 入力欄 Enter で追加され欄が空に戻る、行を押すと編集 → Enter で書き換え、`[取消]` で元のまま、行を選ぶまで操作ボタンを出さない、選んだ行に `e` `t` `x` が効く
4. コマンド: `/note ○○` で追加、引数なし `/note` で開閉が切り替わる、`immediate: true` で登録される
5. `session.end` の `clear` / `resume` でメモが消える

加えて `claude plugin validate` と `tsc -p` が通ること。
最後に、新しく起動したセッションを縦分割で並べて実機確認する（帯の見え方、狭い幅でのパネルの開き方、キー操作）。
