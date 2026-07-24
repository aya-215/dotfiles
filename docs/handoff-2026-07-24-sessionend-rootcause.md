# 引き継ぎメモ: セッション要約 never-started 387件の原因究明結果

作成: 2026-07-24 / 調査セッション: 263ceef5（原因究明担当）
宛先: backfill 実装セッション

---

## 結論（一行）

**「387件の要約欠損」は大幅な過大評価。真の取りこぼしは対話(cli)セッション最大16件（うち実質回収対象は約9件、残り7件は極小で対象外）。** 残り363件(94%)は非対話のSDK/print実行で、中身も自動生成物（要約由来269＋security-review等94）と実証済み、そもそも要約対象外。そして backfill が `claude -p` で要約するたびに、この「要約対象外だが未要約に見える」jsonl(sdk-cli)が1本増える（自己参照ループの火種）。cli欠損16件の原因は非graceful終了（ウィンドウ閉じ/kill/クラッシュ）で、機序は確定・防止不可＝backfillでの事後回収が正しい。

---

## CONFIRMED（実データで実証済み）

### 1. なぜ387件が never-started か = 終了経路によってSessionEndが発火しないから
- `claude -p`（`entrypoint=sdk-cli`）で叩いた実行は、hookイベントを直接観測すると **SessionStart/Stop/UserPromptSubmit は出るが SessionEnd はゼロ**（`claude -p ... --include-hook-events` で実証）。
- その `-p` 実行の jsonl は **永続化される**（`/tmp/…/367838d0.jsonl` が33KBで残存）。
- 帰結: SessionEnd が発火しない → summarize-session.sh が呼ばれない → ログに `summarize start` が残らない → 「never-started」に見える。**これは障害ではなく仕様。**

### 2. entrypoint フィールドが対話/非対話の信頼できる弁別子
- 対話 = `entrypoint:"cli"`, `promptSource:"typed"/"queued"`
- 非対話 = `entrypoint:"sdk-cli"`(claude -p) または `"sdk-py"`(Python SDK), `promptSource:"sdk"`
- **検証**: started集合（SessionEnd発火済み=要約成功した真の対話）229件は **100% `cli`**。sdk-cli/sdk-py はゼロ。→ 弁別子として信頼できる。

### 3. never-started 387件の entrypoint 内訳（実測）
| entrypoint | 件数 | 正体 | 要約すべきか |
|---|---|---|---|
| sdk-cli | 280 | `claude -p`（CLI非対話） | ❌ 対象外 |
| sdk-py | 83 | Python SDK 非対話 | ❌ 対象外 |
| **cli** | **17** | **対話セッション** | ✅ 真の欠損候補 |
| none | 7 | 極小/断片で判定不能 | 個別確認 |

- 17件のcliのうち **`263ceef5`(7/24 dotfiles 1.4M) は調査中の現行セッション自身**なので除外 → **真の欠損は実質16件**。
- 16件リストは同ディレクトリの `scratchpad/ns_path_ep.txt`（`grep -P '\tcli$'`）参照。日付6/24〜7/23、主に ebase-portal-chat / kakeibo / dotfiles。
- ※ `38869330`(7/23 ebase-middleware-mcp) は先の失敗ログ監査の「確定B」とも一致。

### 4. summarize-session.sh の resume除外はデッドコード
- `[ "$reason" = "resume" ] && exit 0`（23行目）は無効。SessionEnd の reason enum は clear/other/prompt_input_exit のみで resume は存在しない（ログ実測 resume 0件）。削除してよい。

---

## 対策（backfill 実装への提言）

### A. backfill の対象を entrypoint で絞る【最重要】
未要約jsonlを拾うとき、**`entrypoint == "cli"` のものだけ**を要約対象にする。sdk-cli / sdk-py は問答無用で除外。
- 効果1: 真の欠損16件だけを正しく拾える（363件のノイズを最初から見ない）
- 効果2: **自己参照ループを根絶できる**。backfill 自身が `claude -p`(sdk-cli) で要約を生成する→その jsonl は entrypoint=sdk-cli→次回 backfill が最初から無視。ゴミが増えても拾わない。
- 実装位置の候補: (a) backfill の対象抽出クエリで entrypoint フィルタ / (b) extract.py が sdk-cli/sdk-py を検出したら空出力で終了（summarize.sh の「本文空なら要約しない」ガードに乗る）。**(a)(b) 両方（多層防御）が堅い。決定的判定はコード側に置く**（学習ルール: 決定的処理と非決定的処理を分離）。

