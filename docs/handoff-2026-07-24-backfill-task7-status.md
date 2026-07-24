# 引き継ぎメモ: セッション要約バックフィル Task7（初回実行）の現状

作成: 2026-07-24 / 作業セッション: 263ceef5（実装・調査担当）
ブランチ: `feat/session-summary-backfill`
先行資料: `docs/handoff-2026-07-24-sessionend-rootcause.md`（原因究明）、`docs/superpowers/plans/2026-07-24-session-summary-backfill.md`（実装プラン、Task4-6改訂済み）

---

## 現在の安全状態（即確認可）

- backfill.sh は**実行中プロセスなし**（前回起動分は停止済み）
- crontab は `backfill.sh` の行を `#` で**無効化中**（21:00には発火しない）。nb-sync（30分毎）と fire-daily-review（22:10、今夜の日報）は有効のまま無傷
- `~/.claude/projects/` の jsonl 総数は増えていない（ゴミ自己増殖は止まっている）

```
*/30 * * * * /home/aya/.dotfiles/scripts/nb-sync.sh
10 22 * * * /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh >> /tmp/fire-daily-review-cron.log 2>&1
# [一時無効化 2026-07-24: backfill自己参照ループ修正まで] 0 21 * * * /home/aya/.dotfiles/scripts/claude-summarize/backfill.sh >> ...
```

## 完了済み（Task1〜6、全てレビューApproved・コミット済み）

```
b6f4926 feat: backfill.sh 対象選定(--dry-run)
923bf31 feat: summarize投入経路+flock多重起動ガード
ee30e99 fix: case2厳格化+SESSIONS_ROOT不在可視化
641aaf7 docs: プラン改訂(自己参照ループ欠陥発見を受けて)
d275c5b fix: --no-session-persistence 追加(欠陥X根絶)
0ec6d9e fix: extract.pyでsdk-cli/sdk-py除外(多層防御1段目)+case6既存バグ修正
7e8941d fix: case7 false pass修正(fixture強化)
b2b1222 docs: stale comment修正
b46751e fix: backfill.shでsdk-cli/sdk-py除外(多層防御2段目)
```

### 実証済みの事実（CONFIRMED）
- **自己参照ループの原因**: summarize.sh の `claude -p`（フラグ無し）が要約のたびに新規セッションjsonlを永続化していた。`--no-session-persistence` 付きなら jsonl差分0、無しなら+1（対照実験で実証）。
- **多層防御が機能している**: extract.py・backfill.sh 双方で `entrypoint` が `sdk-cli`/`sdk-py` の時だけ除外、`cli`/欠落は通す実装。46件のdry-run対象を独立検証した結果、sdk混入ゼロを確認。
- **判定ルール（両ファイル共通・変更しないこと）**: 「明示的に sdk-cli/sdk-py の時だけ除外、cli と entrypoint欠落は必ず通す」（安全側=include。欠落を除外にすると既存テストのfixtureが全滅するため）。

## 未完了: Task7（初回バックフィル実行 + cron再有効化）

### 直前に何が起きたか
Task7 Step1-2 を進めるため実データ dry-run したところ、対象が **46件**（プランの見積もり「最大16件・実質約9件」を大きく超過）。一度 414件で自己参照ループを起こした反省から、ユーザーに「中身を実際に見たか」と指摘され、精査した。

### 46件の正体（実データで確定・CONFIRMED）
**「時間経過で増えた」という中間の説明は誤りだった（advisorに指摘され訂正）。** 正しくは「測っている集合が違った」:

| 内訳 | 件数 | 意味 |
|---|---|---|
| **started-but-failed** | 26件 | `~/.local/log/claude-summarize.log` に `summarize start` 記録はあるが、要約に失敗して md が残らなかった（旧ARG_MAXバグ期・見出し不足など） |
| **never-started** | 20件 | SessionEnd 自体が発火しなかった（`docs/handoff-2026-07-24-sessionend-rootcause.md` の「16件」に相当する集合。実測20件で近い値） |
| **合計** | **46件** | backfill は「md無し全部」を拾う設計であり、両方含むのは意図通りの挙動 |

先行handoffの「16件」は **never-started だけ** を見た数字であり、started-but-failed（26件）を含んでいなかったため、比較対象が食い違って見えていた。

検証方法（再現可能）:
```bash
LOG=~/.local/log/claude-summarize.log
grep -oE 'summarize start: [0-9a-f]{8}' "$LOG" | awk '{print $3}' | sort -u > started_all.txt
# backfill --dry-run の各行から sid8 を抽出したファイルと comm -12/-23 で突合
comm -12 final46_sid8.txt started_all.txt | wc -l   # → 26 (started-but-failed)
comm -23 final46_sid8.txt started_all.txt | wc -l   # → 20 (never-started)
```

