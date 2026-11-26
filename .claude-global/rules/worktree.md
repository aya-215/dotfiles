# worktree の作り方と消し方

## 作る

- `claude -w <ブランチ名>` で起動するか、作業の途中なら EnterWorktree で作る。素の `git worktree add` は使わない（Claude Code が片付けられない worktree になる）
- 置き場所とブランチ名は WorktreeCreate フック（`~/.dotfiles/scripts/claude-worktree/worktree_hook.py`）が決める。決まりは `~/.dotfiles/docs/superpowers/specs/2026-11-24-claude-worktree-hooks-design.md`
- ブランチ名はリポジトリの決まりで付ける（ebase-portal-chat なら `feat/<issue>-<説明>`）。PR の続きは `-w "#<番号>"`
- 名前に使えるのは英数字・`.`・`_`・`-`・`/` だけ。日本語のブランチ名が決まりのリポジトリ（hankyu・pilot の GitBucket）は英数字で作り、push の前に `git branch -m <決まりの名前>` で直す
- `/worktree add` も同じスクリプトで作る

## 仕上げ

worktree の中のセッションは、本体に向けた git（`git -C`、`cd` してからの git、`!` で打ったものも）を Claude Code の守りに止められる。この守りは切れない。

- 本体での操作が要るときは、ExitWorktree（keep）で抜けてから自分で打つ。`!` 付きや `git -C` のコマンドをユーザーに渡さない
- ユーザーの「マージして」「片付けて」は、ExitWorktree で抜けることの依頼も含む
- 抜けたあとは本体（別のセッションと共有）にいる。本体で編集しない。続きがあれば EnterWorktree で入り直す
- 片付けは `/worktree rm` で、自分の worktree だけを番号で選んで消す。「まとめて削除」は別のセッションの worktree も対象に入るので使わない
- dotfiles の「マージして」は次の順で行う。finishing-a-development-branch の「本体で checkout・pull」より優先する
  1. worktree の中で `git fetch` → `git merge origin/main` → テスト
  2. `git push origin HEAD:main`（早送り。force はしない）と、ブランチの push
  3. ExitWorktree（keep）
  4. `python3 -I ~/.dotfiles/scripts/claude-worktree/sync_main.py` で本体を進め、出た1行を伝える。終了コード 3 は理由を伝えて止まる（本体が main でない・未 push のコミットがある・手元の変更と重なった）。1 は fetch の失敗
  5. `/worktree rm` で自分の worktree を消す。リモートブランチの削除は別に聞く

## 消す

- 消すのは、Claude Code がセッション終了時に聞いてくる「消す」か、`/worktree rm`
- `/handoff` で引き継ぐときは、終了時に「残す」を選ぶ（返事のあとの修正をその worktree でやるため）。マージされたら `/worktree rm`
- 素の `rm -rf` や、手で `git worktree remove --force` を打たない
- 終了時の「消す」と ExitWorktree の remove は、変更・追跡していないファイル・未 push のコミットがあるとフックが消さずに残す。そのときは `/worktree rm` で中身を見て消す
