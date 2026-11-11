# 日報自動生成パイプライン

毎晩22:10に、その日の作業内容を自動で日報にまとめて `aya-215/life` の日報Issueへ書き込む仕組み。
本ドキュメントが**現行仕様の正本**。

> 日報Issueの自動作成（毎朝9時）・nb連携・blogファイル化といったGitHub Actions側の仕組みは
> [life-management.md](life-management.md) を参照。本ドキュメントは**サマリー生成**の部分を扱う。

---

## 全体像

```
[随時] SessionEnd hook ──→ summarize.sh（要約生成）
                              ↓
                        ~/.nb/claude/sessions/YYYY-MM-DD/*.md
                              ↑
[21:00 cron] backfill.sh ──────┘（hook取りこぼしの回収）

[22:10 cron] fire-daily-review.sh
               ├─ slice-sessions.sh で、その日の区切り（前日22:10〜当日22:10）に
               │    切り出した要約を作る → ~/.nb/claude/daily-slices/YYYY-MM-DD/*.md
               │    （失敗した sid は sessions/ の既存要約で埋める。切り出しが無い日は sessions/ のまま）
               ├─ git活動をローカル収集
               ├─ Rocket Chat 履歴を取得
               ├─ Thunderbird メールを整理
               ├─ redaction（redact.sh）
               ├─ 送ったペイロードを daily-slices/YYYY-MM-DD/payload.txt に保存（dry-run でも）
               └─ /fire へ POST（60,000字以内）
                              ↓
              クラウドルーティン daily-review（Opus 5）
                              ↓
              life の日報Issue body を更新（MCP の issue_write。git 操作はしない）
                              ↓（Issue が close 済みのとき）
              life の Actions（daily-to-blog.yml の sync-summary）が blog/YYYYMMDD.md のサマリー節へ反映
```

**3層に分かれている**のがポイント。セッション要約は随時、収集と送信は22:10、生成はクラウド側。

---

## cron（5本）

```cron
*/30 * * * *  ~/.dotfiles/scripts/nb-sync.sh                       # 日報とは無関係（nb同期）
30 12 * * *   ~/.dotfiles/scripts/temp-wsl-cleanup.sh              # 日報とは無関係（D:\temp_wsl の掃除）
0 21 * * *    ~/.dotfiles/scripts/claude-summarize/backfill.sh      # 要約の取りこぼし回収
10 22 * * *   ~/.dotfiles/scripts/daily-review/fire-daily-review.sh # 日報生成の発火
40 22 * * *   ~/.dotfiles/scripts/daily-review/check-daily-report.sh >> ~/.local/log/daily-review-check-cron.log 2>&1 # 生成された日報の自己チェック
```

`systemd --user` はWSLで動いていないため、実体はこのcrontabのみ。

### 自己チェック（22:40）

`check-daily-report.sh` が、22:10 に送ったペイロード（`daily-slices/<日付>/payload.txt`）と、
生成された日報（life リポジトリの日次 Issue「YYYY-MM-DD (曜) の記録」の「## 📝 サマリー」）を
`claude -p --model claude-opus-5`（`CHECK_MODEL` で変更可）に照合させる。

- サマリーに箇条書きが出るまで 60 秒おきに最大 20 回取り直す（`--no-wait` なら 1 回）。最後まで空なら `report_missing`
- 判定の注意点は `verify-daily-report` スキルと同じ。全期間要約（補完）の見出しは区切り前の作業を含みうるので、
  それだけを根拠にした「根拠不明」を高確信にせず、区切り前の作業の欠落を取りこぼしに数えない
- PR 照合: payload の `【区切り内にマージされたPR】` の各 PR が、サマリーに `#N`（前後が数字でない）で出ていなければ、LLM の判定とは別にスクリプトが「重大」の取りこぼしとして足す。jq が失敗しても LLM の結果だけで続ける（警告のみ）
- 通知するのは、取りこぼしに「重大」が 1 件以上、または根拠不明に確信度「高」が 1 件以上、`report_missing`、`check_failed`（payload 無し・claude 失敗/タイムアウト・JSON 不正が 2 回）のとき。判定はスクリプトが決定的に行う
- 通知は Windows トースト（`TOAST_CMD` で差し替え可）。通知の失敗でスクリプトは落ちない（常に exit 0）
- 結果は `daily-slices/<日付>/check.json`（`notify` と `status: ok|report_missing|check_failed|skipped` 付き。`skipped` は fire が材料なしで見送った日で、`daily-slices/<日付>/skipped` マーカーがあれば通知せず claude も呼ばない）と `~/.local/log/daily-review-check.log` に 1 行
- 手動実行: `bash scripts/daily-review/check-daily-report.sh --date 2026-11-09 --no-wait`

