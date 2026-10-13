# session-memo

会話ごとの作業メモ（自分が書く数行の箇条書き）を、Claude の画面の中で扱う。
Claude はメモを書き換えない。使い捨てで、会話が変わると消える。

## 使い方

| 操作 | 動き |
|---|---|
| `/note ○○` | メモを末尾に足す。Claude の作業中でもすぐ入る |
| `/note`（引数なし） | パネルを開く。開いていれば閉じる |
| パネルの入力欄で Enter | メモを足す。入力欄は空に戻るので続けて書ける |
| 矢印で行を選んで `e` / 行で Enter / 行をクリック | そのメモを入力欄に読み込んで編集。Enter で書き換え、`[取消]` でやめる |
| 行を選んで `t` | そのメモを先頭へ（先頭のメモは帯に出る） |
| 行を選んで `x` | そのメモを消す |
| Esc | パネルを閉じる |

- プロンプトの上の帯に、先頭のメモと残りの件数を `📝 先頭のメモ（+2）` の1行で常に出す。0件なら出さない
- `/clear`・同じセッション内の `/resume`・終了で消える。`claude --resume` で戻ったら空から始まる
- `/note ○○` で足したメモは会話に残るので Claude も読める。パネルから足したメモは会話に残らない

## カスタマイズ

| 変えたいこと | 場所 |
|---|---|
| コマンド名（`/note`） | `hooks/register.tsx` の `session.start` の `name` と、`command.run` の `{ command: 'note' }`。`tests/command.test.tsx` も合わせる |
| コマンドの説明・引数の案内 | `hooks/register.tsx` の `description`・`argumentHint` |
| 作業中でもすぐ動くか | `hooks/register.tsx` の `immediate: true` |
| パネルの文字キー（`e` `t` `x`） | `hooks/register.tsx` の各ボタンの `hotkey` と `label`、案内文「↑↓ で行を選ぶと…」 |
| 帯の見た目（📝・`（+N）`） | `hooks/memo.ts` の `bandParts`、描画は `hooks/register.tsx` の `AbovePrompt` |
| パネルの見出し・高さ | `hooks/register.tsx` の `$.ui.open` の `title`・`rows`（件数+3、最大20） |
| `/clear` でも残したい | `hooks/register.tsx` の `session.end` hook の条件から `clear` を外す |
| 足すときの整形（改行を空白にまとめる等） | `hooks/memo.ts` の `normalize` |

## 仕組み

- メモの操作（足す・書き換え・先頭へ・消す・選んだ行への操作）は、すべて `hooks/memo.ts` の純粋関数。`hooks/register.tsx` は描画とコマンド・イベントのつなぎだけ
- 状態は `$.state`（そのセッションだけ）に、メモの配列・編集中の位置・選んでいる行の位置を持つ。`$.store` は使わない
- どの行を選んでいるかは、パネルのフォーカスの輪の移動（`ui.focus`）を見て追う。入力欄に輪がある間は `e` `t` `x` のボタン自体を描かないので、打った文字は入力になる
- ボタンは押したときに、その位置のメモが描いた時点と同じかを確かめる（二度押しで別のメモに効かないように）
- パネルの地が黒いのは本体が塗っているため（mod からは変えられない）

## 資料

- 設計: `docs/superpowers/specs/2026-10-13-session-memo-design.md`
- 実装計画: `docs/superpowers/plans/2026-10-13-session-memo.md`（計画後に、コマンド名の変更と文字キー操作への変更が入っている。今の動きはこの README が正）
- テスト: `tests/memo.test.ts`（純粋関数）、`tests/ui.test.tsx`（帯とパネル）、`tests/command.test.tsx`（`/note` と会話リセット）
