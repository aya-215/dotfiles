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
| 応答の完了を検知し、その応答テキストを得る | `on('turn.complete')` の `e.answer`（サブエージェントのターンは `e.agentId` が入る） |
| 自分のプロンプトを集める | `on('prompt.submit')` の `e.text`（`e.origin.kind === 'composer'` のものだけ） |
| 名前を生成する | `$.model.complete({ model: "haiku", prompt })` |
| 名前・色を付ける | `$.command.run({ command: "rename" \| "color", args })`（手で打つのと同じ扱い。セッションが idle になってから実行される） |
| 手動の `/rename` を検知する | `on('command.run', { command: 'rename' })` で `e.origin` が自 plugin 以外のもの |
| hook の外で処理を走らせる | `$.clock.after(0, fn)` |
| `/clear` を検知する | `on('session.end')` の `e.reason === 'clear'` |
| セッション中の値 | `$.state`（hot reload でも残る） |
| セッションをまたぐ値 | `$.store` |

色の候補は `/color` が受け付ける8色（red, blue, green, yellow, purple, orange, pink, cyan）を mod に固定で持つ。
`$.command.list()` が返す `CommandInfo` には `argumentHint` が無く、実行時には取れないため（`claude -p "/color nosuchcolor"` の出力で確認）。

`$.command.run` は「ターンが待っている hook の中」では拒否され、`session.start` は最初のプロンプト前に待たれる。
そのため `/color` `/rename` と Haiku 呼び出しは hook の中で await せず、`$.clock.after(0, ...)` で hook の外に出して実行する。

mod API は EARLY ACCESS であり、本体の更新で変わりうる。

## 動作

### 起動時（`session.start`）

1. `e.isInteractive` が false なら何もしない（`claude -p` の要約セッション等を除外）
2. `$.state` に割り当て済みの色があれば何もしない（hot reload での再発火対策）
3. `$.store` の `nextColorIndex` を読み、8色から1色選ぶ。`nextColorIndex` を1進めて保存する
   - 続けて起動したセッションどうしで色がかぶらないようにするための順送り。8を超えたら先頭に戻る
   - ほぼ同時に起動した2セッションが同じ色になることはありうる（許容する）
4. 割り当てた色と「対象セッションである」ことを `$.state` に記録する
5. `$.clock.after(0, ...)` で `/color <色>` を実行する

`prompt.submit` `turn.complete` も、`$.state` に「対象セッション」の記録が無ければ何もしない。

### 命名（`turn.complete`）

- 対象: `e.reason === 'answer'` かつ `e.agentId` が無い（メインスレッドの）ターンのみ
- 回数: 応答が完了したターンを数え、1回目と、以後5ターンごと（6, 11, 16, …回目）に命名する
- 手動で命名済み（`$.state.manualName === true`）なら何もしない
- 入力:
  - そのセッションの自分のプロンプト履歴（`prompt.submit` で `$.state` に蓄積。新しい順に合計4,000文字まで）
  - 直近の応答テキストの先頭1,000文字
  - 現在の名前（自動で付けたもの。未命名なら空）
- プロンプト: 「作業内容を表す日本語の名前を15文字以内で1つだけ出力。現在の名前がまだ合っていれば、それをそのまま出力」
- 出力の後処理: 前後の空白・引用符・改行以降を除去し、15文字を超える分は切り詰める
- 結果が現在の名前と同じなら何もしない。違えば `/rename <名前>` を実行し、`$.state` の現在の名前を更新する
- 命名処理は応答をブロックしない（`$.clock.after(0, ...)` で hook の外で実行する）

### 手動の `/rename`

- `command.run` で `command === 'rename'` かつ `e.origin` が自 plugin でないものを検知したら、`$.state` の手動フラグを立てる
- 以後そのセッションでは自動命名をしない

### `/clear`

- `session.end` で `e.reason === 'clear'` なら、ターン数・プロンプト履歴・現在の名前・手動フラグをリセットする（色はそのまま）
- 次の応答完了が再び「1回目」になり、新しい会話の内容で命名し直す

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
├── hooks/register.ts            # hook の登録（薄いつなぎ）
├── hooks/naming.ts              # 純粋関数（状態遷移・命名タイミング判定・出力の後処理・色の選択）
├── tests/*.test.ts              # claude plugin test 用
├── tsconfig.json                # tsc -p 用（型ファイル冒頭の推奨設定）
├── types/index.d.ts             # $.state の型定義（PluginState）
└── .gitignore                   # 本体が書き出す .claude-plugin/types/ を除外
```

配布は `~/.claude/settings.json`（= dotfiles の `.claude-global/settings.json`）の `env` に
`CLAUDE_CODE_PLUGIN_DIRS=/home/aya/.dotfiles/.claude-global/mods/session-autoname` を書いて行う。
`${CLAUDE_DEV_MODS_DIR}` はセッションごとの hot reload 許可が要り、常設の読み込みには向かないため使わない。

## テスト

`claude plugin test` で以下を確認する。

1. 命名は応答完了1回目と以後5ターンごとにだけ走る
2. `reason` が `answer` 以外のターン、サブエージェントのターンは数えない
3. 手動 `/rename` の後は自動命名しない。自 plugin が実行した `/rename` では止まらない
4. 起動のたびに色が順送りされ、hot reload の再発火では再割り当てしない
5. `isInteractive: false` のセッションでは、色・命名・プロンプト収集のどれもしない
6. `composer` 以外から来たプロンプト（タスク通知等）は命名の材料にしない
7. Haiku の失敗・空応答で名前を変えない
8. 出力の後処理（引用符・改行の除去、15文字の切り詰め、現在の名前と同じなら何もしない）
9. `/clear` の後は1回目から数え直す
10. `/color` `/rename` は hook が返ったあとに実行される（hook の中で await しない）

加えて `claude plugin validate` と `tsc -p` が通ること。
最後に、新しく起動したセッションで実機確認する（テストキットは本体の代役なので、以下は実機でしか分からない）。

- 縦分割で2〜3セッションを並べて、名前と色の見え方
- 手で打った `/rename` が `command.run` に `origin.kind === 'composer'` で届き、自動命名が止まること
- 引数なしの `/rename` が何をするか（本体が自動で名前を付けるなら、その旨をユーザーに伝える）
