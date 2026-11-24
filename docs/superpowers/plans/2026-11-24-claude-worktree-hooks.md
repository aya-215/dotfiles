# Claude Code の worktree フック 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `claude -w <名前>`・EnterWorktree・サブエージェントの worktree を、WorktreeCreate/WorktreeRemove フックでうちの決まり（置き場所・ブランチ名・`.env` コピー・ブランチ掃除）に合わせる。

**Architecture:** 1本の Python スクリプト `scripts/claude-worktree/worktree_hook.py` が `create`（フック/手動）と `remove`（フック）を持つ。ブランチと置き場所の決定は純粋な関数と git の問い合わせに分け、本物の一時 git リポジトリでテストする。設定（settings.json の hooks、git.nix の ignores）と文書（rules・worktree/handoff/commander の SKILL.md）を合わせて直す。

**Tech Stack:** Python 3 標準ライブラリ、`unittest`、git、`gh`（PR の head ブランチ名だけ）。

**Spec:** `docs/superpowers/specs/2026-11-24-claude-worktree-hooks-design.md`

## Global Constraints

- スクリプトの置き場所: `~/.dotfiles/scripts/claude-worktree/`。`python3 -I` で動き、依存は標準ライブラリだけ
- フックの stdout は最後の空でない行が worktree の絶対パスだけ。ほかの出力（git の出力・進み具合）は stderr
- 置き場所: 本体のルートが `/mnt/` で始まれば `~/worktrees/<本体のフォルダ名>-<スラッグ>`、それ以外は `<本体>/.claude/worktrees/<スラッグ>`。スラッグは名前の `/` を `-` にしたもの
- 既知の種類: `feat/`・`fix/`・`docs/`・`chore/`・`refactor/`・`test/`・`hotfix/`・`ci/`・`perf/`・`build/`・`style/`
- 個人リポジトリ: origin の URL に `github-aya215:` か `github.com/aya-215/` を含む
- 新しいブランチの起点: `origin/main` → `origin/master` → 本体の HEAD
- コピーするのは `.env.local`・`.env.keys`（`node_modules`・`.claude/worktrees` の下は除く）。node_modules は `package-lock.json` があるときだけ、深さ3まで `cp -al`
- ブランチの削除は `git branch -d` だけ（`-D` は使わない）
- テスト: `python3 -I -m unittest discover -s ~/.dotfiles/scripts/claude-worktree -v`
- コメントは非自明な WHY を1行だけ。コミットのプレフィックスは `feat:`・`docs:`・`chore:`。コミットしたら push

## Review Focus

1. `git fetch origin` が失敗する（オフライン、GitBucket の HTTP が不調）→ 手元の参照だけで続けて worktree は作る（Task 2 にテスト）
2. GitHub の `pr-<n>` で `gh` が使えない・認証に失敗する → `pull/<n>/head` をブランチ `pr-<n>` に取って続ける（Task 2 にテスト）
3. 置き場所にディレクトリはあるが git の worktree として登録されていない（前の残骸）→ 上書きせず、理由付きで失敗する（Task 2 にテスト）
4. 本体が `/mnt/` で worktree が `~/worktrees`（別のファイルシステム）にあり `cp -al` が失敗する → その node_modules を消して先へ進み、作成は成功する（Task 3 にテスト）
5. `remove` に来たパスがもう無い・ブランチが他でも checkout 中で `-d` できない → 残っていなければ終了コード 0、ブランチを消せなくても失敗にしない（Task 4 にテスト）

---

## ファイル構成

| ファイル | 役割 |
|---|---|
| `scripts/claude-worktree/worktree_hook.py` | 置き場所とブランチの決定、作成、コピー、削除、CLI |
| `scripts/claude-worktree/test_worktree_hook.py` | 一時リポジトリ（bare の origin 付き）でのテスト |
| `modules/git.nix` | `ignores` に `.claude/worktrees/` |
| `.claude-global/settings.json` | `hooks.WorktreeCreate`・`hooks.WorktreeRemove` |
| `.claude-global/rules/worktree.md` | worktree の作り方・消し方の決まり |
| `.claude-global/skills/worktree/SKILL.md` | add をスクリプト経由に、rm の置き場所の説明 |
| `.claude-global/skills/handoff/SKILL.md` | 終了時に worktree を残す1行 |
| `.claude-global/skills/commander/SKILL.md` | 新しい作業は `claude -w` で起動 |

