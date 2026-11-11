# 日報の品質改善（第2弾）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 区切り前の混入・git にしか出ないマージの落とし・RC の削りすぎ・git 収集範囲の穴・状態の格上げを直し、自己チェックに PR 番号の決定的な照合を足す。

**Architecture:** 切り出しの文脈を「直近の切り出し要約の意図と結論」に替え、自分の発言が無い区切りは切り出さない（summarize.sh）。
fire は git の収集先と正規名を広げ、区切り内のマージ一覧をペイロードに載せ、セッション要約から日報に使わない3節を外す。
RC の `--budget` は字数で数える。自己チェックは payload の マージ一覧の PR 番号が日報にあるかを決定的に確かめる。

**Tech Stack:** bash（`set -euo pipefail`）、Python 3.10+（標準ライブラリのみ。cron は /usr/bin/python3 3.10）、git、jq、`claude -p`、RemoteTrigger。

**Spec:** `docs/superpowers/specs/2026-11-11-daily-report-quality-fixes-design.md`（前回: `docs/superpowers/specs/2026-11-10-daily-report-day-slice-design.md`）

## Global Constraints

- 作業場所は worktree `/home/aya/dotfiles-daily-report-quality`（ブランチ `feat/daily-report-quality`）。`/home/aya/.dotfiles` は別セッションのブランチが出ている本番の作業ツリーなので、編集しない。
- 区切りは JST の「前日 22:10:00（含む）〜 当日 22:10:00（含まない）」。`scripts/daily-review/day-window.sh` の `day_window` を使う。
- 送信を止める経路を作らない。新しい処理の失敗は、ログに残して今の動きに倒す。
- `summarize.sh` を2引数（hook・backfill）で呼んだときの挙動は変えない。既存のテスト（`extract-test.sh`・`summarize-test.sh`・`backfill-test.sh`・`slice-sessions-test.sh`・`fire-daily-review-test.sh`・`check-daily-report-test.sh`・`scripts/lib/rocketchat-test.sh`）は全部 `ALL OK` のまま。
- 全体の予算は 60,000字のまま。RC の予算は 15,000字（`--budget 15000` の意味が字数になる）。
- テストは自前の bash テスト。`claude`・Rocket Chat・メール・GitHub はスタブに差し替える。テストは実在のリポジトリ（`/mnt/d/...` や `~/src/...`）を読まない。
- シェルは `.claude-global/rules/shell-conventions.md`、コメントは `.claude-global/rules/code-comments.md` に従う。
- 外部への書き込み（ルーティンの `RemoteTrigger update`、life の Issue・blog の上書き）は、差分や対象日をユーザーに見せて承認を得てから行う。
- サブスクの5時間上限: `claude -p` を大量に回す検証（Task 7）は、ユーザーが指定する時間帯に行う。

## Review Focus

1. 区切り内の user の文字の発言が、Claude Code が差し込むもの（`<local-command-stdout>`・`[Request interrupted by user]` など）だけのとき → 発言として数えてよい（判定は「user の text が1件以上」で決め打ち。Task 2 のテストで固定）。
2. 前日の切り出しが、検証用に分けた `SLICES_ROOT` にしか無い／本番にしか無い → 同じ `SLICES_ROOT` の中だけを探す（Task 2 のテスト）。
3. `origin` が `.git` 付きの GitBucket の URL、`origin` が無い、別名の clone と worktree が同じリポジトリ → 1つの見出しにまとまり、コミットは1回だけ数えられる（Task 3 のテスト）。
4. 日報で PR を `PR#1202`・`#1202`・`PR #1202` と書く → どれも照合に通る。`1202` だけ（`#` 無し）は通らない（Task 5 のテスト）。
5. マージ一覧が0件の日 → payload の節は `(なし)` になり、自己チェックの PR 照合は何も足さない（Task 4・5 のテスト）。

---

### Task 1: rocketchat.sh の --budget を字数で数える

**Files:**
- Modify: `scripts/lib/rocketchat.sh`（`--budget` の比較 ≈:489-495、使い方コメント ≈:11、≈:438-443 のコメント）
- Modify: `scripts/lib/rocketchat-test.sh`（バイト前提のテスト ≈:729 付近）

**Interfaces:**
- Produces: `rocketchat.sh ... --budget N` は、出力の字数（Unicode の文字数。ロケールに依存しない）が N を超えないようにルーム単位で落とす。省略時は今どおり上限なし。