---

## 情報源と予算

`/fire` の `text` 上限は65,536字。余裕を見て**全体60,000字**に抑えている。

| ソース | 収集元 | 予算 |
|---|---|---|
| セッション要約 | `~/.nb/claude/daily-slices/<日付>/*.md`（日次の切り出し）。失敗した sid（`.failed`）は `sessions/` 全体から `*-<sid8>.md` で補う。切り出しが1本も無い日は `sessions/<日付>/*.md` | 残り全部 |
| git活動 | **ローカル**の git log（区切り内。`--since`/`--until` に区切りを使う） | 8,000字 |
| 区切り内にマージされたPR | 上の git log のマージコミットから作る（`【区切り内にマージされたPR】` 節。無ければ `(なし)`） | git 活動に含む |
| Rocket Chat | 購読ルーム横断・**DM除く** | 15,000字（`--budget` は字数。以前はバイトで数え、日本語が約1/3に削られていた） |
| メール | Thunderbird（life リポジトリにも保存） | 6,000字 |
| GitHubのIssue | クラウド側で `gh` 経由（当日closeのtask Issue等） | — |

区切りは JST の前日22:10（含む）〜当日22:10（含まない）で、送信時刻ではなく対象日から決める（`day-window.sh`）。
ペイロードの【対象日】の次の行に `【区切り】<since> 〜 <until>` を入れる。Rocket Chat・メールは暦日のまま。
ファイル名は `.dotfiles-<sid8>.md` のように隠しファイルになるため、列挙は `find -name '*.md'` で行う（glob は使わない）。

切り出しは `SLICE_TIMEOUT`（既定1800秒）で打ち切る。超えたら `slice: timeout` をログに残し、できている分で送信を続ける。加えて1セッションごとに `SLICE_ONE_TIMEOUT`（既定600秒）で打ち切り、固まった sid は `.failed` に入れて既存要約で補う（stdout/stderr は失敗理由として `slice:` ログに残る）。
`sessions/` 由来の要約（失敗 sid の補完・切り出しが無い日）は区切りで切っていない全期間の要約なので、見出しに `（全期間の要約・補完）` が付く。
git 活動の各行は区切りが日をまたぐため `MM/DD HH:MM` 形式。

**予算超過時は古いセッション要約から1本ずつ落とす**ループで収める（`build_sessions` の `keep` を減らす）。

ペイロードに載せるセッション要約からは、「実行した主なコマンド」「ナレッジ候補」「フィードバック・承認」の3節を除く。日報に使わないのに字数を食うため。除くのはペイロードだけで、要約ファイルは7項目のまま残る。

### git活動をローカル収集する理由

push前のコミットも拾えるうえ、GitHubに無い社内GitBucketリポジトリ（`/mnt/d/tomcat/webapps/*`）もカバーできる。
HEADのみを見る（`--all` はチェックポイントコミットを拾うため使わない）。

収集先は `~/.dotfiles`・`~/src/github.com/{aya-215,ebase-dev}/*/`・`~/src/192.168.208.80/gitbucket/*/*/`・`~/worktrees/*/`・`/mnt/d/tomcat/webapps/*/`・`/mnt/d/git/*/`（`FIRE_GIT_ROOTS` に改行区切りの glob を入れると丸ごと差し替え）。
リポジトリ名は origin から決める（GitBucket は `<group>/<repo>`）。Work/Personal のラベルも origin から決め、`aya-215` の GitHub だけ Personal、それ以外は Work。

**worktreeは本体リポジトリへ集約される。** worktreeは `../<略称>-<ブランチ名>` という兄弟ディレクトリに
作られるため、globでは別リポジトリに見えてしまう。`--git-common-dir` の親ディレクトリ名を正規リポジトリ名
として集約キーに使い、SHA重複を除去している。集約後は1リポジトリに複数ブランチが混ざるので、
ブランチ名は見出しではなく各コミット行（`- 13:45 [feat/xxx] ...`）に付く。

