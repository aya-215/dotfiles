# 司令塔「現在の状況をまとめて」 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 「現在の状況をまとめて」の一言で、gh・tmux・引き継ぎメモ・到達性・git を `status.py` が1回で集め、Claude が MCP の分（GitBucket・Rocket Chat・メール）を足して司令塔ファイルを更新し、C+ の形で表示する。

**Architecture:** tmux と git の読み取りは `sessions.py`、差分の基準時刻・メモの変化・到達性・GitHub の事実と全体の束ねは `status.py`。どちらも外部呼び出しを関数注入にしてテストで差し替える。既存の `collect.py`（todo・メモ）、`carry.py`（tmux 行の解析）、`pr_ball.fetch_pr`（PR とレビュー状態）を使い回す。

**Tech Stack:** Python 3 標準ライブラリのみ、`unittest`、`python3 -I`。

**Spec:** `docs/superpowers/specs/2026-11-24-commander-status-design.md`

## Global Constraints

- 置き場所: `~/.dotfiles/.claude-global/skills/commander/`（`~/.claude/skills/commander` はリンク）
- テスト: `python3 -I -m unittest discover -s ~/.dotfiles/.claude-global/skills/commander/scripts/tests -v`
- 標準ライブラリのみ。外部呼び出し（tmux・git・gh・socket）は引数で差し替えられる形にする
- 1件の取得失敗で残りを止めない。失敗は `warnings` に入れ、stderr に `warn:` で出す
- 最終確認時刻の行: 司令塔ファイルのタイトル直下に `最終確認: <ISO 8601, +09:00>`。無ければその日の 00:00 JST
- tmux の作業中判定: Claude のペインの最後の 8 行に `esc to interrupt` があれば `working`、無ければ `idle`
- 到達性のポート: 22・80・445・3389、各 2 秒
- 「返ってきたもの有る？」の手順と起動ワードは消す

## Review Focus

- Claude のペインが無いセッション（シェルだけ・別プログラム）→ `state: "no_claude"` で出し、落ちない（Task 1 でテスト）
- 自分（司令塔）のペイン → `self: true` で出し、作業一覧には数えない（Task 1 でテスト）
- `done HH:MM` が日付をまたぐ（今 00:10、done 23:50）→ 待ち時間は 20 分（Task 1 でテスト）
- 作業場所が git でない／消えた → `git: null`（Task 1 でテスト）
- 最終確認の行が壊れている（日時として読めない）→ 00:00 にして warning（Task 2 でテスト）

---

### Task 1: `sessions.py`（tmux の各セッションの状態と作業場所の git）

**Files:**
- Create: `scripts/sessions.py`
- Test: `scripts/tests/test_sessions.py`

**Interfaces:**
- Produces:
  - `pick_claude_pane(panes: str) -> dict | None` — 入力は `tmux list-panes -s -t <s> -F '#{pane_id}\t#{pane_current_command}\t#{pane_current_path}'` の出力。`{"pane": "%12", "cwd": "/path"}` か None
  - `pane_state(capture: str, now: datetime) -> dict` — `{"state": "working"|"idle", "idle_since": "HH:MM"|None, "idle_minutes": int|None, "tail": list[str]}`
  - `git_state(porcelain: str | None) -> dict | None` — 入力は `git status --porcelain=v1 --branch` の出力。`{"branch": str, "dirty": int, "ahead": int}`
  - `list_sessions(run, self_pane: str | None, now: datetime) -> list[dict] | None` — `run(argv: list[str]) -> str | None`（失敗は None）。各要素 `{"name", "pane", "cwd", "self": bool, "state": "working"|"idle"|"no_claude", "idle_since", "idle_minutes", "tail", "git"}`。tmux 一覧が取れなければ None

- [ ] **Step 1: 失敗するテストを書く**

