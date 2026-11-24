# Claude Code の worktree をフックでうちの決まりに合わせる（設計）

作成: 2026-11-24。司令塔の設計の続きで、worktree の作り方・置き場所・消し方を決めた。

## 目的と理由

- 作業が終わった worktree を消そうとすると、auto mode に止められることが多い（素の `rm -rf` や `--force` 付きの削除）
- Claude Code の `claude -w <名前>`（中の仕組みは EnterWorktree）に worktree を作らせれば、セッションを閉じるときに Claude Code が片付けてくれる。superpowers も「Claude Code 自身の仕組みがあればそれを使う」としている
- ただし Claude Code の既定はユーザーの決まりと合わない。そこで `WorktreeCreate` / `WorktreeRemove` フックで作り方を差し替える
  - ブランチ名が `worktree-<名前>` になる。AI 関連のリポジトリはリポジトリの決まり（`feat/<issue>-…` 等）に従ってほしい（ユーザー）。dotfiles は個人リポジトリなので何でもよい
  - `/mnt/d` の本体（hankyu・eb-api-extended など Tomcat が直接読む）で中に作ると `webapps/<app>/.claude/worktrees/` ができ、Tomcat の公開範囲に入る恐れがある。`/mnt/d` の本体で worktree を作ることは実際にある（ユーザー）
  - `.env.local` などのコピーと node_modules の用意が無い
- worktree を ghq で開ける必要はない。Claude 経由で指示を出すので、わざわざ開かなくてよい（ユーザー）

## ゴール

1. `claude -w <名前>`・EnterWorktree・サブエージェントの `isolation: worktree` で作る worktree が、次の決まりで作られる
   - 置き場所: 普通のリポジトリは `<本体>/.claude/worktrees/<スラッグ>`。本体が `/mnt/` の下なら `~/worktrees/<本体のフォルダ名>-<スラッグ>`
   - ブランチ: 下の「ブランチの決め方」
   - `.env.local`・`.env.keys` を同じ相対パスへコピーし、npm のリポジトリでは node_modules をハードリンクで複製する
2. worktree を消すとき（Claude Code がセッション終了時に消す・ExitWorktree）、ブランチもマージ済みなら消える
3. git がどのリポジトリでも `.claude/worktrees/` を無視する
4. `/worktree add` も同じ決まりで作り、`/worktree rm` は新しい置き場所も拾う
5. rules に「worktree は `claude -w` で作り、消すのは Claude Code の終了処理か `/worktree rm`。素の `rm -rf` や手での `--force` はしない」と書く
6. 司令塔は新しい作業を `claude -w <ブランチ名> '<プロンプト>'` で起動する

## やらないこと

- ebase-middleware-mcp の eslint の除外に `.claude/` を足す PR（ユーザーが次にそのリポジトリを触るときに出す）
- 今ある worktree（本体の隣 `../<略称>-<ブランチ>`）の移動。`/worktree rm` で順に消える
- temp_wsl の削除の仕組み（別の話。場所の判定とゴミ箱送りのスクリプト案があるが未決）
- 依存のインストール（`npm install` 等）。Claude Code のドキュメントどおり、作業するセッションの Claude に任せる
- 日本語のブランチ名をフックで作ること（下の制約）

## 失敗とみなすこと

- フックが失敗して worktree が作れず、`claude -w` が使えなくなる（フックの失敗は worktree 作成の失敗になる）
- push もマージもしていないコミットを持つブランチを消す
- ユーザーが前から持っている worktree（本体の隣の `../epc-…` や `/mnt/d` の本体）を、フックが作ったものとして Claude Code に消させる
- `/mnt/d` の本体の中に worktree を作る
- 既にあるブランチ（PR のブランチ等）と同名なのに、新しいブランチを作って PR に push できない

## 制約（11/24 の実測とドキュメント）

- フックの stdin は `session_id`・`transcript_path`・`cwd`・`hook_event_name`・`name` だけ。ブランチ・起点・PR 番号は来ない。`cwd` は本体のルート
- 出力: stdout の最後の空でない行に worktree の絶対パス。失敗するかパスが無いと作成は失敗する。`.`・`..` を含むパスは拒否される。タイムアウトは 600 秒
- `name` の実測（Claude Code 2.1.331）
  - `-w feat/1296-mensapo` → `feat/1296-mensapo`（`/` はそのまま）
  - `-w "#1234"` → `pr-1234`
  - `-w 構成品選択で自レコード除外` → フックの前に Claude Code が拒否（英数字・`.`・`_`・`-` だけ、`/` 区切りの各部分は空にできない）
  - 自動生成なら `bold-oak-a3f2` のようなスラッグ