### 区切り内にマージされたPR

git 節の直後に `【区切り内にマージされたPR】` 節を置く。git log からは作業の粒度が読めても、マージの事実は落ちやすいため、別枠で渡して日報の項目に漏れなく含めさせる。
自分の PR は「自分の作業」、他人の PR をレビューしてマージしたものは「レビュー作業」に置く（ルーティンのプロンプトの指示）。

### Rocket Chat の採用ルール

購読ルームのうち期間内に活動があったものを列挙し、自分に関係するメッセージを拾う。

- **DMは含めない**（外部送信のため）。`--include-dm` で明示的に有効化は可能
- 自分の times チャンネル（`RC_CHANNEL`）は**全メッセージ採用**
- それ以外のルームは**起点の前後30分**（`WINDOW_SEC=1800`）の時間窓で採用
- 文字数制御は `--budget` によるルーム単位ドロップに委ねる

`RC_CHANNEL` が未設定・不一致だと自分のtimesが全採用されず時間窓の対象になり、黙って劣化する。
その場合は stderr に警告が出る。

### メールの扱い

gitログにもRocket Chatにも現れない社外・他部署とのやりとりを補う。
整理済みメールは `life` リポジトリの `mail/YYYYMMDD.md` にも保存され、業務履歴そのものが資産として残る。

要約層を挟むのは予算のため。生データを直接載せると1通700字・当日分のみに切り詰めるしかないが、
スレッド全体を読ませてから圧縮すれば「少し返信しただけ」の作業でも経緯を踏まえた記述になる。

#### フォルダ名は一意でない

**収集はフォルダ構成に依存しない。** `fetch()` はフォルダを指定せず全件から取り、採用は
宛先判定（`addressed_to_me`）と送信元・件名のブラックリストで決める。受信トレイを仕分けても
取得結果は変わらない。

ただし MCP が返す `folder` は**パスではなく末端のフォルダ名**（`fl.name`）で、一意ではない。

- **アカウントが2つある**ため `Sent` / `Drafts` / `Trash` が別実体で重複する
  （`mailbox://mori.a@…/Sent` と `imap://claude-code@…/Sent`）
- 仕分けで作った `bot` / `mine` / `自分宛` は GitHub 配下と GitBucket 配下で衝突する

このため `EXCLUDE_FOLDERS` に名前を足すと**両方のアカウント・両方の親フォルダに効く**。
除外を増やすときは `list_folders` で同名フォルダの有無を確認すること。

Sent は宛先判定を通さず無条件採用だったため、別アカウントの送信済みが「自分が返信した
スレッド（最優先）」に混ざりうる。現在は `sent_by_me()`（送信者アドレスで判定）で塞いでいる。
`search_messages` の `folder` 指定も MCP 側が部分一致（`fl.name LIKE %Sent%`）で
`Unsent Messages` まで拾うため、呼び出し側で絞り直している。

> 恒久対応は `folderURI` での判定。`folderLocations` に既にあり SQL も JOIN 済みなので
> MCP 側は1行で足せるが、`ebase-dev/ebase-middleware-mcp` の改修と `build/` の再ビルドが要る。

---

## redaction（二重ガード）

`scripts/lib/redact.sh` を**2箇所**で通す。

1. `summarize.sh` — 要約ファイル書き出し時（ローカルに残るファイルを守る）
2. `fire-daily-review.sh` — 送信直前（外部に出る内容を守る）

トークン類（`ghp_`, `sk-ant-`, `AKIA`, Slack, Bearer 等）に加えて、
**メール本文に平文で書かれる検証環境の認証情報**（`ログイン情報：user:pass` 形式）も落とす。

---

## プロンプトは2層

### ① 要約層（セッション毎・ローカル）

`scripts/claude-summarize/summarize.sh` が7項目固定で生成する。

意図 / 作業内容 / 結論 / 編集・作成ファイル / 実行コマンド / ナレッジ候補 / フィードバック・承認