```python
NOW = datetime.fromisoformat("2026-11-24T16:00:00+09:00")

def test_pick_claude_pane_skips_sidebar(self):
    panes = "%1\ttmux-agent-sidebar\t/home/aya\n%2\tclaude\t/home/aya/src/x\n"
    self.assertEqual(pick_claude_pane(panes), {"pane": "%2", "cwd": "/home/aya/src/x"})

def test_pick_claude_pane_none(self):
    self.assertIsNone(pick_claude_pane("%1\tzsh\t/home/aya\n"))

def test_pane_state_working(self):
    cap = "● 読んでいます\n* 力こそ正義… (1m 0s)\n────\n❯ \n────\n  ⏵⏵ auto mode on · esc to interrupt\n"
    self.assertEqual(pane_state(cap, NOW)["state"], "working")

def test_pane_state_idle_minutes_and_tail(self):
    cap = "コメントの投稿とマージは私がやりますか。\n✻ Cogitated for 8s · done 11:56\n────\n❯ \n────\n  ⚠ cache-keeper: x\n  󰉋 hankyu | feat\n  5h 3% (16:40)\n  ⏵⏵ auto mode on (shift+tab to cycle)\n"
    st = pane_state(cap, NOW)
    self.assertEqual((st["state"], st["idle_since"], st["idle_minutes"]), ("idle", "11:56", 244))
    self.assertEqual(st["tail"][-1], "✻ Cogitated for 8s · done 11:56")
    self.assertNotIn("❯", "".join(st["tail"]))

def test_pane_state_idle_across_midnight(self):
    st = pane_state("✻ done 23:50\n", datetime.fromisoformat("2026-11-25T00:10:00+09:00"))
    self.assertEqual(st["idle_minutes"], 20)

def test_git_state(self):
    self.assertEqual(git_state("## feat/x...origin/feat/x [ahead 2]\n M a.py\n?? b.py\n"),
                     {"branch": "feat/x", "dirty": 2, "ahead": 2})
    self.assertIsNone(git_state(None))

def test_list_sessions(self):
    out = {("tmux", "list-sessions"): "me\nwork\nshell\n",
           ("list-panes", "me"): "%0\tclaude\t/home/aya/memo\n",
           ("list-panes", "work"): "%1\ttmux-agent-sidebar\t/\n%2\tclaude\t/w\n",
           ("list-panes", "shell"): "%3\tzsh\t/\n",
           ("capture-pane", "%2"): "✻ done 15:30\n",
           ("git", "/w"): "## main\n"}
    def run(argv):
        for k, v in out.items():
            if all(x in argv for x in k):
                return v
        return None
    got = {s["name"]: s for s in list_sessions(run, "%0", NOW)}
    self.assertTrue(got["me"]["self"])
    self.assertEqual(got["work"]["state"], "idle")
    self.assertEqual(got["work"]["git"], {"branch": "main", "dirty": 0, "ahead": 0})
    self.assertEqual(got["shell"]["state"], "no_claude")
```

- [ ] **Step 2: 失敗を確かめる**

Run: `python3 -I -m unittest discover -s ~/.dotfiles/.claude-global/skills/commander/scripts/tests -p 'test_sessions.py' -v`
Expected: FAIL（`ModuleNotFoundError: sessions`）

- [ ] **Step 3: 実装する**

- `tail`: 空行・`─` で始まる行・`❯` で始まる行・`auto mode`・`cache`・`󰉋`・`5h `・`│┃` だけの行を除いた最後の 6 行（前後の空白は strip）
- `idle_since`: 最後に出てくる `done (\d{1,2}):(\d{2})`。`now` より後なら前日とみなす
- `list_sessions` の外部呼び出し: `["tmux","list-sessions","-F","#S"]`、`["tmux","list-panes","-s","-t",name,"-F",...]`、`["tmux","capture-pane","-p","-t",pane,"-S","-40"]`、`["git","-C",cwd,"status","--porcelain=v1","--branch"]`
- 自分のペインは capture せず `self: true`・`state: "idle"`
- `main()`: `list_sessions(subprocess 版 run, os.environ.get("TMUX_PANE"), 今)` を JSON で出す（単体でも使えるように）