- [ ] **Step 1: テストを直す・足す** — 日本語だけのルームを3つ（各 2,000字＝6,000バイト）用意し、`--budget 5000` で2ルームが残り1ルームが省略されること（バイトで数えると1ルームしか残らない）。`LANG` 未設定（`env -i`）でも同じ結果になること。既存のバイト前提のケースは字数の期待値に直す。
- [ ] **Step 2: `bash scripts/lib/rocketchat-test.sh` を実行し、新しいケースの失敗を確認する**
- [ ] **Step 3: 字数で比べるよう実装する** — 数え方は `python3 -c` か `LC_ALL=C.UTF-8 wc -m` など、ロケールに依存しない方法。≈:438-443 のコメントを実態に合わせる。
- [ ] **Step 4: `rocketchat-test.sh` が `ALL OK` になることを確認する**
- [ ] **Step 5: コミット** — `fix: rocketchat.sh の --budget をバイトではなく字数で数える`

### Task 2: 切り出しの文脈を直近の切り出しの意図と結論に替え、発言の無い区切りは切り出さない

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh`（切り出しモードの文脈 ≈:143-160、プロンプト）
- Modify: `scripts/claude-summarize/summarize-test.sh`（case9・case10 の期待を直し、ケースを足す）

**Interfaces:**
- Consumes: 切り出し md の置き場所 `$SLICES_ROOT/<YYYY-MM-DD>/<safe_proj>-<sid8>.md`（隠しファイル名あり。find で探す）
- Produces（切り出しモードだけ。hook モードは不変）:
  - 区切り内の本文（`extract.py --since --until` の出力）に `**User:**` で始まる行が1つも無ければ、何も書かずに exit 0（`.failed` には載らない＝補完されない）。
  - 文脈は、`$SLICES_ROOT` の対象日より前の日付フォルダを新しい順に最大14日分探し、最初に見つかった同じ sid8 の切り出し md の「## 意図」節と「## 結論」節だけ。見つからなければ文脈ブロックなし。生ログ（`extract.py --until`）は使わない。`SLICE_CONTEXT_CHARS` は廃止する。
  - プロンプトに次の1文を足す: 「文脈に書かれた作業（コミット・PR・修正・配置など）は、範囲内のやりとりで改めて行われていない限り書かないこと。」

- [ ] **Step 1: テストを書く**
  - case9 改: 範囲内に user の文字の発言がある fixture で切り出しができる（今の期待のまま）。
  - case10 改: 3日前の日付フォルダに同じ sid8 の切り出し md（意図「前日の意図X」、結論「前日の結論Y」、作業内容「前日の作業Z」）を置く → プロンプトの文脈に X と Y があり、Z と範囲前の生の発言は無い。
  - 新ケース: 前日の切り出しが15日前にしか無い → 文脈ブロックなし。
  - 新ケース: 範囲内が assistant の発言と tool_result だけ（user の文字の発言0件） → exit 0、ファイルなし、claude は呼ばれない。
  - 新ケース: 範囲内の user の発言が `<local-command-stdout>...</local-command-stdout>` だけ → 発言ありとして切り出す（Review Focus 1）。
  - 新ケース: 前日の切り出しが別の `SLICES_ROOT` にしか無い → 文脈ブロックなし（Review Focus 2）。
  - プロンプトに上の1文があること。
- [ ] **Step 2: `bash scripts/claude-summarize/summarize-test.sh` を実行し、失敗を確認する**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: `summarize-test.sh`・`extract-test.sh`・`backfill-test.sh`・`scripts/daily-review/slice-sessions-test.sh` が `ALL OK` になることを確認する**
- [ ] **Step 5: コミット** — `fix: 切り出しの文脈を直近の切り出しの意図と結論にし、発言の無い区切りは切り出さない`

### Task 3: git の収集先を広げ、リポジトリ名とラベルを origin で決める

**Files:**
- Modify: `scripts/daily-review/fire-daily-review.sh`（`canonical_repo_name` ≈:138、`collect_git_log` の収集先とラベル ≈:146-）
- Modify: `scripts/daily-review/fire-daily-review-test.sh`

**Interfaces:**
- Produces:
  - 収集先: 今の `$HOME/.dotfiles`・`$HOME/src/github.com/aya-215/*/`・`$HOME/src/github.com/ebase-dev/*/`・`/mnt/d/tomcat/webapps/*/` に加えて `$HOME/worktrees/*/`・`$HOME/src/192.168.208.80/gitbucket/*/*/`・`/mnt/d/git/*/`。テスト用に `FIRE_GIT_ROOTS`（改行区切りの glob の並び）で全体を差し替えられる。
  - 正規名: `git remote get-url origin` の末尾のパス要素から `.git` を除いたもの。`origin` が無ければ今の方法（共通 `.git` の親ディレクトリ名）。
  - ラベル: `origin` に `github.com/aya-215/` または `github.com:aya-215/`、`github-aya215:aya-215/` を含めば Personal、それ以外（`origin` 無しを含む）は Work。
  - 見出しは今と同じ `### [<ラベル>] <正規名>`。コミット行の書式（`MM/DD HH:MM [branch] subject（N files +A -D）`）と SHA の重複除去は変えない。

- [ ] **Step 1: テストを書く** — 一時ディレクトリに bare リポジトリと clone を作り、`FIRE_GIT_ROOTS` で渡す。`--dry-run` の payload.txt の git 節で確かめる。
  - `origin=git@github-aya215:aya-215/dotfiles.git` の clone → `### [Personal] dotfiles`
  - 同じ bare を `origin` に持つ、別名ディレクトリの clone（`eae-docs-x`）と worktree → どちらも `### [Work] eb-api-extended` の1見出しにまとまり、同じコミットは1行だけ
  - `origin=http://192.168.208.80:8080/gitbucket/git/eBASE/release-skills-repo.git` → `### [Work] release-skills-repo`
  - `origin` 無し（ディレクトリ名 `localonly`） → `### [Work] localonly`
  - 他人の author のコミットは入らない（今の `--author` のまま）
- [ ] **Step 2: テストを実行し、失敗を確認する**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: `fire-daily-review-test.sh` が `ALL OK` になることを確認する**
- [ ] **Step 5: コミット** — `fix: 日報の git 収集に worktree・GitBucket・D ドライブを足し、リポジトリ名とラベルを origin で決める`

### Task 4: ペイロードにマージ一覧を載せ、セッション要約から使わない3節を外す

**Files:**
- Modify: `scripts/daily-review/fire-daily-review.sh`（payload の組み立て、`build_sessions` ≈:314-）
- Modify: `scripts/daily-review/fire-daily-review-test.sh`

**Interfaces:**
- Consumes: Task 3 の git 節（見出し `### [<ラベル>] <正規名>` と、件名に `Merge pull request #N from <owner>/<branch>` を含むコミット行）
- Produces:
  - payload に節を足す。位置は git 節の直後。見出しは厳密に `【区切り内にマージされたPR】`。
    1行の書式は厳密に `- <正規名> #<N>（<owner>/<branch>、<MM/DD HH:MM>）`。0件なら本文は `(なし)` の1行。Task 5 はこの書式を正規表現で読む。
  - `build_sessions` が payload に入れる各要約の本文から、`## 実行した主なコマンド`・`## ナレッジ候補`・`## フィードバック/承認` の3節（見出しから次の `## ` の直前まで）を外す。切り出し md・sessions/ の要約ファイル自体は変えない。補完の印の付け方も今のまま。

- [ ] **Step 1: テストを書く**
  - git 節に `Merge pull request #1202 from ebase-dev/feat/1013-x` のコミットがある fixture → payload に `【区切り内にマージされたPR】` と `- ebase-portal-chat #1202（ebase-dev/feat/1013-x、11/06 17:25）` がある
  - マージが無い → 節の本文が `(なし)`（Review Focus 5）
  - 3節を含む切り出し md → payload に「## 作業内容」「## 結論」は残り、3節の見出しも中身も無い
- [ ] **Step 2: テストを実行し、失敗を確認する**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: `fire-daily-review-test.sh` が `ALL OK` になることを確認する**
- [ ] **Step 5: コミット** — `feat: 日報のペイロードに区切り内のマージ一覧を載せ、要約から日報に使わない節を外す`

### Task 5: 自己チェックにマージした PR の決定的な照合を足す

**Files:**
- Modify: `scripts/daily-review/check-daily-report.sh`
- Modify: `scripts/daily-review/check-daily-report-test.sh`

**Interfaces:**
- Consumes: Task 4 の payload の `【区切り内にマージされたPR】` 節と行の書式
- Produces:
  - LLM の照合が終わった後に（`check_failed` でない場合）、節の各 PR 番号 N について、日報の「📝 サマリー」節に `#N` が「直前と直後が数字でない」形で現れるかを調べる。
  - 現れない PR ごとに `missing` に `{"text":"区切り内にマージされた <正規名> #<N> が日報に無い","severity":"重大"}` を足す（同じ番号が LLM の missing に既にあっても重ねてよい）。
  - `notify` と件数（ログ行）は足した後の内容で計算する。
  - 節が無い payload（前回までの形式）や `(なし)` のときは何もしない。

- [ ] **Step 1: テストを書く**
  - 一覧に #1202 と #128、日報に `PR#1202` と `#1280` → #128 だけが重大で足され、`notify=true`（`#1280` は #128 に一致しない）
  - 日報に `PR #128` と `#1202` → 何も足されない（Review Focus 4）
  - 日報に `1202` だけ（`#` 無し） → #1202 が足される
  - 節が `(なし)`、または節が無い payload → 何も足されない（Review Focus 5）
  - LLM が `check_failed` のときは照合しない（今の挙動のまま）
- [ ] **Step 2: テストを実行し、失敗を確認する**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: `check-daily-report-test.sh` が `ALL OK` になることを確認する**
- [ ] **Step 5: コミット** — `feat: 自己チェックで区切り内にマージした PR が日報にあるかを決定的に確かめる`

### Task 6: ルーティンのプロンプトと文書を直す（プロンプトは承認が要る）

**Files:**
- Modify: `docs/daily-report-pipeline.md`（情報源・切り出し・自己チェック・変更履歴）
- Modify: `.claude-global/skills/verify-daily-report/SKILL.md`（「予算は逼迫していない」の記述を実測に合わせる。新しい節の説明）

**Interfaces:**
- Consumes: Task 2〜5 の挙動と、payload の `【区切り内にマージされたPR】` 節

- [ ] **Step 1: `RemoteTrigger get trig_01Xeb7Pw4dHu7jtitzMbK1iv` で今のプロンプトを取り、差分を作る**
  - 手順5に追記: 「【区切り内にマージされたPR】の PR は、すべて日報の項目に含め、`#番号` を書く。自分の PR は自分の作業に、他人の PR をレビューしてマージしたものはレビュー作業に置く」
  - 生成ルールに3行（設計書の決定12）: 予定・依頼・準備を完了のように書かない／ローマ字の ID に漢字を推測して当てない／後の記述が前の記述を訂正していれば後に従う
- [ ] **Step 2: 差分をユーザーに見せて承認を得る。承認が出るまで Step 3 に進まない**
- [ ] **Step 3: `RemoteTrigger update` で `job_config.ccr.events[0].data.message.content` を差し替え、`get` で反映を確かめる**（`environment_id`・`session_context` は get の値のまま）
- [ ] **Step 4: 文書を直す** — pipeline の情報源の表（RC は字数）、切り出しの文脈、マージ一覧、自己チェックの PR 照合、変更履歴。verify スキルの「予算は逼迫していない」を「2026-11 時点で RC が削られていた（字数化で解消見込み）」に直す
- [ ] **Step 5: コミット** — `docs: 日報の品質改善（第2弾）を仕様とスキルに反映する`

### Task 7: 17日分で dry-run して効果を確かめる（5時間上限に注意）

**Files:**
- Create: `docs/daily-report-quality-fixes-check-2026-11.md`（結果）

**Interfaces:**
- Consumes: Task 1〜5

- [ ] **Step 1: ユーザーに実行の時間帯を確認する**（17日分の切り出しを Sonnet で作り直すため、サブスクの5時間上限を食う）
- [ ] **Step 2: 検証用の置き場所で、古い順に1日ずつ dry-run する** — `SLICES_ROOT=$HOME/.nb/claude/daily-slices-v2 MAIL_ARCHIVE_BIN=<何もしないスクリプト> bash scripts/daily-review/fire-daily-review.sh --dry-run --date <D>`（worktree から実行し、`FIRE_ENV_FILE`・`RC_ENV_FILE` は `/home/aya/.dotfiles/scripts/daily-review/.env.local`）。古い順にするのは、文脈に前日の切り出しを使うため
- [ ] **Step 3: 数字を取る**
  - 区切り外の既知5件（10-21 試行1・10-29 #304 の修正・10-29 #1164 の実装・11-09 ピン留め・11-09 `_archive`）が、その日の切り出し要約に出てこないこと（grep）
  - マージ一覧に 11-04 #1160・11-06 #1202・11-06 eb-api-extended #128・10-16 #981 が載ること
  - RC の「容量制限のため … ルームを省略」が出た日数（前回は8日中6日）
  - git 節に hankyu の kensho90 系・pilot_webcatalog のコミットが入り、`eae-docs-idcf-getagentinfo` の見出しが消えて eb-api-extended にまとまること
  - payload の字数（最大・平均）
- [ ] **Step 4: 結果を文書に書いてコミットし、ユーザーに報告する** — 実際に `--overwrite` で作り直す日はユーザーと決める（この計画では発火しない）。コミットメッセージ: `docs: 日報の品質改善（第2弾）の dry-run 結果を追加する`

---

## Self-Review メモ

- 設計書の決定 1〜23 の対応: 1・3・14 → Task 2／2・15 → Task 2／4・19 → Task 3・4／5・12・18・23 → Task 6／6・13・16・17 → Task 5／7 → Task 4／8・20 → Task 1／9・10・11・21 → Task 3／22 → Task 7
- 確かめ方 1 → Task 7、確かめ方 2（実際の再生成と照合）→ Task 7 の Step 4 でユーザーと決める