**「## 意図」の冒頭に【レビュー作業】か【実装作業】を必ず明記させる**のが肝。
これが日報側の分類の一次情報になる。

**clean config で回す**（`--setting-sources '' --system-prompt <要約専用>`）。
ユーザーの CLAUDE.md（会話ペルソナ・口調・「不明点は質問」指示）を継承させると、
要約サブプロセスがプロンプトを会話の続きと誤解して質問を返し、必須見出し不足で discard される
（実データ6件で確認済み）。**決定的な処理と非決定的な処理の分離**の一例。

切り出し（`--slice`）では、会話の流れを補う文脈として、同じ `SLICES_ROOT` の直近14日にある同じ sid8 の最新の切り出しから「意図」「結論」だけを渡す（生の transcript は渡さない）。文脈の作業は範囲内で改めて行われていない限り書かせない。
範囲内に `**User:**` の行が無いセッションは、assistant だけの出力が混ざるだけなので要約せず見送る（exit 0。`.failed` に入れず、全期間の要約での補完もしない）。

モデルはサイズで段階ルーティングする（既定 haiku、240,000字超なら1Mコンテキスト側）。

### ② 生成層（クラウドルーティン）

**現行のプロンプトはこのドキュメントではなくルーティン本体が正本。** 全文を読むには:

```
RemoteTrigger action:"get" trigger_id:"trig_01Xeb7Pw4dHu7jtitzMbK1iv"
```

> プロンプト本文をここに転記しないこと。二重管理になり、`RemoteTrigger update` のたびにズレる。
> かつて `.claude-global/skills/daily-review/SKILL.md` に書式を置いていたが、スキル削除後も
> プロンプトが参照し続け、毎晩リカバリで凌ぐ状態になっていた（2026-08-17に解消）。

構成:

| ブロック | 内容 |
|---|---|
| 無人モードの制約 | 質問禁止・エラーで止まらない |
| 手順1-8 | 対象日特定 → Issue特定 → git活動 → task Issue → 入力の使い方 → 生成 → 更新 → 報告 |
| 【サマリー形式】 | `### Work (N commits across M repos)` / `#### 自分の作業` / `#### レビュー作業` / `### Personal` |
| 【生成ルール】 | 件数表記・分類・粒度・冪等性など |

分類の要点:

- **Work / Personal は「その成果物を会社に提出・共有するか」で分ける。** コミット先のリポジトリでは判断しない。
  - Work: 案件対応・他者PRのレビュー・発表資料・タスク整理・研修・社内の雑務・会社に出す週報
  - Personal: dotfiles等の作業環境整備・日報や life リポジトリへの操作・個人的な学習
  - dotfilesの整備は業務効率化が目的でも**会社に提出しないため Personal**。
    飲料発注のような社内雑務は提出物ではないが**会社のために動いているため Work**。
- **Work内を「自分の作業」と「レビュー作業」に分ける。** 判定は**他者のPRかどうか**。
  自分のPRへの指摘対応・自ブランチのセルフレビューは「自分の作業」に入れる
- **件数表記は Work のみ**（`### Work (12 commits across 3 repos)`）。Personal には付けない
- **「なし」と断定させない。** 該当作業が入力に無ければサブセクションごと省略する
  （6月の実データで「レビュー作業なし」と書きながら実際は要約に存在した例が2件あった）
- PR番号・issue番号・判明した原因・数値などの固有情報は省略しない
- **1項目は結論を1〜2文。経過（Phase構成・試行錯誤・検証手順）は書かせない。**
  規模の小さい作業も省略させない（網羅を字数より優先）。**箇条書きは1階層のみ**
- 既存サマリーがあれば入力として考慮し内容を失わない（冪等性）

---

## 使用クォータ

| 層 | 実行場所 | 消費 |
|---|---|---|
| セッション要約（`summarize.sh`） | ローカル `claude -p` | **サブスク枠** |
| 切り出し要約（`slice-sessions.sh` → `summarize.sh --slice`） | ローカル `claude -p`（`claude-sonnet-5`） | **サブスク枠** |
| メール整理（`thunderbird-summarize.sh`） | ローカル `claude -p`（`claude-sonnet-5`） | **サブスク枠** |
| 自己チェック（`check-daily-report.sh`） | ローカル `claude -p`（`claude-opus-5`） | **サブスク枠** |
| 日報生成（ルーティン） | クラウド | **サブスク枠**（ルーティン実行枠に加えて、5時間の利用上限も共有する） |

