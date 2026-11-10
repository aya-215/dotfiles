# 日報の日次切り出し要約 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 日報の入力を「前日 22:10〜当日 22:10 のやりとりだけを要約した日次の切り出し要約」に切り替え、毎晩の自己チェックと上書き再生成を加える。

**Architecture:** `extract.py` に時刻の範囲指定を足し、`summarize.sh` に切り出しモード（別ディレクトリへ出力し、既存要約を消さない）を足す。
新しい `slice-sessions.sh` がその日の範囲に動きのあった jsonl を全部切り出し要約し、`fire-daily-review.sh` はそれを材料に送る。
送ったペイロードはローカルに保存し、`check-daily-report.sh` が 22:40 にそれと生成された日報を照合する。

**Tech Stack:** bash（`set -euo pipefail`）、Python 3（標準ライブラリのみ）、`claude -p`、`gh api`、cron、PowerShell トースト（既存の `toast.ps1`）。

**Spec:** `docs/superpowers/specs/2026-11-10-daily-report-day-slice-design.md`

## Global Constraints

- 区切りは JST の「前日 22:10:00（含む）〜 当日 22:10:00（含まない）」。表記は `YYYY-MM-DDT22:10:00+09:00`。送信した時刻ではなく対象日から決める。
- 切り出し要約のモデルは `claude-sonnet-5`。長尺（240,000 字超）は `claude-sonnet-5[1m]`。
- 切り出し要約の置き場所は `~/.nb/claude/daily-slices/YYYY-MM-DD/`（環境変数 `SLICES_ROOT` で上書き可）。既存の `~/.nb/claude/sessions/` は作り方・中身・置き場所を変えない。`summarize.sh` を引数なし（hook・backfill）で呼んだときの挙動と、既存の `summarize-test.sh` の全ケースは変えない。
- 切り出しが失敗しても送信は止めない。失敗したセッションは既存の `sessions/` の要約で埋め、切り出しが丸ごと無い日は今の方式で送る。
- redaction（`scripts/lib/redact.sh`）は今と同じく送信直前に通す。DM は含めない。
- 対象外の jsonl: `*/subagents/*` と entrypoint が `sdk-cli` / `sdk-py` のもの（今の backfill と同じ）。
- シェルは `.claude-global/rules/shell-conventions.md` に従う（shebang、`set -euo pipefail`、関数に docstring コメント、ローカル変数は `local`）。コメントは `.claude-global/rules/code-comments.md` に従う（非自明な WHY だけ）。
- テストは既存と同じ自前の bash テスト（`*-test.sh`、全部通れば `ALL OK` で exit 0）。`claude` 本体・Rocket Chat・メール・GitHub はスタブに差し替える。
- 外部への書き込み（ルーティンの `RemoteTrigger update`、life の Issue／blog の書き換え）は、Task 5 は差分の承認を得てから、Task 8 はユーザー承認済み（2026-11-10「日報は書き直して比べてみよう」）の範囲で行う。
- コミットは `feat:` / `fix:` / `docs:` などのプレフィックスを付け、コミットしたら push する。`.claude-global/settings.json` にはユーザーの未コミットの変更（`advisorModel`）があるので、触らない・ステージしない。

## Review Focus

1. 22:10 をまたいで続いたセッション → 範囲の中のやりとりだけが要約され、範囲の外は前の文脈にしか出ない（Task 1・2 のテストで固定）。
2. 同じセッションの jsonl が、生きている場所と退避先（`~/.local/share/daily-slice-replay/jsonl-backup/`）の両方にある → 1本だけ処理し、大きいほう（新しいほう）を使う（Task 3 のテスト）。
3. jsonl の保存期間を過ぎた日の再生成 → 切り出しが0件になり、今の `sessions/<日付>/` の方式で送る。送信が止まらない（Task 4 のテスト）。
4. 一部のセッションだけ切り出しに失敗 → そのセッションだけ既存要約で埋まり、ほかは切り出しのまま（Task 4 のテスト）。
5. hook の要約（`sessions/`）と切り出し要約が同時に走る → 切り出しモードは `sessions/` のファイルを消さない（Task 2 のテスト）。