### ユーザー指摘: 「2種類、性質が違う」（ここで作業中断）
started-but-failed と never-started は**対処すべき性質が異なる**可能性がある——というのがユーザーの最後の指摘。これが次セッションで詰めるべき論点:
- started-but-failed（26件）は「過去に失敗した」もの。今 backfill で拾って良いか？（旧ARG_MAXバグ由来なら今は直っているので正しく要約できるはず）
- never-started（20件）は「SessionEnd非発火」由来。こちらは非graceful終了の日常的attritionなので拾うのが正しい戦略（先行handoffの結論）。
- **両者を同じ46件のリストとして無条件に一括処理してよいか、分けて扱うべきか**は未決定。

### さらに未確認の懸念（中身精査で発覚）
- **直近0〜3時間以内に mtime 更新された jsonl が3件混入**（`3f777557`, `d5b000e9`, `03e232f1`、いずれも ebase-portal-chat / ebase-middleware-mcp）。まだ会話が続いている可能性があり、backfillで要約すると未完成な内容で md が作られるリスク。SessionEndが後で発火すればdedup機構で上書きされるはずだが、一時的に不完全な要約が残る。
- 極小の断片（`ai-title`/`agent-name` のみ、user/assistant行なし）が1件（`07cf0586`）。summarize.sh のガードA（tool0かつ本文200字未満）で弾かれる想定だが未実地検証。
- 「重複に見えた」2組（`202e8e6b`/`cd2d5d89`、`202e8e6b`系のtimestampが同一に見えた件）は調査の結果、**別sidの正当な別ファイル**（resumeセッション由来）と判断。バグではない。

## 追記 2026-07-24（続きセッション 549b3f6f）: 失敗原因を実データ+実測で特定

ユーザー方針: 「SessionEnd非発火は原因明確。バグで止まった方は"どのバグで止まったか確認して直す必要がある"。また失敗する可能性が高いし、そもそも失敗しないのが理想」。
→ backfillで無条件に流す前に、started-but-failed の失敗原因を特定して恒久対策する方針に転換。

### 数字の再締め直し（CONFIRMED）
引き継ぎメモ本文の「started-but-failed 26件」は **ログにstart記録がある集合（成功も含む粗い数字）**。
`~/.local/log/claude-summarize.log` の `discarded` 行で実際に失敗記録が残るのは以下:

| 失敗モード | ユニークsid | うち今もmd無（真の欠損） |
|---|---|---|
| 必須見出し不足 | 17 | 6 |
| claude 実行失敗 | 6 | 2 |
| **合計** | 23 | **8** |

- 失敗23件中15件は後の別機会に md 生成済み（リトライ/再開で救済されていた）。
- **真の欠損は8件のみ**。sid8: 見出し不足=`33c0e4b3 69f54b4d 740a64c6 84989f3e 8f0e42fa b919ffd9`、claude失敗=`57ba7847 e4fbe4e8`。
- 8件とも jsonl 健在、mtime は 7/13〜7/22（全て会話終了済み。進行中疑いは解消）。

### 失敗モード①: claude 実行失敗（2件）= ARG_MAXバグ由来（CONFIRMED・修正済み）
- 因果突合: 失敗日時 `57ba7847`=7/15 14:01、`e4fbe4e8`=7/22 14:43 < stdin化コミット `599f360`=7/24 11:37。→ 旧ARG_MAXバグで確定。
- **実測**: `e4fbe4e8`(1.4MB/713行) を現行 summarize.sh で tmp(SESSIONS_ROOT上書き)向け単発実行 → **7項目揃った valid md 生成成功**（3615B）。
- 結論: stdin化＋MAX_CHARS切り詰めで**修正済み。再実行で確実に直る**。