日報生成をクラウドルーティンに移したのは、Agent SDKクレジット消費を避けるため。

**どの層もサブスクの5時間上限を共有する**（2026-11-10 に実測）。上限に当たると、手元の切り出しは全部失敗して全期間の要約で補完される。
ルーティンは起動直後に `rate_limit: rejected (five_hour)` で終わり、Issue は書き換わらない。fire は HTTP 200 を受け取るので、
fire のログでは成功に見える（`RemoteTrigger get_run_log` で分かる）。その日は 22:40 の自己チェックが `report_missing` で通知するので、
上限が戻ってから `--date <日付> --overwrite` で作り直す。22:10 は、17時ごろにリセットが来る普段の使い方なら上限が空いている時刻として選んでいる。
ただし**メール整理だけはローカルの claude バイナリを使う**（スレッド全体を読ませてから圧縮する必要があり、
ペイロード予算内に生データを載せきれないため）。

---

## トラブルシュート

### ログの場所

| ファイル | 内容 |
|---|---|
| `~/.local/log/fire-daily-review.log` | 発火の成否・ペイロード字数・リトライ・切り出し結果（`slice:` 行） |
| `~/.local/log/claude-summarize.log` | セッション要約の生成状況 |
| `~/.local/log/thunderbird-archive.log` | メール保存の状況 |

### `skip: セッション要約なし` は正常

その日にPCを使っていない（＝作業していない）日は送信しない。
以前はディレクトリ不在で `find` が終了コード1を返し、`pipefail` で**黙って即死**していた
（2026-08-11に発生。ログに成功も失敗も残らず、休日なのかバグなのか区別できなかった）。
現在は明示的に判定して `skip:` をログに残す。**実行しないことは正常だが、記録せず終了するのは正常ではない。**

### 400番台は即中断・リトライなし

`is_permanent_error()` が再認可・権限系（`github_repo_access_denied` / `re-authorize` / `permission` /
`not_found`）を恒久エラーと判定し、**待たずに中断**する。リトライしても永久に成功しないため
（実データ: 2026-06-11に6回無駄打ち）。

**401は一時扱いでリトライ対象。** 同一トークンで直後に成功した実績があり、トークン失効ではないと確認済み
（2026-07-13 attempt=1が401 → attempt=2で成功）。指数バックオフ 60→120→240→480秒、待機総量 約15分。

> ⚠️ この挙動のため、**ルーティン設定に未検証の値を入れると危険**。400で落ちるとその日の日報が
> 丸ごと落ち、無人実行なので翌朝まで気づけない。モデルIDは検証済みの値を明示指定すること。

### 生成されなかった日の再生成

対象は「セッション要約はあるのに日報のサマリーが空」の日。原因は2通りある。

- 発火が失敗した: ログに `fire giving up` / `fire aborting` が出ている
- 発火していない: 22:10 にPCが落ちていて、その日のログ行自体が無い

手順:

1. 失敗日を特定する。

   ```bash
   grep -E 'giving up|aborting' ~/.local/log/fire-daily-review.log
   ```

   ログが無い日は `/verify-daily-report` の手順3（要約数と日報項目数の突き合わせ）で items=0 の日を探す。
2. 直前のログ行で原因を確認し、先に直す。原因が残ったまま再発火しても同じように落ちる。
3. 中身を確かめたいときは dry-run する。dry-run でもメール整理（`claude -p`）と life へのメール保存 push は走る。

   ```bash
   bash ~/.dotfiles/scripts/daily-review/fire-daily-review.sh --dry-run --date YYYY-MM-DD
   ```

4. 発火する。

   ```bash
   bash ~/.dotfiles/scripts/daily-review/fire-daily-review.sh --date YYYY-MM-DD
   ```

5. 結果を確認する。`RemoteTrigger list_runs` で該当 run が成功しているかを見てから、
   `git -C ~/src/github.com/aya-215/life pull` してサマリーが埋まったことを確かめる。