テストの土台（Task 1 で作り、以降のタスクで使う）: `make_repo(tmp: Path, origin_url: str | None = "git@github.com:ebase-dev/x.git") -> Path` … `tmp/origin.git`（bare、`main` に1コミット）を作って clone し、clone 先のパスを返す。`origin_url` を渡すと clone 後に `remote set-url` で表示上の URL を差し替え、fetch 用には `remote.origin.pushurl` ではなく `url.<bare>.insteadOf` で本物の bare を向かせる（個人リポジトリの判定をテストするため）。

---

### Task 1: 置き場所と名前の判定

**Files:**
- Create: `scripts/claude-worktree/worktree_hook.py`
- Test: `scripts/claude-worktree/test_worktree_hook.py`

**Interfaces:**
- Produces:
  - `slug(name: str) -> str`
  - `placement(root: Path, name: str, home: Path) -> Path`
  - `is_personal(remote_url: str | None) -> bool`
  - `KNOWN_TYPES: tuple[str, ...]`
  - `new_branch_name(name: str, personal: bool) -> str` … 既知の種類で始まればそのまま、個人ならそのまま、それ以外は `feat/<name>`
  - テスト用 `make_repo`（上の説明）

- [ ] **Step 1: 失敗するテストを書く**

```python
def test_slug(self):
    self.assertEqual(slug("feat/1296-mensapo"), "feat-1296-mensapo")
def test_placement_inside(self):
    self.assertEqual(placement(Path("/home/aya/src/github.com/o/app"), "feat/x", Path("/home/aya")),
                     Path("/home/aya/src/github.com/o/app/.claude/worktrees/feat-x"))
def test_placement_mnt(self):
    self.assertEqual(placement(Path("/mnt/d/tomcat/webapps/hankyu"), "feat/x", Path("/home/aya")),
                     Path("/home/aya/worktrees/hankyu-feat-x"))
def test_is_personal(self):
    self.assertTrue(is_personal("git@github-aya215:aya-215/dotfiles.git"))
    self.assertTrue(is_personal("https://github.com/aya-215/x.git"))
    self.assertFalse(is_personal("git@github.com:ebase-dev/ebase-portal-chat.git"))
    self.assertFalse(is_personal(None))
def test_new_branch_name(self):
    self.assertEqual(new_branch_name("fix/12-a", personal=False), "fix/12-a")
    self.assertEqual(new_branch_name("bold-oak-a3f2", personal=False), "feat/bold-oak-a3f2")
    self.assertEqual(new_branch_name("bold-oak-a3f2", personal=True), "bold-oak-a3f2")
    self.assertEqual(new_branch_name("featx", personal=False), "feat/featx")  # 「feat」で始まるだけでは種類と見なさない
```

- [ ] **Step 2: 失敗を確かめる** — Run: テストコマンド。Expected: FAIL（`ModuleNotFoundError: worktree_hook`）
- [ ] **Step 3: 実装する**
- [ ] **Step 4: 通ることを確かめる**
- [ ] **Step 5: コミット** `feat: claude-worktree に置き場所とブランチ名の判定を足す`

---

### Task 2: ブランチの決定と作成（create）

**Files:**
- Modify: `scripts/claude-worktree/worktree_hook.py`
- Test: `scripts/claude-worktree/test_worktree_hook.py`

**Interfaces:**
- Consumes: Task 1 の関数
- Produces:
  - `class HookError(Exception)` … 利用者に見せる理由を持つ
  - `checked_out_at(root: Path, branch: str) -> str | None` … `git worktree list --porcelain` でそのブランチを checkout している場所
  - `create(name: str, cwd: Path, home: Path = Path.home(), gh_head: Callable[[Path, int], str | None] = gh_pr_head) -> Path`
  - `gh_pr_head(root: Path, number: int) -> str | None` … `gh pr view <n> --json headRefName -q .headRefName`（`cwd=root`）。失敗は None
- 決め方は設計書「ブランチの決め方」の順。`git fetch origin` は先に1回（失敗は stderr に出して続ける）。置き場所が既に登録済みの worktree なら作らずにそのパスを返す

- [ ] **Step 1: 失敗するテストを書く**（すべて `make_repo` の本物のリポジトリで）