- [ ] **Step 4: 通ることを確かめる**

Run: Step 2 と同じ
Expected: OK

- [ ] **Step 5: コミット**

```bash
git -C ~/.dotfiles add .claude-global/skills/commander/scripts/sessions.py .claude-global/skills/commander/scripts/tests/test_sessions.py
git -C ~/.dotfiles commit -m "feat: commander に tmux セッションの状態と作業場所の git を読む sessions.py を足す"
```

---

### Task 2: `status.py` の部品（最終確認時刻・メモの変化・到達性・閉じたセッション）

**Files:**
- Create: `scripts/status.py`
- Test: `scripts/tests/test_status.py`

**Interfaces:**
- Consumes: `carry.extract(text) -> Carry`、`carry.prune(c, live, None) -> (Carry, info)`（`info["removed_tmux"]`）
- Produces:
  - `read_last_check(text: str | None, today: date, warnings: list[str]) -> datetime`
  - `changed_handoffs(memo_dir: Path, since: datetime) -> list[dict]` — `handoff-*.md` のうち mtime > since。`{"path", "status", "summary", "last_heading"}`（`last_heading` は最後の `## ` 見出しの文字列）
  - `wait_ips(memo_text: str) -> list[str]` — `## 待っているもの` の節にある IPv4（重複なし・出てきた順）
  - `probe(ip: str, connect) -> list[int]` — `connect(ip, port, timeout) -> bool`。開いていたポートの一覧（22・80・445・3389 の順に試す）
  - `closed_sessions(commander_text: str | None, live: list[str] | None) -> list[str]` — 引き継ぐ欄の tmux 行のうち、もう無いもの（行のまま）。live が None なら []

- [ ] **Step 1: 失敗するテストを書く**

```python
TODAY = date(2026, 11, 24)

def test_read_last_check(self):
    w = []
    self.assertEqual(read_last_check("# 司令塔\n最終確認: 2026-11-24T15:40:00+09:00\n", TODAY, w),
                     datetime.fromisoformat("2026-11-24T15:40:00+09:00"))
    self.assertEqual(read_last_check(None, TODAY, w), datetime.fromisoformat("2026-11-24T00:00:00+09:00"))
    self.assertEqual(w, [])

def test_read_last_check_broken(self):
    w = []
    got = read_last_check("最終確認: きのう\n", TODAY, w)
    self.assertEqual(got, datetime.fromisoformat("2026-11-24T00:00:00+09:00"))
    self.assertEqual(len(w), 1)

def test_changed_handoffs(self):  # tmpdir に2ファイル、os.utime で片方だけ since より新しくする
    ...
    self.assertEqual([h["status"] for h in got], ["resolved"])
    self.assertEqual(got[0]["last_heading"], "2026-11-24 本番 eBASE 側の作業（完了）")

def test_wait_ips(self):
    t = "## 待っているもの\n- 192.168.160.92 の起動。GitBucket 192.168.208.80 には届く\n## 今の状態\n- 10.0.0.1\n"
    self.assertEqual(wait_ips(t), ["192.168.160.92", "192.168.208.80"])

def test_probe(self):
    self.assertEqual(probe("1.2.3.4", lambda ip, port, t: port in (80, 3389)), [80, 3389])

def test_closed_sessions(self):
    t = "## 引き継ぐ欄\n### 作業中の tmux セッション\n- epc-1316: マージ\n- epc-1308: 確認\n## 一覧\n"
    self.assertEqual(closed_sessions(t, ["epc-1308"]), ["- epc-1316: マージ"])
    self.assertEqual(closed_sessions(t, None), [])
```

- [ ] **Step 2: 失敗を確かめる**

Run: `python3 -I -m unittest discover -s ~/.dotfiles/.claude-global/skills/commander/scripts/tests -p 'test_status.py' -v`
Expected: FAIL（`ModuleNotFoundError: status`）

