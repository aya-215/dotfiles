# session-autoname

対話セッションに、プロンプト欄の色と、会話内容から作った名前を自動で付ける。
縦分割で並べた Claude を見分けるため。

## 動き

| きっかけ | 動き |
|---|---|
| 起動時 | `/color` で8色を順送りに付ける（起動のたびに次の色）。`claude -p` では何もしない |
| 応答1回目と、以後5ターンごと | Haiku で日本語15文字以内の名前を作り、`/rename` で付ける。今の名前がまだ合っていれば変えない |
| 手で `/rename` したとき | そのセッションでは自動命名を止める |
| `/clear` | 数え直して、新しい会話の内容で付け直す |
| resume で戻ったとき | 戻った会話に名前があれば自動命名しない（手で付けた名前を上書きしないため） |
| 命名に失敗したとき | 名前は変えず、ステータス行に10秒だけ出す |

サブエージェントのターン・中断したターンは数えない。命名の材料にするのは、自分が打ったプロンプト（スラッシュコマンド・タスク通知を除く）と直近の応答の冒頭だけ。

## カスタマイズ

| 変えたいこと | 場所 |
|---|---|
| 名前を見直す間隔（ターン数） | `hooks/naming.ts` の `RENAME_EVERY` |
| 名前の最大文字数 | `hooks/naming.ts` の `NAME_MAX_CHARS` |
| 使う色と順番 | `hooks/naming.ts` の `COLORS`（`/color` が受け付ける色だけ。`claude -p "/color x"` で一覧が出る）。型は `types/index.d.ts` の `Color` も合わせる |
| 命名の材料の量 | `hooks/naming.ts` の `PROMPTS_MAX_CHARS`（プロンプト履歴）・`ANSWER_MAX_CHARS`（応答の冒頭） |
| Haiku への指示文 | `hooks/naming.ts` の `buildPrompt` |
| 使うモデル・上限トークン・タイムアウト | `hooks/register.ts` の `nameSession` 内の `$.model.complete` |
| 失敗表示を出す時間 | `hooks/register.ts` の `STATUS_MS` |
| resume で戻ったときも付け直したい | `hooks/register.ts` の `classic.SessionStart` hook で `hasTitle` を見ないようにする |
| 色を付けない | `hooks/register.ts` の `session.start` hook の `/color` 実行を外す |

## 仕組み

- 判断（いつ命名するか、色の選び方、Haiku の出力の後処理など）はすべて `hooks/naming.ts` の純粋関数。`hooks/register.ts` は hook の登録と `$` の呼び出しだけ
- `/color` `/rename` と Haiku の呼び出しは、hook の中で待たず `$.clock.after(0, ...)` で hook の外で実行する（hook の中で `$.command.run` を待つと拒否される）
- 次の色の番号は `$.store`（セッションをまたいで残る）の `nextColorIndex`。それ以外の状態は `$.state`（そのセッションだけ）
- 自分が実行した `/rename` と手で打った `/rename` は、`command.run` の `origin` で見分ける

## 資料

- 設計: `docs/superpowers/specs/2026-10-09-session-autoname-design.md`
- 実装計画: `docs/superpowers/plans/2026-10-09-session-autoname.md`
- テスト: `tests/naming.test.ts`（純粋関数）、`tests/register.test.ts`（hook を通した動き）
