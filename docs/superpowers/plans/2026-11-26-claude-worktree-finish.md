# worktree のセッションで仕上げまで Claude が済ませる 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本体を進めるスクリプト `sync_main.py` を足す。WorktreeRemove フックが変更のある worktree を消さないようにする。仕上げの流れを rules に書く。

**Architecture:** どちらも `scripts/claude-worktree/` に置く（`worktree_hook.py` と同じ場所・同じ Python 標準ライブラリ・同じ unittest）。Claude が仕上げで呼ぶ順番は rules に書き、機械的な判定はスクリプトに置く。

**Tech Stack:** Python 3（標準ライブラリのみ）、git、unittest

**Spec:** `docs/superpowers/specs/2026-11-26-claude-worktree-finish-design.md`

## Global Constraints

- `git pull` は使わない（本体は `pull.rebase=true` で、手元に変更があると断る）。`git fetch` → `git merge --ff-only origin/main`
- 手元に変更があること自体は、本体を進めない理由にしない（重なりは git が判定する）
- force push・`--force` での削除はしない
- コードコメントは非自明な WHY だけを1行で書く（`.claude-global/rules/code-comments.md`）
- テスト: `python3 -m unittest discover -s /home/aya/.dotfiles/.claude/worktrees/feat-claude-worktree-finish/scripts/claude-worktree -p 'test_*.py'`（pytest は入っていない）
- メモリ（`~/.claude/skills/agent-memory/memories/`）は本体側にあって git の対象外。worktree の中からは守りで編集できないので、仕上げで ExitWorktree したあとに agent-memory スキルで更新する

## Review Focus

- 本体に別作業の追跡ファイル変更があり、取り込むコミットと重ならない → 変更を残したまま進める（Task 2 `test_advances_keeping_unrelated_local_change`）
- 取り込むコミットが本体の未コミット変更と同じファイルを触る → 進めず、本体も変更もそのまま（Task 2 `test_reports_git_refusal_on_overlap`）
- worktree に `.gitignore` されたものだけがある（`.superpowers/` など）→ 消してよい（Task 1 `test_remove_allows_ignored_files`）
- push 済みのコミットだけがある worktree → 消してブランチも消す（Task 1 `test_remove_pushed_commits_are_ok`）
- origin に届かない（認証・ネットワーク）→ 何も変えず失敗を1行で出す（Task 2 `test_fetch_failure`）

---

### Task 1: WorktreeRemove フックが、変更のある worktree を消さない

**Files:**
- Modify: `scripts/claude-worktree/worktree_hook.py`（`remove()`。検査用の関数を足す）
- Test: `scripts/claude-worktree/test_worktree_hook.py`（`RemoveTest`）

**Interfaces:**
- Produces: `unsafe_reasons(worktree_path: Path) -> "list[str]"`。空なら消してよい。要素は次の形
  - `追跡ファイルの変更 N 件`
  - `追跡していないファイル N 件`（ignored は数えない）
  - `どのリモートにも無いコミット N 件`（`rev-list HEAD --not --remotes`）
- `remove(worktree_path: Path) -> int`
  - `unsafe_reasons` が空でなければ消さない。stderr に `<path> は消さずに残しました: <理由を「・」でつなぐ>。中身を見て消すなら /worktree rm` を出し、1 を返す
  - 空なら `git worktree remove`（`--force` なし）→ 今と同じブランチの `-d` 削除

- [ ] **Step 1: 失敗するテストを書く（既存2本を置き換え、4本足す）**

```python
    def test_remove_refuses_local_only_commit(self):  # 旧 test_remove_keeps_branch_with_local_only_commit
        p = create("feat/wip", self.repo, home=self.home, gh_head=no_gh)
        commit_in(p, "a.txt")
        err = io.StringIO()
        with redirect_stderr(err):
            self.assertEqual(remove(p), 1)
        self.assertTrue(p.exists())
        self.assertTrue(branch_exists(self.repo, "feat/wip"))
        self.assertIn("どのリモートにも無いコミット 1 件", err.getvalue())

    def test_remove_refuses_untracked_file(self):  # 旧 test_remove_with_uncommitted_changes
        p = create("feat/dirty", self.repo, home=self.home, gh_head=no_gh)
        (p / "u.txt").write_text("x")
        # assert: remove(p) == 1、p.exists()、stderr に「追跡していないファイル 1 件」

    def test_remove_refuses_tracked_change(self):
        # commit_in(p, "a.txt") → git push -q -u origin HEAD → a.txt を書き換え
        # assert: remove(p) == 1、p.exists()、stderr に「追跡ファイルの変更 1 件」

    def test_remove_allows_ignored_files(self):
        # self.repo/.git/info/exclude に "ignored/" を書く → p/ignored/x を作る
        # assert: remove(p) == 0、not p.exists()

    def test_remove_pushed_commits_are_ok(self):
        # commit_in(p, "a.txt") → git push -q -u origin HEAD
        # assert: remove(p) == 0、not p.exists()、not branch_exists(self.repo, "feat/pushed")

    def test_unsafe_reasons_lists_all(self):
        # 手元だけのコミット1件＋追跡していないファイル1件
        # assert: unsafe_reasons(p) == ["追跡していないファイル 1 件", "どのリモートにも無いコミット 1 件"]
```

