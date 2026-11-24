# worktree の作り方と消し方

## 作る

- `claude -w <ブランチ名>` で起動するか、作業の途中なら EnterWorktree で作る。素の `git worktree add` は使わない（Claude Code が片付けられない worktree になる）
- 置き場所とブランチ名は WorktreeCreate フック（`~/.dotfiles/scripts/claude-worktree/worktree_hook.py`）が決める。決まりは `~/.dotfiles/docs/superpowers/specs/2026-11-24-claude-worktree-hooks-design.md`
- ブランチ名はリポジトリの決まりで付ける（ebase-portal-chat なら `feat/<issue>-<説明>`）。PR の続きは `-w "#<番号>"`
- 名前に使えるのは英数字・`.`・`_`・`-`・`/` だけ。日本語のブランチ名が決まりのリポジトリ（hankyu・pilot の GitBucket）は英数字で作り、push の前に `git branch -m <決まりの名前>` で直す
- `/worktree add` も同じスクリプトで作る

## 消す

- 消すのは、Claude Code がセッション終了時に聞いてくる「消す」か、`/worktree rm`
- `/handoff` で引き継ぐときは、終了時に「残す」を選ぶ（返事のあとの修正をその worktree でやるため）。マージされたら `/worktree rm`
- 素の `rm -rf` や、手で `git worktree remove --force` を打たない