---

### Task 1: extract.py に時刻の範囲指定を足す

**Files:**
- Modify: `scripts/claude-summarize/extract.py`
- Create: `scripts/claude-summarize/extract-test.sh`

**Interfaces:**
- Produces: `python3 extract.py <transcript.jsonl> [--since ISO8601] [--until ISO8601]`
  - `--since` は含む、`--until` は含まない。タイムゾーン付きの ISO 8601（`+09:00` や `Z`）を受け付ける。`timestamp` の無い user/assistant 行は、範囲指定があるときは捨てる。
  - ヘッダに `session_start: <全体で最初の timestamp>` を足す。`start:` / `end:` は範囲の中で最初と最後の timestamp。範囲の中に1行も無ければ本文は空（ヘッダだけ）。
  - 引数なしの出力は、`session_start:` 行が増える以外は今と同じ。

- [ ] **Step 1: テストを書く** — `extract-test.sh` に次のケース。fixture は 4 行（UTC `13:09:00Z`・`13:10:00Z`・`13:11:00Z`・翌日 `13:10:00Z`。JST では 22:09・22:10・22:11・翌日 22:10）。
  - `--since 2026-07-13T22:10:00+09:00 --until 2026-07-14T22:10:00+09:00` → 本文は 22:10 と 22:11 の2行だけ。`start:` は `13:10:00` の行、`end:` は `13:11:00` の行。`session_start:` は `13:09:00` の行。
  - `--until 2026-07-13T22:10:00+09:00` のみ → 本文は 22:09 の1行だけ。
  - 範囲に1行も無い → ヘッダ行のあとの本文が0行。
  - 引数なし → 4行すべてが出る（回帰）。
  - entrypoint `sdk-cli` → 範囲指定があっても本文0行。
- [ ] **Step 2: `bash scripts/claude-summarize/extract-test.sh` を実行し、失敗を確認する**
- [ ] **Step 3: 実装する** — `argparse` で `transcript`, `--since`, `--until` を受ける。比較は `datetime.fromisoformat`（`Z` は `+00:00` に置換）で aware 同士。
- [ ] **Step 4: `extract-test.sh` と既存の `summarize-test.sh` を実行し、両方 `ALL OK` を確認する**
- [ ] **Step 5: コミットする** — `feat: extract.py に --since/--until の時刻範囲指定を追加する`