- 本体が `/mnt/d` にあっても、リポジトリの外のパスを返せば通る（実測）
- `WorktreeRemove` の stdin は共通フィールドと `worktree_path`。フックが作った worktree にだけ呼ばれる。終了コード 0 でディレクトリが残ると Claude Code は git に任せないので、フックが自分で消す。Claude Code はフックが作った worktree のブランチを消さない
- サブエージェント終了時は `WorktreeRemove` が呼ばれない（`cleanupPeriodDays` の掃除か `/worktree rm` に任せる）。`-p` の非対話実行も自動では消えない
- 作業の途中で `.claude/worktrees/` の外の worktree に入るときは、毎回承認を求められる（bypassPermissions 以外は止められない）。`/mnt/d` の本体のときだけ外に置くのはこのため
- `--worktree` と `--tmux` を併用するとプラグイン由来のフックは動かない。今回はユーザー設定（`~/.claude/settings.json`）に書くので当たらない
- ebase-middleware-mcp の `eslint .` は中に置いた worktree を拾う（640 ファイル中 317、実測）。eslint は git の除外設定を読まないので、global gitignore では直らない。prettier は `.gitignore` を見るので拾わない
- フックのスクリプトは `~/.dotfiles/scripts/<名前>/` に置く流儀（既存の claude-pane-session 等）
- 決定的な処理はスクリプト、Claude の判断と分ける（`rules/learned-rules.md`）

## 作り方の案（Approaches）

| 案 | 内容 | 取捨 |
|---|---|---|
| A. 今のまま（本体の隣） | ghq で開ける | ghq の一覧に混ざる・`/mnt/d` で webapps に生える・消すとき止められる |
| B. `~/worktrees` にまとめる | 置き場所が1か所 | Claude Code の片付けに乗らない。作業途中で入るたびに承認 |
| C1. `claude -w` をそのまま | 片付けは Claude Code | ブランチ名が `worktree-<名前>`・`/mnt/d` で危ない |
| **C2. `claude -w` ＋ フック** | 片付けは Claude Code、ブランチ・場所・コピーはうちの決まり | 作る量が一番多い。ブランチは WorktreeRemove で消す必要 |
| bare repo 構成 | 全ブランチ対等 | clone を作り直す。Tomcat の本体が普通の checkout である必要があり合わない |

**選んだもの: C2、置き場所は (i)「中に置き、`/mnt/` だけ外」**（ユーザー「C2で一気に作ってしまってもいい」「i」）

## 決まった中身

### ブランチの決め方（上から順に最初に当たったもの）

1. `pr-<n>`: GitHub なら `gh pr view <n> --json headRefName` の head ブランチを origin から取ってそれを開く（レビューの修正をそのまま push できるように）。GitBucket は `refs/pull/<n>/head` を取り、ブランチ `pr-<n>` にする
2. 手元か `origin/` に同名のブランチがある: それを開く（origin だけなら追跡ブランチを作る）。そのブランチが本体か別の worktree で checkout 中なら、作らずに失敗し「<場所> で使用中。そこで claude を起動して」と stderr に出す（既存の場所を返すと、Claude Code がフックの作ったものとみなして終了時に `--force` で消しかねないため。Claude の判断）
3. 先頭が既知の種類（`feat/`・`fix/`・`docs/`・`chore/`・`refactor/`・`test/`・`hotfix/`・`ci/`・`perf/`・`build/`・`style/`）: そのまま新しいブランチにする
4. 個人リポジトリ（origin が `github-aya215:` か `github.com/aya-215/`）: 名前をそのまま新しいブランチにする
5. それ以外: `feat/<名前>` で新しいブランチにする
- 新しいブランチの起点は `origin/main`、無ければ `origin/master`、無ければ本体の HEAD。作る前に `git fetch origin` する（失敗しても続ける）
- 日本語のブランチ名（hankyu・pilot の GitBucket リポジトリ）は `-w` で渡せない。英数字の名前で作り、push する前に Claude が `git branch -m` でリポジトリの決まりに合わせる（rules に書く）