`unsafe_reasons` を import に足す。

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `python3 -m unittest discover -s /home/aya/.dotfiles/.claude/worktrees/feat-claude-worktree-finish/scripts/claude-worktree -p 'test_worktree_hook.py'`
Expected: `ImportError: cannot import name 'unsafe_reasons'`

- [ ] **Step 3: `unsafe_reasons()` を実装し、`remove()` を直す**

`status --porcelain` で数える（`??` が追跡していないファイル、それ以外が追跡ファイルの変更）。`git worktree remove` の `--force` を外す。`--force` の前提を書いた既存コメントは消す。

- [ ] **Step 4: テストが通るのを確かめる**

Run: Global Constraints のテストコマンド
Expected: 全件 OK

- [ ] **Step 5: コミットして push する**

```bash
git add scripts/claude-worktree/worktree_hook.py scripts/claude-worktree/test_worktree_hook.py
git commit -m "fix: worktree のフックで、変更や未 push のコミットがある worktree は消さない"
git push
```

### Task 2: 本体を進める `sync_main.py`

**Files:**
- Create: `scripts/claude-worktree/sync_main.py`
- Test: `scripts/claude-worktree/test_sync_main.py`（`make_repo`・`git`・`commit_in` は `test_worktree_hook` から import する）

**Interfaces:**
- Produces: `sync(root: Path) -> "tuple[int, str]"`。終了コードと1行を返す
  - `(0, "最新")`
  - `(0, "進めた: <前の7桁> → <後の7桁>（N コミット）")`
  - `(3, "本体は <ブランチ> を使用中なので進めない")`
  - `(3, "本体の main に未 push のコミットが N 件あるので進めない")`
  - `(3, "git が早送りを断った: <git の stderr の最初の行>")`
  - `(1, "fetch に失敗: <git の stderr の最初の行>")`
- `main(argv=None) -> int`: `--repo`（既定 `Path.home() / ".dotfiles"`）を受け、1行を stdout に出して終了コードを返す
- 判定の順は spec のとおり（ブランチ → fetch → 未 push → `merge --ff-only`）。git は `worktree_hook._GIT_ENV` と同じく認証プロンプトを出さない環境で呼ぶ

- [ ] **Step 1: 失敗するテストを書く**

テスト用ヘルパー: `push_remote(tmp, name)`。`tmp/origin.git` を別の場所に clone し、`name` のファイルをコミットして push する。

```python
class SyncTest(unittest.TestCase):
    # setUp: self.repo = make_repo(self.tmp / "r", origin_url=None); git config pull.rebase true

    def test_up_to_date(self):
        self.assertEqual(sync(self.repo), (0, "最新"))

    def test_advances_keeping_unrelated_local_change(self):
        # 先に a.txt を repo でコミットして push → repo で a.txt を書き換え・u.txt を作る → push_remote("b.txt")
        code, line = sync(self.repo)
        self.assertEqual(code, 0)
        self.assertRegex(line, r"^進めた: [0-9a-f]{7} → [0-9a-f]{7}（1 コミット）$")
        # assert: HEAD == origin/main、a.txt の書き換えと u.txt が残っている

    def test_skips_when_not_on_main(self):
        # git checkout -q -b other
        self.assertEqual(sync(self.repo), (3, "本体は other を使用中なので進めない"))

    def test_skips_unpushed_local_main(self):
        # commit_in(self.repo, "local.txt") → push_remote("b.txt")
        self.assertEqual(sync(self.repo), (3, "本体の main に未 push のコミットが 1 件あるので進めない"))

    def test_reports_git_refusal_on_overlap(self):
        # a.txt をコミットして push → 別 clone で a.txt を変えて push → repo で a.txt を書き換え（未コミット）
        code, line = sync(self.repo)
        self.assertEqual(code, 3)
        self.assertTrue(line.startswith("git が早送りを断った: "))
        # assert: HEAD は変わらず、a.txt の書き換えが残っている

    def test_fetch_failure(self):
        # git remote set-url origin <存在しないパス>
        code, line = sync(self.repo)
        self.assertEqual(code, 1)
        self.assertTrue(line.startswith("fetch に失敗: "))

    def test_main_prints_line(self):
        # main(["--repo", str(self.repo)]) の stdout が "最新\n"、戻り値 0
```

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `python3 -m unittest discover -s /home/aya/.dotfiles/.claude/worktrees/feat-claude-worktree-finish/scripts/claude-worktree -p 'test_sync_main.py'`
Expected: `ModuleNotFoundError: No module named 'sync_main'`