既存のサマリーを引き継がせず、このペイロードだけで作り直させたいときは `--overwrite` を付ける（`--date` 必須。単独だと exit 2）。
ペイロードに `【再生成モード】上書き` が入る。切り出しの区切りが変わった日など、既存サマリーが古い前提で書かれているときに使う。

   ```bash
   bash ~/.dotfiles/scripts/daily-review/fire-daily-review.sh --date YYYY-MM-DD --overwrite
   ```

送ったペイロードは `~/.nb/claude/daily-slices/YYYY-MM-DD/payload.txt` に残る（dry-run でも保存する）。
**最後に生成したペイロード**が残るだけなので、後から `--dry-run` すると上書きされる。保存に失敗しても送信は止めない（ログに `warn: payload.txt 保存失敗`）。
dry-run のときは、メール保存の push を避けたければ `MAIL_ARCHIVE_BIN` に何も出力しないスクリプトを指定する。

ルーティンは【対象日】の Issue 本文だけを更新する。Issue が close 済みなら、life の Actions
（`daily-to-blog.yml` の `sync-summary` ジョブ）が本文の「📝 サマリー」節を `blog/YYYYMMDD.md` の同じ節へ差し替えて push する。
blog の他の節は触らない。push は `concurrency` で直列化しているので、複数日を続けて発火してよい。
既存のサマリーは通常は入力として引き継ぐよう指示しているので、埋まっている日に再発火しても内容は消えない想定（`--overwrite` を除く）。

> 以前はルーティンが close 済みの日に `blog/` を直接編集して git push していたが、無人実行では
> `git reset --hard` や heredoc 付きの `git commit` が許可プロンプトで止まり、完了しなかった（2026-11-10 に判明）。
> Issue が open の日は MCP の `issue_write` だけで済むため、毎晩の定時実行では表面化していなかった。

**切り出し要約により、後日の再生成でも元の日の作業だけを拾える。** 以前は、セッションを再開すると
`summarize.sh` が古い要約を消して終わった日のフォルダに書き直すため、元の日の作業が欠けたり後の日の作業が混ざったりした。
現在は jsonl からその日の区切りで切り出し直す（jsonl は180日保持）。切り出しに失敗した sid だけ `sessions/` の既存要約で埋めるため、その分は従来の限界が残る。

**日付が変わってから手動で発火するときは必ず `--date` を付ける。** 付けないと実行した日が対象日になる
（10/8 分を 10/9 00:31 に手動発火した結果、10/9 が対象日になった）。

### `Argument list too long` で送信できない（2026-11-10 解消）

旧実装は JSON 本文を `curl -d "$body_json"` で argv に載せていた。Linux の1引数あたりの上限は 128KiB で、
`json.dumps` が日本語を `\uXXXX`（6バイト）に escape するため、日本語の多い日は約2.2万字で溢れていた。
同じ本文を何度送っても通らないため、5回リトライして `fire giving up` になる。
現在は本文をファイルに書き出して `--data-binary @file` で渡している。

### ルーティンの実行履歴を読む

```
RemoteTrigger action:"list_runs"    trigger_id:"trig_01Xeb7Pw4dHu7jtitzMbK1iv"
RemoteTrigger action:"get_run_log"  session_id:"<list_runsで得たID>"
```

`get_run_log` は実際のツール呼び出し・エラー・最終結果まで追える。
Web UI（<https://claude.ai/code/routines>）よりこちらのほうが速い。

### 主要な識別子

| 項目 | 値 |
|---|---|
| ルーティンID | `trig_01Xeb7Pw4dHu7jtitzMbK1iv` |
| モデル | `claude-opus-5` |
| 対象リポジトリ | `aya-215/dotfiles`, `aya-215/life` |

---

## 関連ファイル

