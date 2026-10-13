# session-autoname

対話セッションに、プロンプト欄の色と、会話内容から作った名前を自動で付ける。
縦分割で並べた Claude を見分けるため。

## 動き

| きっかけ | 動き |
|---|---|
| 起動時 | `/color` で8色を順送りに付ける（起動のたびに次の色）。`claude -p` では何もしない |
| 応答1回目と、以後5ターンごと | Haiku に「15文字以内」で名前を頼み、`<name>…</name>` の中身を `/rename` で付ける（表示は20文字まで、超えた分は切る）。今の名前がまだ合っていれば変えない。形式違反（タグ無し・文章になっている等）なら理由を添えて1回だけ頼み直す |
| 手で `/rename` したとき | そのセッションでは自動命名を止める |
| `/clear` | 数え直して、新しい会話の内容で付け直す |
| resume で戻ったとき | 戻った会話に名前があれば自動命名しない（手で付けた名前を上書きしないため） |
| 命名に失敗したとき（Haiku のエラー、頼み直しても形式違反） | 名前は変えず、ステータス行に10秒だけ出す |

サブエージェントのターン・中断したターンは数えない。命名の材料にするのは、自分が打ったプロンプト（スラッシュコマンド・タスク通知を除く）と直近の応答の冒頭だけ。

## カスタマイズ

| 変えたいこと | 場所 |
|---|---|
| 名前を見直す間隔（ターン数） | `hooks/naming.ts` の `RENAME_EVERY` |
| Haiku に頼む文字数 | `hooks/naming.ts` の `NAME_PROMPT_CHARS`（15） |
| 表示する最大文字数（超えたら切る） | `hooks/naming.ts` の `NAME_MAX_CHARS`（20） |
| 使う色と順番 | `hooks/naming.ts` の `COLORS`（`/color` が受け付ける色だけ。`claude -p "/color x"` で一覧が出る）。型は `types/index.d.ts` の `Color` も合わせる |
| 命名の材料の量 | `hooks/naming.ts` の `PROMPTS_MAX_CHARS`（プロンプト履歴）・`ANSWER_MAX_CHARS`（応答の冒頭） |
| Haiku への指示（役割・ルール・良い例/悪い例） | `hooks/naming.ts` の `buildSystem`（system prompt） |
| Haiku に渡す素材の形 | `hooks/naming.ts` の `buildPrompt`（`<current>` `<prompts>` `<answer>`） |
| 形式違反の判定 | `hooks/naming.ts` の `judgeReply` |
| 使うモデル・上限トークン・タイムアウト | `hooks/register.ts` の `nameSession` 内の `$.model.complete` |
| 失敗表示を出す時間 | `hooks/register.ts` の `STATUS_MS` |
| resume で戻ったときも付け直したい | `hooks/register.ts` の `classic.SessionStart` hook で `hasTitle` を見ないようにする |
| 色を付けない | `hooks/register.ts` の `session.start` hook の `/color` 実行を外す |

## 仕組み

- 判断（いつ命名するか、色の選び方、Haiku の出力の後処理など）はすべて `hooks/naming.ts` の純粋関数。`hooks/register.ts` は hook の登録と `$` の呼び出しだけ
- `/color` `/rename` と Haiku の呼び出しは、hook の中で待たず `$.clock.after(0, ...)` で hook の外で実行する（hook の中で `$.command.run` を待つと拒否される）
- 次の色の番号は `$.store`（セッションをまたいで残る）の `nextColorIndex`。それ以外の状態は `$.state`（そのセッションだけ）
- 自分が実行した `/rename` と手で打った `/rename` は、`command.run` の `origin` で見分ける
- Haiku の出力は `<name>` タグの中身だけを使う。指示文を変えたら、Haiku に何パターンか投げて形式どおりに返るか確かめる（2026-10-13 に6パターン×2回＝12件すべて形式どおりを確認）

## 資料

- 設計: `docs/superpowers/specs/2026-10-09-session-autoname-design.md`
- 実装計画: `docs/superpowers/plans/2026-10-09-session-autoname.md`
- テスト: `tests/naming.test.ts`（純粋関数）、`tests/register.test.ts`（hook を通した動き）