- [ ] **Step 3: `sync_main.py` を実装する**（docstring に用途と spec のパス。実行権限を付ける）

- [ ] **Step 4: テストが通るのを確かめる**

Run: Global Constraints のテストコマンド
Expected: 全件 OK

- [ ] **Step 5: 本体に対して読み取りだけで確かめる**

worktree の中からは本体に向けた git が守りで止まる。そのため、ここでは本体の代わりにこの worktree 自身を `--repo` に渡す。ブランチが main でないので、何も変えずに返るはず。
Run: `python3 -I /home/aya/.dotfiles/.claude/worktrees/feat-claude-worktree-finish/scripts/claude-worktree/sync_main.py --repo /home/aya/.dotfiles/.claude/worktrees/feat-claude-worktree-finish; echo "rc=$?"`
Expected: `本体は feat/claude-worktree-finish を使用中なので進めない` と `rc=3`

- [ ] **Step 6: コミットして push する**

```bash
git add scripts/claude-worktree/sync_main.py scripts/claude-worktree/test_sync_main.py
git commit -m "feat: worktree の仕上げで本体を早送りで進める sync_main.py を足す"
git push
```

### Task 3: rules に仕上げの流れを書く

**Files:**
- Modify: `.claude-global/rules/worktree.md`（`## 仕上げ` の節を「作る」と「消す」の間に足す。「消す」の節に一文足す）
- Modify: `.claude-global/rules/command-handoff.md`（末尾の箇条に1行）

**Interfaces:**
- Consumes: Task 2 の `python3 -I ~/.dotfiles/scripts/claude-worktree/sync_main.py`（終了コード 0／3／1 と1行）、Task 1 のフックの振る舞い（変更があれば消さない）

- [ ] **Step 1: `worktree.md` に `## 仕上げ` を足す**

spec の「3. rules」の箇条をそのまま節にする（抜けるときは keep、本体で編集しない、片付けは `/worktree rm` で自分の分だけ番号指定、dotfiles の「マージして」の5段）。dotfiles の手順の 4 は `python3 -I ~/.dotfiles/scripts/claude-worktree/sync_main.py` と書き、「終了コード 3 は理由を伝えて止まる。1 は fetch の失敗」と添える。

- [ ] **Step 2: `worktree.md` の「消す」に一文足す**

「終了時の『消す』と ExitWorktree の remove は、フックが変更・未 push のコミットを見つけると消さずに残す。そのときは `/worktree rm` で中身を見て消す」

- [ ] **Step 3: `command-handoff.md` に1行足す**

spec の文（隔離されたセッションでは `!` も守りに掛かる → 自分で ExitWorktree して打つ。頼むなら `!` なしで別ペイン用に）。

- [ ] **Step 4: 確かめる**

Run: `grep -n 'ExitWorktree\|sync_main\|/worktree rm' /home/aya/.dotfiles/.claude/worktrees/feat-claude-worktree-finish/.claude-global/rules/worktree.md /home/aya/.dotfiles/.claude/worktrees/feat-claude-worktree-finish/.claude-global/rules/command-handoff.md`
Expected: `worktree.md` に ExitWorktree・sync_main・`/worktree rm` が、`command-handoff.md` に ExitWorktree が出る

- [ ] **Step 5: コミットして push する**

```bash
git add .claude-global/rules/worktree.md .claude-global/rules/command-handoff.md
git commit -m "docs: worktree のセッションの仕上げ（抜けて本体を進め、自分の worktree を片付ける）を rules に書く"
git push
```

### 仕上げ（実装後、この流れ自体で試す）

Task 3 の rules どおりに仕上げる。これが最初の実地確認になる。

- worktree の中で `git fetch` → `git merge origin/main` → テスト → `git push origin HEAD:main`
- ExitWorktree(keep) → `sync_main.py`
- agent-memory スキルで `user-preferences/dotfiles-merge-to-main.md` を更新する。手順は rules に移したと書き、古い「自分の worktree で `git checkout main`」を消す
- `/worktree rm` で feat/claude-worktree-finish だけを消す