### 失敗モード②: 必須見出し不足（6件）= ペルソナ継承バグ（CONFIRMED・要恒久対策）
- **真因**: summarize が呼ぶ `claude -p` が、ユーザーの CLAUDE.md/output-style（関西弁＋「不明点は質問」モード）を継承し、要約プロンプトを**会話の続きと誤解して質問返し**していた（「了解やで…どうしますか？」等）。→ 7見出しが出ず discard。
- `--no-session-persistence --settings '{"disableAllHooks":true}'` だけでは **設定ソース・system-prompt までは遮断できていなかった**のが穴。
- **discriminating test（CONFIRMED）**: 同じ `84989f3e` の extract を `--system-prompt '要約ツール。質問するな' --setting-sources ''` の clean config で再実行 → **7項目完璧に生成、質問返し消滅**。→ **ペルソナ継承が支配的主因**であることを確定。
- ⚠️ **訂正（2026-07-24 バックフィル実行時に falsify）**: 当初この test 1本(84989f3e)だけで「質問終わり継続説はREFUTED」と一般化して記録・コミット(`4d2cfd3`)したが、**これは行き過ぎだった**。clean config 修正後の実バックフィルで `5a736154` が **clean config 下でも継続モードで discard**（会話ログ末尾が「投稿しますか？どちらのご希望ですか？」で終わっており、Haiku が末尾発言を引き継いで質問返しする）。→ 正しくは **2層**:
  1. **ペルソナ継承（支配的主因・修正済み）**: CLAUDE.md/output-style の口調・質問モード継承。clean config で根絶。46件中の大半の見出し不足を解消。
  2. **質問終わり継続（稀な残存モード・未対策）**: 会話ログ末尾が質問で終わるセッションで Haiku が継続してしまう。clean config でも残る。頻度極小（実測46件中1件=5a736154）。→ follow-up タスク（下記）。
- learned-rule「決定的/非決定的を分離」に直結: 要約という決定的タスクを対話ペルソナから切り離した clean config で回すのが恒久対策。
- **細分**: 見出し不足6件中、実作業ありtools≥3が5件（clean config修正で救える）、tools=0の薄い1件（`69f54b4d`＝/model・/insightsのスラコマ出力のみ）はガードAの守備範囲外＝別の設計判断。

### 恒久対策（実装済み・コミット `4d2cfd3`）
summarize.sh の claude 呼び出しに以下を追加してペルソナを決定的に遮断した:
- `--system-prompt "$SUMMARIZER_SYSTEM"`（要約専用の非対話 system に置換）
- `--setting-sources ''`（ユーザー設定ソースを継承しない）
- テスト case1b でフラグ・値の両方を検証（回帰ガード）。

## Task7 実行結果（2026-07-24 完了）
ユーザー承認: 「スクリプト実行して正常に動いていたら cron も有効化して」。進行中混入について「作業途中の内容も日報に入って便利」→ 恒久ガードは作らず、今回の手動実行のみ**自分自身(549b3f6f)だけ手で除外**して実行。

- dry-run 対象 46件（真の欠損8件＋never-started等）。自分自身を除いた 45件を本番 `~/.nb/claude/sessions` へ投入。
- 途中 teardown で一度中断（20/45）→ backfill 冪等性で残りを流し直し、最終的に全件処理完了。
- 結果: md 総数 347 → **385（+38件生成）**。
- **最終 dry-run で残る md 無しは9件、全て説明つく**（＝正常動作を証明）:
  - legit-skip 6件（薄い/空セッション。summarize.sh ガードA の正常な弾き。今後も永久 skip）
  - `549b3f6f`（実行中の自分自身。SessionEnd で後から要約される）
  - `5a736154`（既知の質問終わり継続モード残存。無害＝md不在であって誤生成ではない。毎 cron で再試行され落ち続けるが害なし）
- 全処理で `~/.claude/projects` の jsonl 増殖なし（自己参照ループ再発なし）。

## follow-up タスク（未着手・別スコープ）
**質問終わり継続モードの対策**（handoff 上記②）。会話ログ末尾が質問で終わるセッションで Haiku が要約せず継続質問する稀な残存モード。対策案: プロンプトで会話ログを明示デリミタで囲み「上記はログ。あなたはこれを要約するだけで会話は継続しない」を強調する等。頻度極小（46件中1件）のため今回スコープ外とした。

### 全実測で安全確認済み
tmp向け単発実行いずれも `~/.claude/projects` の jsonl 数 1697→1697（差分ゼロ＝自己参照ループ増殖なし）。cron は backfill 行 `#` 無効のまま無傷。

## 次セッションでの論点（未決定・要ユーザー判断）

1. **started-but-failed(26) と never-started(20) を分けて扱うか**。分けるなら backfill.sh に「失敗履歴の有無」で区別するロジックを足すか、単に2回に分けて手動実行するかの選択。
2. **進行中と疑われる3件（直近0-3時間更新）を除外するか**。除外するなら「直近N時間以内のjsonlはスキップ」というガードを backfill.sh に追加するタスクが必要（現行プランには無い）。
3. 上記を決めたら Task7 Step2以降（実行・冪等確認・cron再有効化）を再開。

## 参考: このセッションで作った検証用ファイル（scratchpad, 揮発性）
- `final46.txt` — dry-run対象46件のフルパス
- `final46_sid8.txt` — 上記のsid8のみ
- `started_all.txt` — ログ上の summarize start 記録済みsid8全集合(508件)
- `bucket_started.txt` / `bucket_never.txt` — 46件をstarted/never-startedに分類したもの
