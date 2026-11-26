# worktree のセッションで、仕上げ（マージ・本体への反映・片付け）まで Claude が済ませる

## 何のため

`claude -w` で起動したセッションは、Claude Code の worktree isolation checks に守られている。本体のチェックアウトに向けた git（`git -C`、`cd` してからの git、`!` で打ったコマンドも含む）は止められ、この守りは設定で切れない（公式ドキュメント）。

そのため dotfiles を直したあと、毎回次の往復が起きている。

- Claude が通らないコマンドを渡す（`!` 付き・`git -C`）
- ユーザーが別のペインに移って本体の pull を手で打つ
- worktree の片付けも中からできない

ユーザーの望み: worktree は使っても使わなくてもよい。使うなら、Claude が自分で片付けまで済ませるのが一番よい。

## 実測で分かったこと（2026-11-25〜26）

- `claude -w` のセッションでも ExitWorktree は使える。keep で抜けると本体に戻り、守りが外れて本体で git を打てる
- ExitWorktree の remove は、フックで作った worktree だと「状態を確かめられない」で止まり、`discard_changes: true` を要求された。中身が空でも同じだった（1回の観測。原因は推測）
- WorktreeRemove フックは本体を起点に `git worktree remove`・`git branch -d` を打て、守りは掛からない
- 本体はたいてい別作業の変更を抱えている（lazygit の設定・追跡していないファイル）。さらに `pull.rebase=true` なので、`git pull` は手元に変更があるだけで断る。`git fetch` して `git merge --ff-only origin/main` なら、重なりが無い限り変更を残して進められた
- worktree の中から `git push origin HEAD:main` は通る（本体のチェックアウトに触らないため）
- keep で抜けたあとの `/worktree rm` は、`--force` なしで worktree とブランチを消せた。止まるのはスキルの削除確認の1回だけ

## やること・やらないこと

- やる: 仕上げの流れを決め、Claude がそのとおりに動けるよう rules に書く。本体を進める部分は決まった条件で動くスクリプトにする。フックの安全の穴を塞ぐ
- やらない: 守りを外す起動（`-w --tmux`）。cron で本体を勝手に追いつかせること。WorktreeRemove フックで本体を進めること（あとで保険が欲しくなったら足す）
- 範囲: 片付けと「`!` を案内しない」は `claude -w` を使う全リポジトリ。本体への反映（スクリプト）は dotfiles だけ。dotfiles は本体が「実際に読まれる場所」（`~/.claude/*` のリンク・hooks の `~/.dotfiles/scripts/...`）だから

## 作り方

### 検討した道

「何をするか」（本体を進める・片付ける）と「誰が始めるか」を分けて比べた。

| 誰が始めるか | 中身 | 採否 |
|---|---|---|
| α. Claude が仕上げで | worktree の中で取り込み → テスト → push → ExitWorktree(keep) → 本体でスクリプト → `/worktree rm` | 採用。困りごとの3つ（手打ち・止められる・片付け）に正面から答える唯一の案 |
| β. WorktreeRemove フック | 消したあとに本体を進める | 不採用。普段使いしない「終了時に消す」でしか動かない |
| γ. cron | 本体が数分おきに追いつく | 不採用。片付けが解決しない。動いているセッションの下で skills・hooks が入れ替わる |
| δ. 守りの無い起動（`-w --tmux`） | 守りそのものを外す | 不採用。本体では別のセッションも動いており、誤編集を止めるものが無くなる |

### 1. 本体を進めるスクリプト（dotfiles）

`scripts/claude-worktree/` に置く（`worktree_hook.py` と同じ場所・同じ Python・同じテストの作り方）。本体のパスを引数で受け取り、次の順に決める。結果は1行で出す。

1. 本体のブランチが `main` でなければ何もしない（理由: 「本体は <ブランチ> を使用中」）
2. `git fetch origin`
3. ローカルの `main` に `origin/main` に無いコミットがあれば何もしない（理由: 「本体の main に未 push のコミットが N 件」）
4. `git merge --ff-only origin/main`。git が断ったら（手元の変更と重なった等）何もせず git の理由を出す
5. 進めたら「<前> → <後>（N コミット）」、もう最新なら「最新」

`git pull` は使わない（`pull.rebase=true` で手元に変更があると断るため）。手元に変更があること自体は止める理由にしない（いつも何かある。重なりは git が判定する）。

### 2. フックの安全の穴を塞ぐ（全リポジトリ）

`worktree_hook.py remove` は「Claude Code が変更の有無を聞いてから呼ぶ」前提で `--force` を使っている。しかし実測では、Claude Code は状態を確かめられないまま `discard_changes: true` で素通しになり、ユーザーは何が消えるか見せられないまま「消す」を選ぶことになる。

remove の前に次を調べ、どれかがあれば消さずに終了コード 1 で失敗させ、何があるかを stderr に出す（Claude Code はディレクトリが残っていれば削除を失敗として扱う）。

- 追跡ファイルの変更
- 追跡していないファイル（`.gitignore` されたものは数えない）
- どのリモートブランチにも無いコミット

中身を見て消したいときは `/worktree rm` を使う（状態を表示して確認してから `--force` する）。既存テストのうち「変更があっても消す」「手元だけのコミットがあればディレクトリは消してブランチは残す」は、この方針に合わせて書き換える。

### 3. rules（全リポジトリ・自動で読まれる場所）

`.claude-global/rules/worktree.md` に「仕上げ」の節を足す。

- worktree の外（本体）での操作が要るときは、ExitWorktree(keep) で抜けてから自分で打つ。`!` 付きや `git -C` のコマンドをユーザーに渡さない
- ユーザーの「マージして」「片付けて」は、ExitWorktree で抜けることの依頼を含む（ツールの「頼まれたときだけ」を満たす）
- 抜けたあとは本体（共有）にいる。本体で編集しない。続きの作業があれば EnterWorktree で入り直す
- 片付けは `/worktree rm` で、自分の worktree だけを番号指定で消す。「まとめて削除」は別のセッションの worktree も対象に入るので使わない
- dotfiles の「マージして」は次の順。finishing-a-development-branch の Option 1（本体で checkout・pull）より優先する
  1. worktree の中で `git fetch` → `git merge origin/main` → テスト
  2. `git push origin HEAD:main`（早送り。force はしない）と、ブランチの push
  3. ExitWorktree(keep)
  4. 本体を進めるスクリプトを流し、結果の1行を伝える（進まなかったら理由を伝える）
  5. `/worktree rm` で自分の worktree を消す。リモートブランチの削除は別に聞く

`.claude-global/rules/command-handoff.md` に1行足す: worktree で隔離されたセッションでは `!` も同じ守りに掛かる。本体向けのコマンドは自分で ExitWorktree して打つ。どうしてもユーザーに頼むなら、別のペインで打つ前提で `!` を付けずにクリップボードへ入れる。

agent-memory の `user-preferences/dotfiles-merge-to-main.md` は、手順を rules に移したことを書き、古い手順（「自分の worktree で `git checkout main`」）を消す（agent-memory スキルで更新する）。

## 作る人に任せること

- スクリプトの名前・終了コードの分け方・出力の細かい文言
- フックの検査で使う git コマンド（`status --porcelain`・`rev-list --not --remotes` 等）
- rules の文の細部（既存の rules の書き方に合わせる）