- [ ] **Step 3: 実装する**（frontmatter の `status:`・`summary:` は行頭一致の正規表現で読む。IPv4 は `\b(?:\d{1,3}\.){3}\d{1,3}\b`）

- [ ] **Step 4: 通ることを確かめる**（Step 2 と同じ。Expected: OK）

- [ ] **Step 5: コミット**

```bash
git -C ~/.dotfiles add .claude-global/skills/commander/scripts/status.py .claude-global/skills/commander/scripts/tests/test_status.py
git -C ~/.dotfiles commit -m "feat: commander の status.py に最終確認時刻・メモの変化・到達性・閉じたセッションの判定を足す"
```

---

### Task 3: `status.py` の GitHub の事実と全体の束ね

**Files:**
- Modify: `scripts/status.py`
- Test: `scripts/tests/test_status.py`

**Interfaces:**
- Consumes: Task 1 の `list_sessions`、Task 2 の関数、`collect.collect(...)`（`todo[].ref`・`handoffs[].refs/wait_refs/since/path`）、`collect._find_handoffs`、`pr_ball.fetch_pr(repo, number, token) -> {"state","author","reviewers","events"}`（events の review は `state` 付き）、`pr_ball.gh_json`、`check_waits.returned(state, events, me, since, closed_at)`
- Produces:
  - `github_facts(ref: str, fetch_pr, fetch_extra, me: set[str], last_check: datetime, since: datetime | None) -> dict` —
    `{"ref","state","reviews": {user: state}（各人の最新）,"last_commit": iso|None,"checks": {"pass":n,"fail":n,"pending":n}|None,"activity": [他人の events で ts > last_check],"returned": bool|None}`。`fetch_extra(repo, number) -> {"last_commit": iso|None, "checks": dict|None}`（PR のときだけ呼ぶ。issue は None）。`since` が None なら `returned` は None
  - `build(...) -> dict` — 出力 JSON: `{"now","last_check","sessions","closed_sessions","handoffs_changed","github": [...],"gitbucket_refs": [...],"reachability": [{"ip","open","memo"}],"warnings"}`
  - CLI: `python3 -I status.py [--commander-dir ~/memo/commander] [--todo ~/memo/todo.md]`

- [ ] **Step 1: 失敗するテストを書く**

```python
LAST = datetime.fromisoformat("2026-11-24T12:00:00+09:00")
ME = {"eBASE-Mori"}

def test_github_facts_pr(self):
    pr = {"state": "open", "author": "nakatani0324", "reviewers": [], "events": [
        {"user": "ebase-iyanaga", "ts": "2026-11-24T01:00:00Z", "kind": "review", "state": "COMMENTED"},
        {"user": "ebase-iyanaga", "ts": "2026-11-24T05:32:24Z", "kind": "review", "state": "APPROVED"},
        {"user": "eBASE-Mori", "ts": "2026-11-24T05:40:00Z", "kind": "comment", "state": None}]}
    got = github_facts("epc#1313", lambda r, n, t: pr,
                       lambda r, n: {"last_commit": "2026-11-24T05:26:00Z", "checks": {"pass": 5, "fail": 0, "pending": 0}},
                       ME, LAST, None)
    self.assertEqual(got["reviews"], {"ebase-iyanaga": "APPROVED"})
    self.assertEqual([e["ts"] for e in got["activity"]], ["2026-11-24T05:32:24Z"])
    self.assertIsNone(got["returned"])

def test_github_facts_returned_with_since(self):
    pr = {"state": "merged", "author": "x", "reviewers": [], "events": []}
    got = github_facts("epc#1312", lambda r, n, t: pr, lambda r, n: {"last_commit": None, "checks": None},
                       ME, LAST, datetime.fromisoformat("2026-11-20T13:42:00+09:00"))
    self.assertTrue(got["returned"])

def test_build_dedups_refs_and_splits_gitbucket(self):
    # collect の出力の形を手で作り、todo と handoffs に同じ epc#1316 と gb:ebase-web#102 を入れる
    ...
    self.assertEqual([g["ref"] for g in out["github"]].count("epc#1316"), 1)
    self.assertEqual(out["gitbucket_refs"], ["gb:ebase-web#102"])
```