```python
def test_new_feat_branch_from_origin_main(self):
    p = create("bold-oak-a3f2", self.repo, home=self.home, gh_head=lambda r, n: None)
    self.assertEqual(p, self.repo / ".claude/worktrees/bold-oak-a3f2")
    self.assertEqual(branch_of(p), "feat/bold-oak-a3f2")
    self.assertEqual(rev(p, "HEAD"), rev(self.repo, "origin/main"))
def test_known_type_kept(self):
    self.assertEqual(branch_of(create("fix/9-a", self.repo, home=self.home, gh_head=lambda r, n: None)), "fix/9-a")
def test_existing_remote_branch_tracked(self):
    # origin に feat/old を push しておく（手元には無い）
    p = create("feat/old", self.repo, home=self.home, gh_head=lambda r, n: None)
    self.assertEqual(branch_of(p), "feat/old")
    self.assertEqual(upstream_of(p), "origin/feat/old")
def test_github_pr_opens_head_branch(self):
    # origin に feat/pr-head を push しておく
    p = create("pr-77", self.repo, home=self.home, gh_head=lambda r, n: "feat/pr-head" if n == 77 else None)
    self.assertEqual(branch_of(p), "feat/pr-head")
def test_pr_fallback_to_pull_ref(self):  # Review Focus 2（GitBucket も同じ経路）
    # origin に refs/pull/5/head を作っておく
    p = create("pr-5", self.repo, home=self.home, gh_head=lambda r, n: None)
    self.assertEqual(branch_of(p), "pr-5")
def test_branch_checked_out_elsewhere_fails(self):
    # 本体で feat/busy を checkout しておく
    with self.assertRaises(HookError) as cm:
        create("feat/busy", self.repo, home=self.home, gh_head=lambda r, n: None)
    self.assertIn(str(self.repo), str(cm.exception))
def test_reenter_returns_same_path(self):
    a = create("feat/again", self.repo, home=self.home, gh_head=lambda r, n: None)
    self.assertEqual(create("feat/again", self.repo, home=self.home, gh_head=lambda r, n: None), a)
def test_leftover_dir_fails(self):  # Review Focus 3
    (self.repo / ".claude/worktrees/feat-left").mkdir(parents=True)
    with self.assertRaises(HookError):
        create("feat/left", self.repo, home=self.home, gh_head=lambda r, n: None)
def test_fetch_failure_continues(self):  # Review Focus 1
    # origin の URL を存在しないパスに変える（origin/main は手元に残っている）
    p = create("feat/offline", self.repo, home=self.home, gh_head=lambda r, n: None)
    self.assertTrue(p.is_dir())
def test_personal_repo_keeps_name(self):
    repo = make_repo(self.tmp / "p", origin_url="git@github-aya215:aya-215/dotfiles.git")
    self.assertEqual(branch_of(create("bold-oak", repo, home=self.home, gh_head=lambda r, n: None)), "bold-oak")
def test_no_origin_uses_head(self):
    # origin の無いリポジトリ
    p = create("feat/local", self.plain_repo, home=self.home, gh_head=lambda r, n: None)
    self.assertEqual(rev(p, "HEAD"), rev(self.plain_repo, "HEAD"))
```

- [ ] **Step 2: 失敗を確かめる**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: 通ることを確かめる**
- [ ] **Step 5: コミット** `feat: claude-worktree にブランチの決定と worktree の作成を足す`

---

### Task 3: `.env` のコピーと node_modules

**Files:**
- Modify: `scripts/claude-worktree/worktree_hook.py`
- Test: `scripts/claude-worktree/test_worktree_hook.py`

**Interfaces:**
- Produces:
  - `copy_env(root: Path, wt: Path) -> list[str]` … コピーした相対パス
  - `link_node_modules(root: Path, wt: Path, cp: Callable[[Path, Path], bool] = _cp_al) -> list[str]` … 複製できた相対パス。`cp` は失敗で False
  - `create` は worktree を作った後にこの2つを呼ぶ（既存の worktree に入り直すときは呼ばない）

- [ ] **Step 1: 失敗するテストを書く**