### Task 2: summarize.sh に切り出しモードを足す

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh`
- Modify: `scripts/claude-summarize/summarize-test.sh`（ケースを追加）

**Interfaces:**
- Consumes: Task 1 の `extract.py --since/--until`
- Produces: `summarize.sh <transcript.jsonl> <session_id> --slice <YYYY-MM-DD> --since <ISO> --until <ISO>`
  - 出力先は `${SLICES_ROOT:-$HOME/.nb/claude/daily-slices}/<YYYY-MM-DD>/<safe_proj>-<sid8>.md`。同じパスがあれば上書きする。**ほかのファイルは消さない**（既存の `find ... -delete` は切り出しモードでは実行しない）。
  - frontmatter: `project` / `session_id` / `cwd` / `session_start` / `start` / `end`（範囲の中）/ `window_since` / `window_until`。
  - モデル: `SLICE_MODEL`（既定 `claude-sonnet-5`）、240,000 字超は `SLICE_MODEL_LARGE`（既定 `claude-sonnet-5[1m]`）。
  - 文脈: `extract.py --until <since>` の本文の末尾 `SLICE_CONTEXT_CHARS`（既定 20000）字を、プロンプトの `<<<CONTEXT_START>>>`〜`<<<CONTEXT_END>>>` に入れる。指示は「これは対象範囲より前の経緯。理解のためだけに使い、要約には含めない」。範囲より前が無ければブロックごと省く。
  - 7項目の書式と【レビュー作業】【実装作業】の指示は今と共通（プロンプト本文は二重に持たない）。
  - 終了コード: 書けたら 0。範囲の中が空・薄いセッションで書かなかったら 0。生成が2回とも失敗（claude 失敗・必須見出し不足）したら **3**（切り出しモードだけ。hook モードは今どおり 0）。
  - `--slice` が無いときは今と完全に同じ動き。

- [ ] **Step 1: テストを足す**（`summarize-test.sh` に case9〜12）
  - case9: Task 1 と同じ形の fixture を `--slice 2026-07-14 --since 2026-07-13T22:10:00+09:00 --until 2026-07-14T22:10:00+09:00` で要約 → `$SLICES_ROOT/2026-07-14/testproj-<sid8>.md` ができる。frontmatter に `window_since: 2026-07-13T22:10:00+09:00` がある。スタブに渡った引数に `claude-sonnet-5` がある。
  - case10: case9 のプロンプト（スタブの `prompt.1`）の TRANSCRIPT 部分に 22:09 の発言が無く、CONTEXT 部分に 22:09 の発言がある。
  - case11: 先に `$SESSIONS_ROOT/2026-07-13/testproj-2209-<sid8>.md` を置いてから case9 を実行 → そのファイルが残っている。
  - case12: スタブが2回とも不正出力を返す → 切り出しモードの終了コードが 3。同じ条件の hook モードは 0（回帰）。
- [ ] **Step 2: `bash scripts/claude-summarize/summarize-test.sh` を実行し、case9〜12 の失敗を確認する**
- [ ] **Step 3: 実装する** — 引数パースを足し、プロンプト組み立て・`claude -p` 呼び出し・見出し検証は今のコードを両モードで共有する。
- [ ] **Step 4: `summarize-test.sh` と `extract-test.sh` が `ALL OK` になることを確認する**
- [ ] **Step 5: コミットする** — `feat: summarize.sh に日次の切り出し要約モードを追加する`

### Task 3: 区切りの計算と、その日の切り出しをまとめて作る slice-sessions.sh

**Files:**
- Create: `scripts/daily-review/day-window.sh`（source 用）
- Create: `scripts/daily-review/slice-sessions.sh`
- Create: `scripts/daily-review/slice-sessions-test.sh`

**Interfaces:**
- Produces（`day-window.sh`）: `day_window <YYYY-MM-DD>` → 標準出力に `<since>\t<until>`。例: `day_window 2026-11-04` → `2026-11-03T22:10:00+09:00\t2026-11-04T22:10:00+09:00`。区切り時刻は定数 `DAY_CUTOFF="22:10:00"`。
- Produces（`slice-sessions.sh`）: `slice-sessions.sh <YYYY-MM-DD>`
  - 探す場所は `JSONL_ROOTS`（コロン区切り。既定は `$HOME/.claude/projects` と、あれば `$HOME/.local/share/daily-slice-replay/jsonl-backup`）。
  - 対象: `*.jsonl`（`*/subagents/*` を除く、ファイル名が UUID 形式）で、mtime が since 以降のもの。同じ session_id が複数あれば、サイズが大きいものを1本だけ使う。
  - 実行前に `$SLICES_ROOT/<date>/` の `*.md` と `.failed` を消してから作り直す（何度実行しても同じ結果になる）。
  - 各 jsonl について `${SUMMARIZE_BIN:-summarize.sh} <jsonl> <sid> --slice <date> --since <since> --until <until>` を `SLICE_JOBS`（既定 4）並列で呼ぶ。終了コード 3 だった sid の先頭8文字を `$SLICES_ROOT/<date>/.failed` に1行ずつ書く。
  - 最後に1行 `slices: written=<N> failed=<M> candidates=<K>` を標準出力に出す。終了コードは常に 0（呼び出し側の送信を止めないため）。

- [ ] **Step 1: テストを書く** — スタブ `SUMMARIZE_BIN` は受け取った引数を記録し、sid に応じて md を書く／何も書かない／exit 3 する。
  - `day_window 2026-11-04` と、月またぎ `day_window 2026-11-01`（since が `2026-10-31T22:10:00+09:00`）の出力。
  - mtime が since より前の jsonl はスタブに渡らない。`subagents/` 配下も渡らない。
  - 同じ sid が `JSONL_ROOTS` の2か所にあれば、サイズが大きいほうのパスだけが渡る。
  - exit 3 の sid が `.failed` に載り、最後の行が `slices: written=1 failed=1 candidates=3` の形になる。
  - 2回続けて実行しても、前回の md と `.failed` が残らない。
- [ ] **Step 2: テストを実行し、失敗を確認する**
- [ ] **Step 3: 実装する** — 並列は `xargs -P "$SLICE_JOBS"`。終了コードを集めるため、1件ずつ結果を一時ディレクトリに書く形にする。
- [ ] **Step 4: テストが `ALL OK` になることを確認する。実データで `bash scripts/daily-review/slice-sessions.sh 2026-11-05` を流し、`~/.nb/claude/daily-slices/2026-11-05/` に `ebase-portal-chat-97433f2a.md`（PR #1202 のセッション）ができていて、本文に `#1202` があることを目で確かめる**
- [ ] **Step 5: コミットする** — `feat: 日報用にその日の区切りで切り出し要約を作る slice-sessions.sh を追加する`

### Task 4: fire-daily-review.sh を切り出し要約に切り替え、上書きモードとペイロード保存を足す

**Files:**
- Modify: `scripts/daily-review/fire-daily-review.sh`
- Create: `scripts/daily-review/fire-daily-review-test.sh`
- Modify: `docs/daily-report-pipeline.md`（全体像・情報源・再生成の節）

**Interfaces:**
- Consumes: Task 3 の `day_window`、`slice-sessions.sh`
- Produces:
  - 引数: `[--dry-run] [--date YYYY-MM-DD] [--overwrite]`。`--overwrite` は `--date` と一緒のときだけ受け付ける（単独なら exit 2）。
  - 送ったペイロード（redaction 後）を `$SLICES_ROOT/<date>/payload.txt` に保存する。dry-run でも保存する。Task 6 が読む。
  - テスト用の差し替え口: `FIRE_ENV_FILE` / `ROCKETCHAT_BIN` / `MAIL_ARCHIVE_BIN` / `SLICE_BIN` / `SESSIONS_ROOT` / `SLICES_ROOT`（いずれも既定は今の値）。

変更点:
- 先頭で `export LANG=C.UTF-8`。予算の `${#var}` を cron でも文字数で数えるため。
- `WINDOW_SINCE` / `WINDOW_UNTIL` を `day_window "$target_date"` で決める。git 収集の `--since` / `--until` をこの2つに変える。RC・メールは暦日のまま。
- 送信判定の前に `slice-sessions.sh "$target_date"` を呼び、出力をログに残す（失敗しても続行する）。
- 「送らない」のは、切り出しの md も `sessions/<date>/` の md も無いときだけ。
- `build_sessions` の材料の決め方:
  - 切り出しの md がある → 切り出しの md ＋ `.failed` に載った sid の既存要約（`$SESSIONS_ROOT` 全体から `*-<sid8>.md`）を使う
  - 切り出しの md が無い → 今どおり `sessions/<date>/`
  - 見出しの時刻は、切り出しなら frontmatter の `end`
- ペイロードの【対象日】の次の行に `【区切り】<since> 〜 <until>（セッション要約はこの範囲のやりとりだけを要約済み）` を足す。
- `--overwrite` のときは、さらに `【再生成モード】上書き（既存の「📝 サマリー」は引き継がず、このペイロードだけで作り直す）` を足す。

- [ ] **Step 1: テストを書く** — 環境は一時ディレクトリにまとめる。スタブの RC とメールは固定文字列を返す。スタブの `SLICE_BIN` はケースごとに用意した md を置く。テストは `--dry-run` で走らせ、`payload.txt` を検査する。
  - 切り出しが2本ある → `payload.txt` に両方の本文と `【区切り】2026-11-03T22:10:00+09:00 〜 2026-11-04T22:10:00+09:00` がある。`sessions/2026-11-04/` の本文は入らない。
  - `.failed` に sid8 が1つある → その sid の既存要約（別の日付フォルダにあるもの）の本文も入る。
  - 切り出しが0本で `sessions/2026-11-04/` に要約がある → その本文が入る（今の方式）。
  - 両方0本 → `payload.txt` はできず、ログに `skip:` が出る。
  - `--date 2026-11-04 --overwrite` → `【再生成モード】上書き` がある。`--overwrite` だけ → exit 2。
- [ ] **Step 2: テストを実行し、失敗を確認する**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: テストが `ALL OK` になることを確認する。実データで `bash scripts/daily-review/fire-daily-review.sh --dry-run --date 2026-10-30 > /dev/null` を流し、`~/.nb/claude/daily-slices/2026-10-30/payload.txt` に #1080 の昇格完了（close）が入っていることを確かめる**
- [ ] **Step 5: `docs/daily-report-pipeline.md` を新しい流れに合わせて直す** — 全体像の図、情報源の表、「生成されなかった日の再生成」に `--overwrite` を書く。
- [ ] **Step 6: コミットする** — `feat: 日報の送信を日次の切り出し要約に切り替え、上書き再生成とペイロード保存を追加する`

### Task 5: ルーティンのプロンプトを新しいペイロードに合わせる（外部変更・承認が要る）

**Files:**
- Modify: `docs/daily-report-pipeline.md`（変更履歴に1項目）

**Interfaces:**
- Consumes: Task 4 のペイロード（【区切り】行・【再生成モード】行）

- [ ] **Step 1: `RemoteTrigger get trig_01Xeb7Pw4dHu7jtitzMbK1iv` で今のプロンプトを取り、次の差分を作る**
  - 手順1に追記: 「【区切り】がある場合、【セッション要約】と【git活動】はその範囲（前日 22:10〜当日 22:10）のものである」
  - 手順5に追記: 「【セッション要約】は範囲内のやりとりだけを要約したもの。範囲より前の経緯を自分の作業として書き足さない」
  - 生成ルールの冪等性の行に追記: 「ペイロードに【再生成モード】上書き とある場合は、既存の『📝 サマリー』を引き継がず、ペイロードだけで作り直す」
  - Work の例に追記: 「社内リポジトリの worktree やブランチの掃除、業務資料の所在調査」
- [ ] **Step 2: 差分をユーザーに見せて承認を得る。承認が出るまで次へ進まない**
- [ ] **Step 3: `RemoteTrigger update` で `job_config.ccr.events[0].data.message.content` を差し替える**（`environment_id`・`session_context` は get の値のまま送る）。直後に `get` して、差分どおりになっていることを確かめる
- [ ] **Step 4: 変更履歴を書いてコミットする** — `docs: 日報ルーティンのプロンプトを区切りと上書き再生成に対応させた記録を追加する`

### Task 6: 毎晩の自己チェック check-daily-report.sh

**Files:**
- Create: `scripts/daily-review/check-daily-report.sh`
- Create: `scripts/daily-review/check-daily-report-test.sh`
- Modify: `docs/daily-report-pipeline.md`（cron と自己チェックの節）

**Interfaces:**
- Consumes: Task 4 の `$SLICES_ROOT/<date>/payload.txt`
- Produces: `check-daily-report.sh [--date YYYY-MM-DD] [--no-wait]`（既定の対象日は今日。JST）
  - 日報を取る: `gh api` で `repo:aya-215/life is:issue "<date>" in:title` を検索し、本文から「## 📝 サマリー」節を取り出す。認証は `GH_TOKEN="$(gh auth token --user aya-215)"`。テスト用に `ISSUE_BODY_FILE` が指定されていればそれを読む。
  - 待ち: サマリー節に箇条書きが1行も無いあいだは、60秒ごとに取り直す（最大20回）。`--no-wait` なら1回だけ。最後まで空なら結果を `report_missing` にする。
  - 照合: `claude -p --model "${CHECK_MODEL:-claude-opus-5}"` に、payload.txt・サマリー節・判定の注意点（verify-daily-report の「判定の注意点」と同じ内容。ただし「根拠は payload の【区切り】範囲の要約・git・RC・メールすべて」）を渡す。出力は次の JSON だけにさせる。
    `{"missing":[{"text":str,"severity":"重大|軽微"}],"unsupported":[{"text":str,"confidence":"高|中|低"}],"misclassified":[{"text":str}],"format":[str]}`
    JSON として読めなければ1回だけやり直す。
  - 判定（決定的）: `missing` に `重大` が1つ以上、または `unsupported` に `高` が1つ以上 → 要通知。
  - 出力: `$SLICES_ROOT/<date>/check.json`（LLM の JSON に `"notify": bool` と `"status": "ok|report_missing|check_failed"` を足したもの）。`~/.local/log/daily-review-check.log` に1行 `[時刻] <date> status=<..> missing=<n>(重大<n>) unsupported=<n>(高<n>) misclassified=<n> notify=<bool>`。
  - 通知: 要通知・`report_missing`・`check_failed` のときだけ、`printf '%s\n%s\n' "<タイトル>" "<1行の要約>" | "${TOAST_CMD:-<PowerShell で ~/.claude/hooks/toast.ps1>}"`。呼び方は `.claude-global/hooks/notify.sh` の96行目と同じ。

- [ ] **Step 1: テストを書く** — スタブの claude は固定の JSON を返す。`ISSUE_BODY_FILE` で日報を渡す。スタブの `TOAST_CMD` は呼ばれたら記録する。
  - `missing` が軽微だけ・`unsupported` が低だけ → `notify=false`。トーストは呼ばれない。ログの1行が上の形になる。
  - `missing` に重大が1件 → `notify=true`。トーストが呼ばれ、タイトルに対象日が入る。
  - スタブが2回とも JSON でないものを返す → `status=check_failed`。トーストが呼ばれる。exit 0。
  - サマリー節が空で `--no-wait` → `status=report_missing`。claude は呼ばれない。
  - payload.txt が無い → `status=check_failed`。claude は呼ばれない。
- [ ] **Step 2: テストを実行し、失敗を確認する**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: テストが `ALL OK` になることを確認する。実データで `bash scripts/daily-review/check-daily-report.sh --date 2026-11-09 --no-wait` を流し、`check.json` ができることを確かめる**（2026-11-09 の payload.txt が無ければ、先に Task 4 の dry-run を流して作る）
- [ ] **Step 5: crontab に `40 22 * * * /home/aya/.dotfiles/scripts/daily-review/check-daily-report.sh >> /home/aya/.local/log/daily-review-check-cron.log 2>&1` を足す**（`crontab -l` に追記して `crontab -`）。`docs/daily-report-pipeline.md` の cron の節を5本に直し、自己チェックの節を書く
- [ ] **Step 6: コミットする** — `feat: 生成された日報を毎晩ローカルで照合し、重大な問題だけ通知する自己チェックを追加する`

### Task 7: verify-daily-report スキルを新方式と RC に対応させる

**Files:**
- Modify: `.claude-global/skills/verify-daily-report/SKILL.md`

**Interfaces:**
- Consumes: Task 4 の `payload.txt`、Task 6 の `check.json`、Task 3 の `day_window`

- [ ] **Step 1: SKILL.md を直す**
  - 手順3: 対象日ごとに `~/.nb/claude/daily-slices/<date>/payload.txt` があれば新方式、無ければ旧方式（今の手順）と判定し、表に方式を載せる
  - 新方式のデータの場所: payload.txt（要約・git・RC・メールが全部入っている）、切り出しの md、check.json。区切りは `day_window`
  - 旧方式でも RC を照合に加える: `bash ~/.dotfiles/scripts/lib/rocketchat.sh --from <date> --to <date> --budget 15000`。その結果をサブエージェントに渡す
  - 判定の注意点: 「多日セッションの日付帰属」は旧方式だけの注意として残す。新方式では「範囲の外の作業が書かれていたら根拠不明に数える」に置き換える
  - 過去の実測に、2026-11-10 の結果（12日で取りこぼし2件・根拠不明18件は RC で裏付けあり・誤分類2件）を足す
- [ ] **Step 2: `bash scripts/daily-review/check-daily-report.sh --date 2026-11-05 --no-wait` の check.json と、スキルの手順で並べた結果の形が矛盾しないことを目で確かめる**
- [ ] **Step 3: コミットする** — `docs: verify-daily-report を切り出し要約と Rocket Chat の照合に対応させる`

### Task 8: 過去日を上書きで作り直して新旧を比べる

**Files:**
- Create: `docs/daily-report-day-slice-replay-2026-11.md`（比較結果）

**Interfaces:**
- Consumes: Task 4 の `--date --overwrite`、Task 5 のプロンプト、Task 6 の `check-daily-report.sh`

- [ ] **Step 1: 書き直す前の状態を記録する** — `git -C ~/src/github.com/aya-215/life pull` してから、HEAD のコミット ID を比較結果のファイルに書く（旧版の blog はこのコミットから取り出せる）。対象日は、2026-10-13〜2026-11-09 のうち `~/.nb/claude/sessions/<date>/` に要約がある日
- [ ] **Step 2: 先に dry-run で3例を確かめる** — 10-30・11-05 の `payload.txt` に、#1080 の昇格完了・PR #1202・decrypt の確認がその日の分として入っていること。REQ-2026-10-20-001 の作業が、やりとりのあった日の payload にだけ入っていること（`grep -l REQ-2026-10-20-001 ~/.nb/claude/daily-slices/*/payload.txt`）。期待どおりでなければ、ここで止めてユーザーに報告する
- [ ] **Step 3: 対象日を1日ずつ古い順に `fire-daily-review.sh --date <date> --overwrite` で発火する** — 1日ごとに `RemoteTrigger list_runs` で前の run が `idle` になってから次へ進む。`requires_action` になったら止めて報告する
- [ ] **Step 4: 全日の blog に反映されたら、各日に `check-daily-report.sh --date <date> --no-wait` を流す**
- [ ] **Step 5: 新旧を比べて比較結果のファイルに書く**
  - 日ごとの項目数（旧／新）
  - 取りこぼし・根拠不明・誤分類の件数（新は check.json。旧は 2026-11-10 の実測 12日分）
  - 複数日に重複して載った成果の数（旧／新）
  - 3例が正しい日に最終状態で載ったか
  - 新方式で悪くなった点
- [ ] **Step 6: コミットして、結果と調整案をユーザーに報告する** — `docs: 日報の切り出し要約で過去日を作り直した比較結果を追加する`

---

## Self-Review メモ

- 設計書の「決まっていること」1〜13 と、ユーザーが決めたこと（上書きモード・180日）の対応先:
  1→Task 3・4／2→Task 2・3／3→Task 2／4→Task 2／5→Task 4／6→Task 3・4／7→Task 6／8→Task 4・8／9→Task 5・7／10→Task 7／11→Task 6／12→Task 4（RC・メールは暦日のまま）／13→退避済み（Task 3 の `JSONL_ROOTS` で使う）
- 180日の保存期間はコミット済み（`a8034fe`）。この計画に作業は無い
