# セッション自動命名 mod 設計

## 目的

画面を縦に分割して複数の Claude Code セッションを並べたとき、どのセッションが何をしているかを一目で区別できるようにする。
手で `/rename` `/color` を毎回打つ手間をなくすため、名前と色を mod が自動で付ける。

- 名前: 会話内容から定期的に生成し、本体の `/rename` で付ける
- 色: 起動時に本体の `/color` でセッションごとに違う色を付ける

## スコープ外

- セッションごとの作業メモ（別の mod として後で設計する）
- 名前・色の表示方法の変更（本体の表示をそのまま使う）

## 前提（本体 2.1.295 の mod API で確認済み）

| 用途 | API |
|---|---|
| 応答の完了を検知し、その応答テキストを得る | `on('turn.complete')` で `await next(e)` の戻り値 `{ text }` |
| 自分のプロンプトを集める | `on('prompt.submit')` の `e.text` |
| 名前を生成する | `$.model.complete({ model: "haiku", prompt })` |
| 名前・色を付ける | `$.command.run({ command: "rename" \| "color", args })`（手で打つのと同じ扱い。セッションが idle になってから実行される） |
| 手動の `/rename` を検知する | `on('command.run', { command: 'rename' })` で `e.origin` が自 plugin 以外のもの |
| 色の候補を得る | `$.command.list()` の `color` の `argumentHint` |
| セッション中の値 | `$.state`（hot reload でも残る） |
| セッションをまたぐ値 | `$.store` |

mod API は EARLY ACCESS であり、本体の更新で変わりうる。

## 動作

### 起動時（`session.start`）

1. `e.isInteractive` が false なら何もしない（`claude -p` の要約セッション等を除外）
2. `$.state` に割り当て済みの色があれば何もしない（hot reload での再発火対策）
3. `$.store` の `nextColorIndex` を読み、`/color` の候補から1色選んで `/color <色>` を実行する。`nextColorIndex` を1進めて保存する
   - 続けて起動したセッションどうしで色がかぶらないようにするための順送り。候補数を超えたら先頭に戻る
   - 候補に `default` が含まれる場合は除外する
4. 割り当てた色を `$.state` に記録する

### 命名（`turn.complete`）

- 対象: `e.reason === 'answer'` のターンのみ
- 回数: 応答が完了したターンを数え、1回目と、以後5ターンごと（6, 11, 16, …回目）に命名する
- 手動で命名済み（`$.state.manualName === true`）なら何もしない
- 入力:
  - そのセッションの自分のプロンプト履歴（`prompt.submit` で `$.state` に蓄積。新しい順に合計4,000文字まで）
  - 直近の応答テキストの先頭1,000文字
  - 現在の名前（自動で付けたもの。未命名なら空）
- プロンプト: 「作業内容を表す日本語の名前を15文字以内で1つだけ出力。現在の名前がまだ合っていれば、それをそのまま出力」
- 出力の後処理: 前後の空白・引用符・改行以降を除去し、15文字を超える分は切り詰める
- 結果が現在の名前と同じなら何もしない。違えば `/rename <名前>` を実行し、`$.state` の現在の名前を更新する
- 命名処理は応答をブロックしない（`next(e)` の結果を返してから非同期に実行する）

### 手動の `/rename`

- `command.run` で `command === 'rename'` かつ `e.origin` が自 plugin でないものを検知したら、`$.state.manualName = true` にする
- 以後そのセッションでは自動命名をしない

### 失敗時

- Haiku の呼び出しが失敗した、または空の応答だった場合は、名前を変えず次の周期に回す
- 失敗は `$.ui.status` に短く出すだけで、トーストや会話への割り込みはしない
- `/rename` `/color` の実行が拒否された場合も同様に status に出して終える

## ファイル構成

ソースは dotfiles に置く: `.claude-global/mods/session-autoname/`

```
session-autoname/
├── .claude-plugin/plugin.json   # name, version, description, "types": "./types/index.d.ts"
├── hooks/hooks.json             # { "modules": ["./register.ts"] }
├── hooks/register.ts            # 本体
├── hooks/naming.ts              # 純粋関数（命名タイミング判定・出力の後処理・色の選択）
├── hooks/*.test.ts              # claude plugin test 用
└── types/index.d.ts             # $.state の型定義（PluginState）
```

本体が読む mod フォルダ（`${CLAUDE_DEV_MODS_DIR}`）へは、既存の hooks・skills と同様に `~/.claude` 側からシンボリックリンクで配る。
実際のパスは `plugin-authoring` スキル読み込み時に確定させる。リンクで配れない場合は `CLAUDE_CODE_PLUGIN_DIRS` で dotfiles のフォルダを指す。

## テスト

`claude plugin test` で以下を確認する。

1. 命名は応答完了1回目と以後5ターンごとにだけ走る
2. `reason` が `answer` 以外のターンは数えない
3. 手動 `/rename` の後は自動命名しない。自 plugin が実行した `/rename` では止まらない
4. 起動のたびに色が順送りされ、hot reload の再発火では再割り当てしない
5. `isInteractive: false` では何もしない
6. Haiku の失敗・空応答で名前を変えない
7. 出力の後処理（引用符・改行の除去、15文字の切り詰め、現在の名前と同じなら何もしない）

加えて `claude plugin validate` と `tsc -p` が通ること。
最後に、縦分割で2〜3セッションを並べて、名前と色の見え方を実機で確認する。