```python
def test_copy_env_same_relative_paths(self):
    # 本体に apps/ui/.env.local・.env.keys・node_modules/x/.env.local・.claude/worktrees/y/.env.local を置き、apps/ui を追跡しておく
    got = copy_env(self.repo, wt)
    self.assertEqual(sorted(got), [".env.keys", "apps/ui/.env.local"])
    self.assertTrue((wt / "apps/ui/.env.local").exists())
def test_link_node_modules_only_with_package_lock(self):
    # package-lock.json なし → []
def test_link_node_modules_hardlinks(self):
    # package-lock.json と node_modules/a/index.js（深さ1）・apps/ui/node_modules/b.js
    got = link_node_modules(self.repo, wt)
    self.assertEqual(sorted(got), ["apps/ui/node_modules", "node_modules"])
    self.assertEqual(os.stat(self.repo / "node_modules/a/index.js").st_ino, os.stat(wt / "node_modules/a/index.js").st_ino)
def test_link_failure_cleans_and_continues(self):  # Review Focus 4
    def cp_fail(src, dst):
        dst.mkdir(parents=True); (dst / "partial").write_text("x"); return False
    self.assertEqual(link_node_modules(self.repo, wt, cp=cp_fail), [])
    self.assertFalse((wt / "node_modules").exists())
```

- [ ] **Step 2: 失敗を確かめる**
- [ ] **Step 3: 実装する**（`_cp_al` は `cp -al src dst` の subprocess。失敗で False）
- [ ] **Step 4: 通ることを確かめる**
- [ ] **Step 5: コミット** `feat: claude-worktree で .env のコピーと node_modules のハードリンクをする`

---

### Task 4: 削除（remove）と CLI

**Files:**
- Modify: `scripts/claude-worktree/worktree_hook.py`
- Test: `scripts/claude-worktree/test_worktree_hook.py`

**Interfaces:**
- Produces:
  - `remove(worktree_path: Path) -> int` … 終了コード。設計書「消すとき」の手順
  - `main(argv: list[str] | None = None, stdin: TextIO = sys.stdin) -> int`
    - `create` … stdin の JSON（`name`・`cwd`）。成功で stdout にパスだけ、終了コード 0。`HookError` は stderr に理由、終了コード 1
    - `create --name N --cwd D` … stdin を読まない（`/worktree add` 用）
    - `remove` … stdin の JSON（`worktree_path`）

- [ ] **Step 1: 失敗するテストを書く**

```python
def test_remove_deletes_dir_and_merged_branch(self):
    p = create("feat/done", self.repo, home=self.home, gh_head=lambda r, n: None)
    self.assertEqual(remove(p), 0)
    self.assertFalse(p.exists())
    self.assertFalse(branch_exists(self.repo, "feat/done"))
def test_remove_keeps_branch_with_local_only_commit(self):
    p = create("feat/wip", self.repo, home=self.home, gh_head=lambda r, n: None)
    commit_in(p, "a.txt")
    self.assertEqual(remove(p), 0)
    self.assertTrue(branch_exists(self.repo, "feat/wip"))
def test_remove_with_uncommitted_changes(self):
    p = create("feat/dirty", self.repo, home=self.home, gh_head=lambda r, n: None)
    (p / "u.txt").write_text("x")
    self.assertEqual(remove(p), 0); self.assertFalse(p.exists())
def test_remove_missing_path_is_ok(self):  # Review Focus 5
    self.assertEqual(remove(self.tmp / "gone"), 0)
def test_main_create_prints_only_path(self):
    out = io.StringIO()
    with redirect_stdout(out):
        rc = main(["create"], stdin=io.StringIO(json.dumps({"name": "feat/cli", "cwd": str(self.repo)})))
    self.assertEqual(rc, 0)
    self.assertEqual(out.getvalue().strip().splitlines()[-1], str(self.repo / ".claude/worktrees/feat-cli"))
def test_main_create_error_exit_1(self):
    # feat/busy を本体で checkout しておく → rc 1、stdout は空
def test_main_remove_from_json(self): ...
```

- [ ] **Step 2: 失敗を確かめる**
- [ ] **Step 3: 実装する**（git の stdout が stdout に混ざらないよう、git は capture して stderr へ流す）
- [ ] **Step 4: 通ることを確かめる**
- [ ] **Step 5: コミット** `feat: claude-worktree に worktree の削除と CLI を足す`

---

### Task 5: 設定と文書

**Files:**
- Modify: `modules/git.nix`（`ignores` の `# Claude Code` の下に `".claude/worktrees/"`）
- Modify: `.claude-global/settings.json`（`hooks` に2つ）
- Create: `.claude-global/rules/worktree.md`
- Modify: `.claude-global/skills/worktree/SKILL.md`・`.claude-global/skills/handoff/SKILL.md`・`.claude-global/skills/commander/SKILL.md`