| パス | 役割 |
|---|---|
| `scripts/daily-review/fire-daily-review.sh` | 収集・整形・POST（cron 22:10）。`--dry-run` / `--date` / `--overwrite` |
| `scripts/daily-review/check-daily-report.sh` | 生成された日報の自己チェック（cron 22:40）。`--date` / `--no-wait` |
| `scripts/daily-review/slice-sessions.sh` | 日次の切り出し要約を作る |
| `scripts/daily-review/day-window.sh` | 1日の区切り（前日22:10〜当日22:10）の計算 |
| `scripts/daily-review/.env.local` | `ROUTINE_FIRE_URL` / `ROUTINE_FIRE_TOKEN` / RC認証 |
| `scripts/claude-summarize/summarize-session.sh` | SessionEnd hook の入口 |
| `scripts/claude-summarize/summarize.sh` | セッション要約の本体 |
| `scripts/claude-summarize/backfill.sh` | 取りこぼし回収（cron 21:00） |
| `scripts/claude-summarize/extract.py` | JSONL前処理 |
| `scripts/lib/rocketchat.sh` | RC収集（work-report スキルと共通） |
| `scripts/lib/thunderbird-archive.sh` | メール保存（life リポジトリへ push） |
| `scripts/lib/thunderbird-summarize.sh` | メール整理（`claude-sonnet-5`） |
| `scripts/lib/redact.sh` | シークレット除去（二重ガードの実体） |

設計ドキュメント（当時の記録・現行仕様とはズレる場合がある）:

- [claude -p 移行設計](superpowers/specs/2026-06-10-claude-p-migration-design.md)
- [ルーティン移行計画](superpowers/plans/2026-06-10-daily-review-routine-migration.md)
- [セッション要約設計](superpowers/specs/2026-06-09-claude-session-summary-design.md)
- [Rocket Chat 複数ルーム対応](superpowers/specs/2026-07-28-rocketchat-multiroom-design.md)

---

## 品質の実測（2026-08-17時点）

> 同じ照合は `/verify-daily-report` スキルで再実行できる。前回実行日を記録して差分だけ処理するため、
> 月1回程度回すと劣化に早く気づける。

6〜8月の日報46日ぶんを、セッション要約・git活動と機械的に照合した結果。

| 期間 | 対象 | 取りこぼし | 根拠不明 | 誤分類 |
|---|---|---|---|---|
| 6月 | 16日 | 18件（重大5件） | 20件（確信度・高は1件） | 7件 |
| 7月 | 21日 | 3件（すべて軽微） | 0件 | 0件 |
| 8月 | 9日・62セッション | 2件（重大1件） | 2件（いずれも確信度・低） | 4件（実質0件） |

**6月から明確に改善している。** 要約の書式安定化・backfill導入・プロンプト改善が効いた結果で、
現状の評価は7〜8月を基準に見るのが正しい。

判明した事実:

- **セッション要約からの再現性は高い。** 8月は62セッション中、実体ある作業の取りこぼしが1件のみ
- **予算は逼迫していないが、Rocket Chat は例外だった（2026-11 に判明）。** ペイロード実測は最大36,424字（8/10）・平均約19,000字で、
  60,000の上限に一度も達していない。**古いセッションを落とすループは発動実績ゼロ**。
  ただし RC の 15,000 は当時バイトで数えており、日本語では実質 5,000字ほどに削られていた（字数化で解消見込み）。
  RC 由来の取りこぼしは、予算を疑う
- **誤分類は日報ではなく要約側の問題だった。** 6月・8月の誤分類のほとんどが
  「自分のPRへのレビュー指摘対応」で、日報側の判断のほうが実態に即していた。
  他者の成果を自分の作業として記録した例は**3ヶ月通して0件**
- **「なし」の断定が唯一の事実誤り系。** 06-10「レビュー作業なし」・06-30「レビュー作業の記録なし」は
  要約と直接矛盾していた。入力に無いものを省くのは無害だが、無いと断定するのは検証可能な誤りになる
- **空の日報2件はいずれも品質問題ではない。**
  - `2026-06-08`: 生成器がまだ存在しなかった（システム未成立）
  - `2026-07-17`: 401で3回失敗し `fire giving up`。**日報生成が一度も走っていない**。
    同じ401が07-13にも出てretry 2で復旧しており、当時の `MAX_ATTEMPTS=3`（約2分）が短すぎた。
    現在は5回・待機総量15分に拡張済み

## 変更履歴

