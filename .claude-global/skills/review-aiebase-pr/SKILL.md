---
name: review-aiebase-pr
description: Use when quickly checking a pull request in ebase-portal-chat, ebase-middleware-mcp (eb-api-mcp), or eb-api-extended — 「ざっとレビュー」「ざっと確認」「観点チェック」「このPR見て」「修正来た」「再レビュー」「指摘が直ったか確認」, or when /review-pr is too heavy for the PR. Also covers reviewing from a PR worktree (epc-* / emm-*).
allowed-tools: Bash, Read, Grep, Glob
version: 1.0.0
---

# eBASE AI 3リポジトリの PR ざっと確認

portal-chat → eb-api-mcp → eb-api-extended(JSP) は1つの機能が複数 PR に分かれる。
このスキルは、その3リポジトリ専用の観点を **一度に** 当てて所見を出す。対話で深く読むのは `/review-pr` の役割。

| やりたいこと | 使うもの |
|---|---|
| 観点を一通り当てて所見を一覧で見る／修正の再確認 | このスキル |
| 設計意図を対話で1つずつ理解する | `/review-pr` |
| 所見のうち何を指摘するか決める | `/triage-review-findings` |
| コメント文面を書く | `/write-review-comment`（投稿はユーザーが行う） |

## Step 0: 準備（毎回）

1. 観点チェックリストを読む: `~/.claude/skills/review-aiebase-pr/references/perspectives.md`（git 管理外。無ければ「references が無い」と伝えて一般観点で進める）
2. 関連メモリを検索する: `rg "^summary:" ~/.claude/skills/agent-memory/memories/ --no-ignore --hidden` を PR のキーワード（機能名・ボリューム番号・ブランド名・ツール名）で絞り、該当する本体を読む
3. 事実を一括で集める（判断を含まないスクリプト）:

```bash
python3 ~/.claude/skills/review-aiebase-pr/scripts/pr_context.py [PR番号] [--repo ebase-dev/<repo>]
```

出力: PR概要・PR本文・closing issue 本文・変更ファイル・作業場所（PRのworktreeの有無とHEADのずれ、base との衝突）・CI・PRプレビュー（最新headか、ブランド）・関連PR/issue（他リポジトリの短縮表記も含む）・時系列・他者の発言全文（claude[bot] を含む）・再レビュー情報（最後の CHANGES_REQUESTED を基準に、自分の過去の指摘全文と、それ以降の修正コミット）。

## Step 1: モード判定

- 「再レビュー情報」に自分の過去の review/comment がある → **再レビューモード**（Step 3R）
- 無い → **初回モード**（Step 2〜3）
- 本体コードの変更（テスト・ドキュメント・評価ケース・スナップショットを除く）がおおむね100行以下で、関連PRも無い → 観点 A・K だけ当てて「軽く見るので十分」と結論してよい。設計論点を量産しない
- 依頼文と事実が食い違うとき（「修正来た」なのに基準以降の修正コミットが0件 等）は、出力の見出し直下に1行で明記する

## Step 2: コードの読み方（作業場所のルール）

| 状況 | 読み方 |
|---|---|
| PRのworktreeがあり HEAD が一致 | worktree 内で読む（テストは下記の使い捨て worktree で回す） |
| worktreeがあるが HEAD 不一致 | `git -C <worktree> show/diff origin/<head>` で読む。**pull / merge / checkout / reset しない** |
| worktreeが無い | 本体cloneで `git show origin/<head>:<path>`、または `gh pr diff N --repo R` |
| eb-api-extended | Tomcat が直接読む作業ツリー。**checkout しない**。`git show` で読む。git の前に `rm -f .git/index.lock` |
| 相手側リポジトリの現行実装 | `git -C <clone> fetch` → `git -C <clone> show origin/main:<path>`、`git grep <pat> origin/main` |
| main との衝突確認 | `git merge-tree --write-tree --name-only origin/main origin/<head>`（作業ツリーに触れない） |

テストを回す・相手側 main をローカル起動するときは、scratchpad に使い捨ての worktree を切る。PR の worktree や本体 clone では回さない（ユーザーが作業中のことがあり、未コミットの lockfile やテストキャッシュを汚す）:

```bash
git -C <clone> worktree add --detach <scratchpad>/wt origin/<head>
# node_modules は package.json の差が小さければ symlink で借りる（monorepo はルートと apps/portal-ui の2か所）。差が大きければ npm ci
# 検証用テストは vitest の include 対象（例: lib/__tests__/zz-*.test.ts）に置く
# 片付け: 借りた symlink を rm → git -C <clone> worktree remove --force <scratchpad>/wt
```

zsh では `"$ref:path"` の `:a` 等が修飾子として展開される。`git show "${ref}:path"` と波括弧で書く。

pr_context が「残っている scratchpad worktree」を出したら、片付け候補としてユーザーに伝える（勝手に消さない）。

## Step 3: 初回モード

1. PR本文・closing issue（背景・実測・検討した案）を読み、diff を読み、PR を **「要するに〜した」1〜2文** にする
2. references の観点 A〜M を当てる。当てる条件に該当しない観点は飛ばす。関連PRがある、または repo のプロンプト・設定を eBASE へ手で転記する変更なら D（リリース順序）は必ず当てる。評価ケース・期待値を変える PR には I（どのランナーで測り、変更したコード経路を通るか）を必ず当てる
3. claude[bot] 等の既存レビュー: 作者が対応済みのものは繰り返さず、「既存指摘 n 件は対応済み（テストで確認）」を扱い=記録の1行にまとめる。未対応や対応が不十分なものだけ所見にする
4. 所見ごとに一次情報で裏取りし、CONFIRMED / PLAUSIBLE / REFUTED を付ける（Step 4 の範囲で自分で検証する）
5. Step 5 の形式で出力する

## Step 3R: 再レビューモード

1. 自分の過去の指摘（pr_context の全文）を1件ずつ番号付きで並べる
2. 各指摘について、修正コミット（`git show <sha>`）と作者の返信を照合し、状態を付ける
   - 対応済み（根拠: commit・file:line・実機結果）／部分対応／未対応／方針変更で合意／相談中（未決）
3. 作者の返信にある「確認しました」は、どの経路・権限・値で確認したかを読み、足りなければ自分で確かめる
4. 修正コミットで新たに入ったものに、初回と同じく観点 A〜M を条件に応じて当てる（範囲は修正コミットだけ。main 取り込みは除く）
5. Step 5R の形式で出力する

## Step 4: 検証（自分でやる範囲）

**読み取りの検証は許可を求めずに自分で行う。** ユーザーや作者に「確認してもらう」と投げない。

- PRプレビュー（URL は PR の github-actions[bot] コメント）や MCP に JSON-RPC（`tools/call` / `resources/read`）を送る。プレビューが古い head なら、そう明記する。プレビューのブランドが変更対象のブランドと違えば、プレビューでの確認は根拠にしない。その場合は対象ブランドで dev を起動して、アプリ経由の挙動まで自分で確かめる（未確認欄に回さない）
- MCP の接続先: PR プレビュー（MCP の PR）→ dev の `EB_API_MCP_URL`（`npx dotenvx get EB_API_MCP_URL -f .env`）→ agent-memory の順に探す。見つからなければ未確認欄に「接続先不明」と書く
- JSP / eB-API を直接叩く。必要なら全件を走査する
- `npx vitest run <関連パス>`、`npm run type-check`。テストが効いているかは、修正を戻して落ちることで確かめる
- dev サーバ: 空いているポート（3100番台）で起動する。env は `npx dotenvx run --overload -f .env -f .env.local -f <scratchpad>/override.env -- ...`（override.env を最後に置く）。worktree で復号が要るときは本体cloneの `.env.keys` を `-fk` で渡す
- dev を止めるのは自分が起動した PID だけ。`/proc/<pid>/cwd` で確認する。`pkill -f` は使わない
- ユーザーが worktree 名の tmux セッションで dev を動かしているときは、`tmux capture-pane` でログを読み、再起動しない