### B. queue-operation 等の type で弾く案より entrypoint 判定が確実
別セッションで検討していた「非会話ログ(queue-operation)を無視」案も有効だが、**entrypoint による判定の方が根拠が明確**（sdk-cli は定義上SessionEndを出さない＝要約する意味がない、と論理的に言える）。type ベースは表面的な症状、entrypoint はモードそのもの。

### C. disableAllHooks について（未確認・要検証）
summarize.sh は `claude -p --settings '{"disableAllHooks":true}'` を使用。今回 hookイベントが消えることは確認したが、**「jsonl永続化そのものを止められるか」は未検証**。もし `--no-session-persistence` フラグ（`claude --help` に存在、print専用）で backfill の要約呼び出しが jsonl を残さなくできるなら、それが最もクリーンな根絶策。→ **backfill セッションで `claude -p "test" --no-session-persistence` を叩いて jsonl が生成されないことを実機確認する価値あり。** これが効けば A の効果2すら不要になる。

---

### 5. 「363ノイズ」の内訳も中身で確定（ラベルだけでなく実証）
sdk系363件を jsonl 中身で分類:
- **要約由来 269件** — summarize.sh 自身の haiku 呼び出し（プロンプト署名「以下は Claude Code の1セッションの会話ログ」を検出）。★これが backfill の自己参照ループの温床。
- **要約以外のSDK実行 94件** — 大半が「Review this change for security vulnerabilities.」＝security-review hook 等が自動で叩く `claude -p`。これも自動生成物で要約対象外。
- → 363件すべて非対話の自動生成物であることを中身で確認。ラベル(entrypoint)と中身が一致。

### 6. section C 確定（disableAllHooks は永続化を止めない）【CONFIRMED】
上記269件の存在自体が証拠。summarize.sh は `claude -p --settings '{"disableAllHooks":true}'` で叩いているのに、その269本が jsonl として残っている。**disableAllHooks はhookを切るだけで、jsonl永続化は止まらない**とディスク上で確定。→ 対策Cの `--no-session-persistence` 検証は依然有効（永続化自体を止められるなら根絶策）。

### 7. cli欠損16件（真の取りこぼし）の原因 = 非graceful終了【機序CONFIRMED / per-session復元不能】
- **機序（論理で確定）**: SessionEnd の reason enum(clear/logout/prompt_input_exit/other)は全て「プロセスが生きて shutdown handler を走らせて」emit される。ウィンドウ閉じ/SIGKILL/WSL teardown/クラッシュで死んだプロセスはどの reason も出せない。16件は SessionEnd ゼロ かつ jsonl構造が発火群(started)とバイトレベルで同型（最終行type分布も一致）→ **非graceful終了で死んだと機序レベルで確定**。
- **per-session の犯人特定は原理的に不可能**: 終了モードはjsonlに記録されない。「どれがウィンドウ閉じでどれがクラッシュか」は復元できない（H-a/H-bは区別不能かつ打ち手が同じなので畳んでよい）。
- **REFUTED**: H-c(未終了)=発火群も同じ形で終わる / H-d(発火しないgraceful経路)=started 229/229 が全部cliで発火しており反証。
- **これは firing バグではなく日常的 attrition**: 16件は 6/24〜7/23 に散在、多数プロジェクトに分散、単一日クラスタなし。→ **「防げないので backfill で事後回収」戦略が正しいと裏付ける**。
- **回収対象の上限 ≤16件**: うち7件は極小(≤10行)で thin-session ガード(tool0＆本文200字未満)に弾かれ得る。**実質的な回収対象は約9件**。リストは `scratchpad/cli_paths.txt`。

## 未確認・別セッター側で要検証
- 「ゴミjsonlが15本湧いた」の具体（この調査セッションでは未観測。backfill 側のログで確認を）
- backfill の現行除外ロジック（このセッションでコード未読）
- C の `--no-session-persistence` の実効性（永続化を止められれば自己参照ループの根絶策）

## 参考ファイル（scratchpad, 揮発性）
- `ns_path_ep.txt` — 387件の パス＋entrypoint 対応表
- `ns_full.txt` — never-started 387件（sid/path/日付）
- `started.txt` — SessionEnd発火済み集合