- [ ] **Step 2: 失敗を確かめる**（Task 2 と同じコマンド。Expected: FAIL `github_facts` 未定義）

- [ ] **Step 3: 実装する**

- ref の解釈は `check_waits.check` と同じ（`abbr#num` で `abbr in sync_github.REPOS`）。`gb:` は `gitbucket_refs` へ、それ以外は捨てる
- PR でない（`fetch_pr` が 404）ときは issue として `check_waits.fetch` で state と events を取る
- `fetch_extra`: `pulls/{n}/commits`（最後の要素の `commit.committer.date`）と `commits/{head_sha}/check-runs`（`conclusion` が success/skipped/neutral → pass、failure/cancelled/timed_out → fail、None → pending）
- `returned` は、`since` があるとき `check_waits.returned` を使う。`since` は ref を `wait_refs` に持つ引き継ぎメモのもの
- 到達性は `status: blocked` の引き継ぎメモ（collect が返すもの）だけ
- `main()`: 司令塔ファイルは今日のファイル、無ければ `collect` の `files.previous`。gh のトークンが取れなければ github は空にして warning

- [ ] **Step 4: 全テストが通ることを確かめる**

Run: `python3 -I -m unittest discover -s ~/.dotfiles/.claude-global/skills/commander/scripts/tests -v`
Expected: OK（既存のテストも含めて）

- [ ] **Step 5: 実データで流す**

Run: `python3 -I ~/.claude/skills/commander/scripts/status.py | head -80`
Expected: `sessions` に今の tmux セッション、`github` に epc#1308 等、`warnings` が空か理由つき

- [ ] **Step 6: コミット**

```bash
git -C ~/.dotfiles add .claude-global/skills/commander/scripts/status.py .claude-global/skills/commander/scripts/tests/test_status.py
git -C ~/.dotfiles commit -m "feat: commander の status.py で GitHub の事実を取り、状況確認の材料を1回で出す"
```

---

### Task 4: SKILL.md の手順を「現在の状況をまとめて」に差し替える

**Files:**
- Modify: `SKILL.md`（description・スクリプトの節・司令塔ファイルの書式・手順 3）

**Interfaces:**
- Consumes: Task 3 の `status.py` の出力キー

- [ ] **Step 1: Rocket Chat で自分宛てのメンションを取る方法を確かめる**

`mcp__rocketchat__search_messages` 等を実際に呼び、前回確認以降の自分宛てメンション・DM を取れる手段を決める。取れなければ「待ちの相手の部屋だけ見る」と書く

- [ ] **Step 2: SKILL.md を直す**

- description: 「返ってきたもの有る？」を消し、「現在の状況をまとめて」「状況確認」を足す
- スクリプトの節に `status.py`（出力キーの一覧）を足す
- 書式: タイトル直下に `最終確認: <ISO 日時>` の行
- 手順 3 を「現在の状況をまとめて」に差し替える: ① `status.py` ② GitBucket（`gitbucket_refs`）・Rocket Chat・メールを MCP で（取るのは前回確認以降。秘密は書かない、の決まりは今のまま） ③ 司令塔ファイル更新（済んだこと・tmux・メモ・一覧・最終確認） ④ 設計書の「表示の形」の C+ で出す（段・右の列・空の段は省く・低はほかN件）
- 「開いたとき」の手順 4（照合）と 7（resolved を聞く）は `status.py` を使う形に寄せる

- [ ] **Step 3: 実際に「現在の状況をまとめて」を1回通す**

このセッションで手順どおりに流し、C+ で出ること・司令塔ファイルに最終確認の行が入ることを確かめる

- [ ] **Step 4: コミット**

```bash
git -C ~/.dotfiles add .claude-global/skills/commander/SKILL.md
git -C ~/.dotfiles commit -m "feat: commander の状況確認を「現在の状況をまとめて」に差し替える"
```