**書き込みを伴う検証**（eBASE の値・共有フラグ等）は、内容を説明して承認を得てから行う。1項目ずつ行い、必ず元の値に戻して読み戻しで確認する。auto mode が拒否する操作（JSESSIONID の取り出し等）は、`!` で実行できる1行コマンドを用意してユーザーに渡す。

## Step 5: 出力形式（初回）

です・ます調。初回はこの形、再レビューは Step 5R の形で出し、テンプレート以外のセクションは足さない。

```
## <repo>#<N> <title>
作者 / +a -d / CI: SUCCESS n・FAILURE n・SKIPPED n / base との衝突: なし|あり / プレビュー: 最新head|古いhead、ブランド <brand>

**要するに**: <1〜2文>
**関連**: <他リポジトリPR・前提・マージ順序。無ければ「なし」>

### 所見
| # | 扱い | 重要度 | 判定 | 観点 | 内容と根拠（file:line / 実測値） |
|---|---|---|---|---|---|
| 1 | コメント | Critical | CONFIRMED | D | ... |

### 未確認（実機で確かめたいこと）
- <何を> — <どう確かめるか（コマンド）> — 読み取り: 実施済み/未 ／ 書き込み: 要承認

### 判定の目安
Approve / Request Changes / 保留 — <理由1行>

次の一手: <1行>
```

- 扱い: コメント=PRコメントにする / issue=後続 issue / 記録=指摘しない（記録だけ）
- 判定: 事実と影響で確度が違うときは「CONFIRMED（事実）/ PLAUSIBLE（影響）」のように併記する
- 重要度: Critical / Important / Nit。決着しない論点は重要度なしで「設計論点」と書く
- 所見が無ければ表を出さず「確認した範囲で指摘なし」と書き、確認した観点を1行で並べる

## Step 5R: 出力形式（再レビュー）

```
## <repo>#<N> 再レビュー（前回 <日時> @ <sha> 以降の修正 <k> 件）

### 前回の指摘の対応状況
| # | 前回の指摘（要約） | 状態 | 根拠 |

### 修正で新たに入ったもの
<所見表（Step 5 と同じ列）。無ければ「なし」>

### 未確認（実機で確かめたいこと）
<Step 5 と同じ形式。無ければ「なし」>

### 判定の目安
Approve / Request Changes / 保留 — <理由1行>

次の一手: <1行>
```

次の一手の例: 「深掘りは /review-pr、指摘の取捨は /triage-review-findings、コメント文面は /write-review-comment」。

## 守ること

- PR のブランチ・worktree を書き換えない（「確認して」は読むだけ）。他人の PR のコードを編集しない
- PR へのコメント投稿・issue 起票はしない。ユーザーの明示指示があるときだけ行う
- 実機確認の範囲を大きく言わない（「Administrator でのみ確認」のように、権限・経路・値を書く）
- 推論を「判明した」と書かない。作った例を実データのように出さない
- 「作者の意図」「定義書どおり」「先方仕様」を、それだけで根拠にしない
- ユーザーが持ち込んだ論点と Claude が出した論点を区別して書く
- 頼まれていないデプロイ・リリースの話に進まない
- 略語（FE 等）を使わない。簡潔に書く

## よくある失敗

| 失敗 | 正しくは |
|---|---|
| worktree が遅れていたので `git merge --ff-only` / `pull` した | `origin/<head>` を show/diff で読む |
| `pkill -f "next dev"` で他の worktree のサーバまで止めた | 自分の PID だけ止める |
| 「作者に確認してもらう」で終えた | 読み取りで確かめられることは自分で実測してから提案する |
| 認証なしで 200 だったので問題なしとした | 想定外に強い権限の経路で通っていないか、一般ユーザーのセッションで確かめる |
| 軽い PR に設計論点を7件並べた | 観点 A・K だけで「軽く見るので十分」と結論する |
| 再レビューで main 取り込みの差分まで所見にした | 修正コミットだけを対象にする |
| 別ブランドのプレビューで、特定ブランド限定の変更を「確認済み」とした | ブランドが違うプレビューは根拠にしない |
| PR の worktree でテストを回して lockfile やキャッシュを汚した | scratchpad の使い捨て worktree で回す |