- **2026-11-11（日報の品質改善・第2弾）**:
  - `rocketchat.sh --budget` を字数で数える（fire・verify スキルは 15000 字）。
  - 切り出し要約の文脈を、直近14日の同じ sid8 の切り出しの「意図」「結論」に変更（`SLICE_CONTEXT_CHARS` は廃止）。`**User:**` の無い範囲のセッションは見送る。
  - fire の git 収集に `~/worktrees`・GitBucket・`/mnt/d/git` を追加。名前とラベルは origin から決める。`【区切り内にマージされたPR】` 節を追加し、ペイロードから要約の3節（実行した主なコマンド・ナレッジ候補・フィードバック/承認）を除く。
  - `check-daily-report.sh` に、マージされた PR が日報に `#N` で出ているかの決定的な照合を追加（無ければ重大）。
  - ルーティンのプロンプト差分（手順5に PR を漏らさない指示、生成ルールに「予定・依頼・準備を完了と書かない」「ローマ字 ID に漢字を当てない」「後の記述が訂正なら後に従う」の3行）を用意済み。適用はユーザー承認後。

- **2026-11-10（ルーティンのプロンプト）**: 【区切り】の意味、範囲外の作業を書かないこと、`（全期間の要約・補完）` の扱い、【再生成モード】上書き の時は既存サマリーを引き継がないこと、雑務の分類例（社内リポジトリの worktree・ブランチの掃除、業務資料の所在調査は Work）を追加した。
- **2026-11-10（自己チェック）**: 毎晩 22:40 に、ペイロードと生成済みサマリーを照合して重大な問題だけ通知する `check-daily-report.sh` を追加した。
- **2026-11-10（切り出し要約）**: 送信の入力を、日次の切り出し要約（`slice-sessions.sh`）に切り替えた。
  git 収集も同じ区切りで絞る。`--overwrite`（既存サマリーを引き継がず作り直す）とペイロード保存
  （`daily-slices/<日付>/payload.txt`）を追加。`LANG=C.UTF-8` を固定し、予算を cron でも文字数で数える。
- **2026-11-10**: 送信が `Argument list too long` で落ちる不具合を修正（本文を argv ではなくファイル経由で渡す）。
  8/25・10/9・10/13・10/16・10/20・11/4 の6回発生しており、予算の 60,000 より手前に argv の上限
  （128KiB）があった。cron は LANG 未設定のため `${#payload}` はバイト数を数えている点にも注意。
  あわせて過去日を再生成する `--date YYYY-MM-DD` オプションを追加し、発火ログに対象日を出すようにした。
  ルーティンの手順7を「close 済みでも Issue 本文を issue_write で更新し、git 操作はしない」に変更し、
  blog への反映は life の `daily-to-blog.yml` に `issues: edited` トリガーで移した。
  手順2・4もクラウドで GraphQL が 403 になる `gh issue list` をやめ、REST の search API に変更。
- **2026-08-19**: サマリーの肥大化を是正。8/17改訂で入れた「1項目が数行になってよい」に上限が無く、
  8/17-18の実績が平常の約3.5倍（1,300字→4,866字）になっていた。入力量ではなく圧縮率の変化
  （7%→17〜20%）が原因。「結論1〜2文・経過を書かない」「1階層のみ」「網羅を字数より優先」に変更。
  本番と同じ opus-5 で08-18の実データを再現し3案を比較した結果、**数値上限（150字等）は
  opusでは項目削除の口実として働き網羅が8/12に低下**したため、数値を使わない案を採用（網羅12/12・
  4,419→2,775字）。haikuでは逆の結論が出るため、この種の検証は本番モデルで行うこと。
- **2026-08-17（2回目）**: 3ヶ月ぶんの実測を踏まえてプロンプトを改善。
  Work/Personalの判定を「提出・共有するか」に変更、Personalの件数表記を廃止、
  「なし」断定を禁止、自分のPRへの指摘対応を「自分の作業」と明示。
  要約側（`summarize.sh`）も【レビュー作業】の定義を修正（`34ff0a3`）。
- **2026-08-17**: worktreeのコミットを本体リポジトリへ集約（`eee206c`）。ルーティンのプロンプトに
  書式テンプレートを埋め込み、削除済み SKILL.md への参照2箇所を除去。モデルを
  `claude-opus-4-8` → `claude-opus-5` に更新。
- **2026-08-10**: Thunderbirdメールを情報源に追加。対話用の daily-review スキルを削除。
- **2026-06-10**: 日報生成を `claude -p` からクラウドルーティンへ移行。