- [ ] **Step 1: settings.json に足す**（`update-config` スキルの流儀。既存の hooks を壊さない）

```json
"WorktreeCreate": [{"hooks": [{"type": "command", "command": "python3 -I ~/.dotfiles/scripts/claude-worktree/worktree_hook.py create"}]}],
"WorktreeRemove": [{"hooks": [{"type": "command", "command": "python3 -I ~/.dotfiles/scripts/claude-worktree/worktree_hook.py remove"}]}]
```

- [ ] **Step 2: 確かめる** `python3 -c "import json;d=json.load(open('.claude-global/settings.json'));print(sorted(d['hooks']))"` に `WorktreeCreate` と `WorktreeRemove` が出る
- [ ] **Step 3: rules/worktree.md を書く**: worktree は `claude -w <ブランチ名>`（作業途中なら EnterWorktree）で作る／置き場所とブランチはフックが決める（中身は1行で設計書へのリンク）／消すのは Claude Code の終了処理（引き継ぎのときは「残す」）か `/worktree rm`。素の `rm -rf`・手での `git worktree remove --force` はしない／日本語のブランチ名が決まりのリポジトリ（hankyu・pilot の GitBucket）は英数字で作り、push 前に `git branch -m` で直す
- [ ] **Step 4: worktree/SKILL.md**: add の作成手順（略称・`../<略称>-<ブランチ>`・`git worktree add`・依存と `.env` のコピー）を `python3 -I ~/.dotfiles/scripts/claude-worktree/worktree_hook.py create --name <ブランチ名> --cwd <本体>` に置き換える（依存のインストールは今の手順を残す）。rm は「`<本体>/.claude/worktrees/*` と `~/worktrees/*` も対象」と明記。frontmatter の `allowed-tools` に `Bash(python3 -I ~/.dotfiles/scripts/claude-worktree/worktree_hook.py:*)` を足す
- [ ] **Step 5: handoff/SKILL.md** の手順の最後に「`claude -w` で作った worktree で作業していたら、終了時に残すか聞かれるので残す（返事のあとの修正をそこでやるため）」
- [ ] **Step 6: commander/SKILL.md** の「5. 起動」に: 新しい作業は `claude -w <ブランチ名> '<プロンプト>'` を本体で起動する（ブランチ名はリポジトリの決まりで。PR の続きは `-w "#<番号>"`）。既にある worktree の続き（引き継ぎメモの作業場所）はその場所で `claude '<プロンプト>'`
- [ ] **Step 7: コミット** `feat: worktree フックを設定し、作り方と消し方の決まりを書く`

---

### Task 6: 実機確認と後片付け

**Files:** なし（リポジトリ外の試験用ディレクトリだけ）

- [ ] **Step 1: 全テスト**（Global Constraints のコマンド）が OK
- [ ] **Step 2: main にマージして push し、`home-manager switch --flake ~/.dotfiles` を流す**。`git config --global --get core.excludesFile` の先に `.claude/worktrees/` があること
- [ ] **Step 3: 試験用リポジトリ（スクラッチの `wthook/repo`）で `claude -w feat/real-check -p "pwd を1行で" --max-turns 1`**。Expected: `<repo>/.claude/worktrees/feat-real-check`、ブランチ `feat/real-check`、`git -C <repo> status --short` に `.claude/` が出ない
- [ ] **Step 4: `/mnt/d/temp_wsl/wthook-test-repo` で同じく**。Expected: `~/worktrees/wthook-test-repo-feat-real-check`
- [ ] **Step 5: 両方の worktree を `echo '{"worktree_path":"<p>"}' | python3 -I .../worktree_hook.py remove` で消す**。Expected: ディレクトリとブランチが消える
- [ ] **Step 6: `python3 -I ~/.claude/skills/worktree/scripts/worktree_scan.py --no-fetch --no-size` で、Step 3・4 の時点の worktree が拾われていたことを確かめる**（Step 5 の前に流す）
- [ ] **Step 7: 試験用のものを消す**: スクラッチの `ghqtest2`・`wthook`、`/mnt/d/temp_wsl/wthook-test-repo`、`~/worktrees` に残ったもの。この作業の feat ブランチの worktree は `/worktree rm`（または `git worktree remove`）で
