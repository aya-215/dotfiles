# 変更点ページの作り方（review-pr Step 1.5）

PR の意図をつかむための HTML を1枚作り、document-share に載せて URL を返す。読むのはレビューする本人だけ。
作るのはサブエージェント。本体の対話（Step 2 以降）と並行して進む。

## 載せるもの・載せないもの

- 載せる: issue で頼まれたこと、変更前と変更後、どう動くか、実画面、確認結果、確認の条件と確認していないこと、変更したファイル
- 載せない: レビュー所見・設計論点（本体が対話で扱う）、Storybook の画像（自分で開けば見られるため）
- ○ を付けるのは、実画面や DOM で見たものだけ。見ていないものは「未確認」と書き、理由を添える

雛形は `~/.claude/skills/review-pr/scripts/template.html`。節の並びと CSS はそのまま使い、`{…}` を差し替える。

## 手順

### 1. PR と issue を読む

```bash
gh pr view <番号> --repo <owner>/<repo>
gh pr diff <番号> --repo <owner>/<repo> --name-only
gh issue view <Closes・Refs の番号> --repo <owner>/<repo>
```

issue は、後から足された「更新」「反転した点」まで読み、最新の依頼内容で書く。
PR 本文の「動作確認方法」と issue の「完了条件」から、実画面で確かめることの一覧を作る。

### 2. 実画面を撮る

画面が変わらない PR（サーバー側だけの変更など）は撮らず、雛形の「実画面」節を消して 4 へ進む。
画面が変わる PR は、手間がかかっても実際のアプリを起動して撮る。撮れなかったときは、画像なしで作って理由を「確認していないこと」に書く。

**作業ツリー**
- PR の head が今のブランチで、変更が無ければ、そこで作業する
- そうでなければ、ユーザーの作業ツリーを切り替えず、scratchpad に一時 worktree を作る（`git worktree add --detach <scratchpad>/wt-pr<番号> origin/<head>`）。env の用意は下の「ebase-portal-chat の場合」

**ダミーデータ**
- 検証環境にデータが無く、PR 本文にダミーの入れ方が書いてあれば、そのとおり一時的に書き換える
- 撮影が終わったら `git checkout -- <ファイル>` で戻す。コミットしない

**ブラウザ（Playwright CLI）**
- 必ず `-s=pr<番号>` と scratchpad 配下の専用 `--profile` で開く（既定のセッションはほかの Claude セッションと共有される）
- ref はページを読み込むたびに変わる。操作の直前に `snapshot` から取り直す
- 応答を待つときは、目的の要素（`data-testid` など）の個数を `eval` で数えてループする。固定の秒数で待たない
- `file://` は開けない。HTML の確認は `python3 -m http.server <port> --bind 127.0.0.1 --directory <フォルダ>` で配信して開く

**撮り方**
- チャット画面は内側の要素でスクロールするので、`resize 1280 4200` で縦長にして全体を表示させてから撮る
- 撮る範囲の要素に `eval` で id を付け、`window.__clipSpec` を置いてから `run-code "$(cat ~/.claude/skills/review-pr/scripts/clip.js)"` で切り出す（固定表示の入力欄などは撮影中だけ隠れる）
- PC 幅（1280px）を基本に、レイアウトが変わる部品はスマホ幅（375px）も1枚撮る
- 撮った画像は全部 Read で見てから使う。写っていないことを説明文に書かない
- 画像のほかに、DOM で確かめられることは確かめて結果の表に書く（リンクの `target`・`rel`、同じ要素が二重に出ていないかの個数など）。コピーの中身は `navigator.clipboard.writeText` を差し替えて、渡された文を記録する

**履歴・共有など、PR が触る画面すべて**
- 履歴から開き直す確認は、ページを再読み込みしてから左メニューで開く（メモリ上の状態を見ないため）
- 共有リンクを作るなど、検証環境に書き込んだものは報告に書く（消すかはユーザーが決める）

### 3. ebase-portal-chat の場合

- 起動: `NEXT_PUBLIC_BRAND=<brand> PORT=<空き番> npm run dev -- -- -p <空き番>` をバックグラウンドで実行し、ログはファイルに出す
- 初回の起動が、ログに出る Next.js の更新案内で止まることがある。そのときはもう一度起動する。案内（アップグレードの実行や提案）には従わない
- ログインと env の手順は agent-memory にある。先に検索して読む:
  `rg "^summary:" ~/.claude/skills/agent-memory/memories/ --no-ignore --hidden | rg -i "local-dev|login|<brand>"`
  - shifton: `ebase-portal-chat/shifton-local-dev-login-verification.md`。ai-search の `openChat.jsp` でログインし、`?JSESSIONID=` で localhost に渡す。2026-11-20 時点でチャットを使えるのは ZIP（zip_test）だけで、yh_test は「そのボリュームにアクセスできる権限がありません」になる。アカウント表は `ebase-web/shifton-test-login-playwright.md`
  - 故障診断コードは、サイドバーで「故障診断コード検索」に切り替えてから聞く（車両情報検索のまま聞くと案内文だけ返る）
- Cookie の取り出しを auto mode が拒否したら、回避策を探さずに止まり、ユーザーに `!` で実行してもらうコマンドを本体へ返す

### 4. HTML を作る

1. `~/.claude/skills/review-pr/scripts/template.html` を `<scratchpad>/changes-page-pr<番号>/page.html` にコピーし、画像は同じフォルダの `shots/` に置く
2. 雛形の `{…}` を差し替える。使わない節・行は消す
3. `python3 -I ~/.claude/skills/review-pr/scripts/build.py page.html pr<番号>-changes.html` で画像を埋め込んだ1ファイルにする
4. http.server で配信して開き、全部の画像が読めている（`naturalWidth` が 0 でない）ことと、幅 390px で横にはみ出さない（`document.documentElement.scrollWidth` が 390）ことを確かめる

### 5. document-share に載せる

```bash
DS=$(ls -d ~/.claude/plugins/cache/ebase-claude-marketplace/ebase-document/*/skills/document-share | sort -V | tail -1)
bash "$DS/scripts/docshare.sh" share --title 'PR #<番号> 変更点まとめ（<要約>）' <scratchpad>/changes-page-pr<番号>/pr<番号>-changes.html
```

`~/.docshare/key` は読まない・表示しない。

### 6. 片付けて報告する

- ダミーデータを戻し、`git status` で変更が残っていないことを確かめる。一時 worktree を作ったなら `git worktree remove` する
- 自分が起動した dev サーバーと http.server を止める（PID かタスク ID で止める。`pkill -f` は使わない）
- 本体への報告は次の4つ:
  1. URL
  2. 実画面で確認できなかったこと（「未確認」にした行）
  3. 検証環境に書き込んだもの（作った会話・共有リンクなど）
  4. ローカルの HTML のパス