### 置き場所

- スラッグ: 名前の `/` を `-` にしたもの（`feat/1296-mensapo` → `feat-1296-mensapo`）
- 本体のルート（`git rev-parse --show-toplevel`、cwd から）が `/mnt/` で始まる: `~/worktrees/<本体のフォルダ名>-<スラッグ>`
- それ以外: `<本体>/.claude/worktrees/<スラッグ>`
- 置き場所が既にあり、その worktree が git に登録済みなら、作らずにそのパスを返す（同じ名前で入り直せるように）

### 作った後

- 本体から `.env.local`・`.env.keys` を探し（`node_modules`・`.claude/worktrees` の下は除く）、同じ相対パスへコピー
- 本体に `package-lock.json` があれば、深さ3までの `node_modules` を、worktree 側に親フォルダがあるときだけ `cp -al` で複製。失敗したらその分は消して先へ進む（今の `/worktree add` と同じ）。symlink は使わない（Turbopack が拒否する）
- 進み具合は stderr に出し、stdout の最後の行はパスだけにする

### 消すとき（WorktreeRemove）

1. `worktree_path` のブランチ名を取る（`git -C <path> branch --show-current`）
2. 本体（`git -C <path> rev-parse --git-common-dir` の親）から `git worktree remove --force <path>`。Claude Code は変更があればユーザーに消すか聞いてから呼ぶので `--force` でよい
3. `git branch -d <ブランチ>`。git は upstream があれば upstream に、無ければ本体の HEAD に入っているかで判定するので、消えるのは「手元にしか無いコミットが無い」ブランチだけ（push 済みで PR が未マージのブランチは手元から消えるが、origin に残るので失うものは無い）。手元にしか無いコミットがあれば git が断るので残す（stderr に一言）。squash マージ済みのブランチは `-d` では消えないので、`/worktree rm`（PR の MERGED を見る）に任せる（Claude の判断）
4. どこで失敗しても、ディレクトリが残っていれば終了コード 1（Claude Code に「消せなかった」と伝わる）

### 周り

- `modules/git.nix` の `ignores` に `.claude/worktrees/` を足す（反映は `home-manager switch`）
- `.claude-global/settings.json` の `hooks` に `WorktreeCreate` と `WorktreeRemove` を足す（`update-config` スキルの流儀で）
- `/worktree add` は同じ作成スクリプトを `--name <ブランチ名>` で呼ぶ。`/worktree rm` の `worktree_scan.py` が `<本体>/.claude/worktrees/*` と `~/worktrees/*` を拾うことを確かめ、拾わなければ直す
- rules に `worktree.md` を足す（ゴールの 5 と、日本語ブランチ名の `git branch -m`）
- 司令塔の SKILL.md の起動手順を `claude -w` に変える（既にある worktree の続きなら、その場所で `claude`）
- 引き継ぎ（`/handoff`）のとき: worktree は残す。相手の返事のあとの修正はその worktree でやるため。`claude -w <名前>` で作った名前付きの worktree は、終了時に Claude Code が「残す／消す」を聞くので「残す」を選ぶ。`/handoff` の SKILL.md の最後に「終了時に worktree を残すか聞かれたら残す」と1行足す。再開は今までどおりメモの作業場所で `/pickup`（作業場所は残っている）。マージされたら `/worktree rm` で消す（Claude の判断）

## 作る人に任せること

- スクリプトの言語と分け方（既存に合わせるなら Python 標準ライブラリ、`python3 -I`）。作成と削除は別のスクリプトでも1本でもよい
- テスト（一時ディレクトリに本物の git リポジトリを作る。GitHub の PR 取得は `gh` を差し替える）
- 実機確認: 試験用リポジトリで `claude -w` を流して、置き場所・ブランチ・コピー・削除を確かめる。試験用に作ったものは最後に消す（ユーザー許可済み）

## 関連

- 司令塔の設計: `docs/superpowers/specs/2026-11-24-commander-design.md`
- 今の worktree スキル: `.claude-global/skills/worktree/`（`SKILL.md`・`scripts/worktree_scan.py`）
- Claude Code: https://code.claude.com/docs/en/worktrees.md 、https://code.claude.com/docs/en/hooks.md
