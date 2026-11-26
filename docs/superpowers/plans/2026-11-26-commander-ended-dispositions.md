# commander の終わった会話を漏れなく一覧へ反映する 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ended_sessions` の要素に `session_id`・ペインの座標・`cwd`・`refs` を足し、`alive` を外す。司令塔の除外をペインの座標にし、続いている会話と2回目の表示を除く。SKILL.md で、全件に「反映した／関係なし」を付けさせる。

**Architecture:** `status.py` の `ended_sessions()` は純粋関数のままにする。transcript の更新時刻とリポジトリの判定は呼び出し側から関数で渡す。`main()` がそれを組み立てる。

**Tech Stack:** Python 3（標準ライブラリのみ）、unittest

**Spec:** `docs/superpowers/specs/2026-11-26-commander-ended-dispositions-design.md`

## Global Constraints

- 要約の形式（`scripts/claude-summarize/`）は変えない
- 反映の判断（どの行に当てるか）は Claude（SKILL.md）。スクリプトは材料と除外だけ
- コードコメントは非自明な WHY だけを1行（`.claude-global/rules/code-comments.md`）
- テスト: `python3 -m unittest discover -s /home/aya/.dotfiles/.claude/worktrees/feat-commander-ended-dispositions/.claude-global/skills/commander/scripts/tests`

## Review Focus

- 司令塔と同じ tmux の別ペインで終わった会話 → 除かずに出す（Task 1 `test_keeps_other_pane_of_commander_tmux`）
- `wsl --shutdown` で落ちた会話（transcript が `end` のまま）→ 出す（Task 1 `test_transcript_at_end_is_shown`）
- transcript が見つからない（消えた・別マシン）→ 出す（Task 1 `test_transcript_missing_is_shown`）
- `#1254` のようなリポジトリ名の無い番号で、cwd のリポジトリが決まらない → 補わず、ほかの番号は残す（Task 1 `test_bare_number_unresolved_is_dropped`）
- tmux の外の会話（map.tsv に無い）→ `window`・`pane` は null で出す（Task 1 `test_falls_back_to_cwd_name` に assert を足す）

---

### Task 1: `ended_sessions()` の材料・除外・重複

**Files:**
- Modify: `.claude-global/skills/commander/scripts/status.py`（`_tmux_names` を座標つきに置き換え、`ended_sessions()` と `main()` を直し、`abbr_from_remote()` を足す）
- Test: `.claude-global/skills/commander/scripts/tests/test_status.py`（`EndedSessionsTest` とヘルパー `_summary`）

**Interfaces:**
- Produces:
  - `ended_sessions(sessions_dir: Path, pane_map: "str | None", last_check: datetime, now: datetime, self_pane: "tuple[str, str, str] | None", warnings: "list[str]", transcript_mtime: "Callable[[str], float | None]", repo_of: "Callable[[str], str | None]") -> "list[dict]"`
    - `self_pane` は (session_name, window_index, pane_index)。`transcript_mtime(session_id)` は transcript の更新時刻（無ければ None）。`repo_of(cwd)` は `epc` などの略称（決まらなければ None）
    - 要素: `{"session_id", "tmux", "window", "pane", "cwd", "refs", "end", "conclusion", "path"}`。`window`・`pane` は文字列か None、`refs` はソート済みの list
  - `abbr_from_remote(url: str) -> "str | None"`: remote の URL の末尾（`.git` を除く）が `sync_github.REPOS` の値なら、その略称を返す
  - `STILL_RUNNING = timedelta(minutes=5)`
- 振る舞い（spec から）:
  - 要約の更新時刻が `last_check` より後かつ `now` 以下のものだけ
  - `transcript_mtime(sid)` が `end + STILL_RUNNING` より後なら出さない
  - map.tsv の座標が `self_pane` と3つとも一致するものだけ除く（`self_pane` が None なら除かない）
  - `refs` は `## 意図` と `## 結論` から取る。`refs_in_text` の結果に加え、`(?<![\w#:/])#(\d+)` の裸の番号を `repo_of(cwd)` の略称で `<略称>#<番号>` にする（略称が None なら足さない）

テストの前提を変える:
- `_summary` の mtime の既定を `LC + timedelta(hours=1)` にし、意図の本文を渡す引数 `intent="確認する。"` を足す（今は既定の mtime が現在時刻なので、`now` の上限を入れると落ちる）
- テストは `NOW = LC + timedelta(hours=2)` を渡す。`transcript_mtime` の既定は `lambda sid: None`、`repo_of` の既定は `lambda cwd: None`（クラスにヘルパー `_ended(...)` を作り、既定を入れて呼ぶ）

- [ ] **Step 1: 失敗するテストを書く（既存の書き換えと追加）**

```python
    # 書き換え
    def test_picks_summary_written_after_last_check(self):
        # 期待する要素: {"session_id": SID, "tmux": "shifton-00002-check", "window": "1", "pane": "2", "cwd": PORTAL,
        #   "refs": [], "end": "2026-11-25T10:47:14.527000+09:00", "conclusion": "...", "path": str(p)}（alive は無い）
    def test_falls_back_to_cwd_name(self):
        # 加えて out[0]["window"] is None、out[0]["pane"] is None
    def test_excludes_commander_self(self):
        # map: commander 1 1 → self_pane=("commander","1","1") で out == []
    # test_sessions_unknown は削除（alive を外すため）

    # 追加
    def test_keeps_other_pane_of_commander_tmux(self):
        # map: dotfiles-ebapi 1 3 の会話、self_pane=("dotfiles-ebapi","1","2") → 1件出る
    def test_no_self_pane_excludes_nothing(self):
        # self_pane=None → 1件出る
    def test_skips_summary_written_after_now(self):
        # mtime = NOW + 1分 → []
    def test_still_running_is_skipped(self):
        # end=2026-11-25T02:00:00Z、transcript_mtime → end + 10分 → []
    def test_transcript_at_end_is_shown(self):
        # transcript_mtime → end + 1分 → 1件
    def test_transcript_missing_is_shown(self):
        # transcript_mtime → None → 1件
    def test_refs_with_bare_number(self):
        # intent="`/pickup` で #1254 の引き継ぎメモを読む"、conclusion="eae#142 のマージのみ残る"、repo_of → "epc"
        # out[0]["refs"] == ["eae#142", "epc#1254"]
    def test_bare_number_unresolved_is_dropped(self):
        # 同じ本文で repo_of → None → ["eae#142"]

class AbbrFromRemoteTest(unittest.TestCase):
    def test_known_repos(self):
        # "git@github.com:ebase-dev/ebase-portal-chat.git" → "epc"
        # "https://github.com/ebase-dev/eb-api-extended" → "eae"
    def test_unknown_repo(self):
        # "git@github-aya215:aya-215/dotfiles.git" → None
```

import に `abbr_from_remote` を足す。

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: Global Constraints のテストコマンド
Expected: `ImportError: cannot import name 'abbr_from_remote'`

- [ ] **Step 3: `status.py` を直す**

`_tmux_names` は `sid → (name, window, pane)` を返す形に変える。`main()` は次を渡す。
- `self_pane`: `TMUX_PANE` があれば `tmux display-message -p -t $TMUX_PANE '#{session_name}\t#{window_index}\t#{pane_index}'`（`tmux_sessions.run_cmd`）。無いか失敗なら None
- `transcript_mtime`: `~/.claude/projects/*/<sid>.jsonl` の最初の一致の `st_mtime`
- `repo_of`: `git -C <cwd> remote get-url origin` → `abbr_from_remote`。失敗なら None
- `now` は `main()` 冒頭の `now`

- [ ] **Step 4: テストが通るのを確かめる**

Run: Global Constraints のテストコマンド
Expected: 全件 OK

- [ ] **Step 5: 実データで確かめる**

Run: `mkdir -p /tmp/claude-1000/-home-aya--dotfiles/e3c4b352-e225-41e1-8c5a-7bf7bdaf8e8e/scratchpad/empty-commander && python3 -I /home/aya/.dotfiles/.claude/worktrees/feat-commander-ended-dispositions/.claude-global/skills/commander/scripts/status.py --commander-dir /tmp/claude-1000/-home-aya--dotfiles/e3c4b352-e225-41e1-8c5a-7bf7bdaf8e8e/scratchpad/empty-commander 2>/dev/null | jq '[.ended_sessions[] | {tmux, window, pane, refs, end}]'`
Expected: 今日終わった会話が並ぶ。`refs` に番号が入るものがある。このセッションのペイン（dotfiles-closed-summary 1 2）の会話は出ない。`alive` が無い

- [ ] **Step 6: コミットして push する**

```bash
git add .claude-global/skills/commander/scripts/status.py .claude-global/skills/commander/scripts/tests/test_status.py
git commit -m "feat: commander の終わった会話に作業の場所と番号を足し、司令塔自身・続いている会話・2回目を除く"
git push
```

### Task 2: SKILL.md で全件に「反映した／関係なし」を付けさせる

**Files:**
- Modify: `.claude-global/skills/commander/SKILL.md`（31行目の出力の説明、3. の手順 2 の「終わった会話」の行、表示の形のコードブロック、「- 変わった:」の行）

**Interfaces:**
- Consumes: Task 1 の要素のキー（`session_id`・`tmux`・`window`・`pane`・`cwd`・`refs`・`end`・`conclusion`・`path`）

- [ ] **Step 1: 出力の説明を直す**

`ended_sessions` の説明を Task 1 のキーに合わせる（`alive` を消す）。除くもの（このペインの会話・まだ続いている会話）を一言添える。

- [ ] **Step 2: 手順を置き換える**

手順 2 の「終わった会話: …1行に縮めて…判定はせず…」を、spec の「SKILL.md」の箇条（1件ごとに反映した／関係なし、手がかりは `refs`・`cwd`・中身、番号が無くても中身で当てる、手順4で書き込む、確認を求めない、「〇〇まだ」で戻す）に置き換える。手順4の「司令塔ファイルを更新する」に「終わった会話の反映」を足す。

- [ ] **Step 3: 表示の形を直す**

コードブロックの「変わった」を spec の例（cwd のフォルダ名と何を変えたかを1件1行、最後に「終わった会話 N件（反映 a・ほか b）」）に置き換える。「- 変わった:」の行も同じ決まりに直し、a＋b が N になることを書く。

- [ ] **Step 4: 確かめる**

Run: `grep -n 'alive\|反映 a\|関係なし\|ended_sessions' /home/aya/.dotfiles/.claude/worktrees/feat-commander-ended-dispositions/.claude-global/skills/commander/SKILL.md`
Expected: `alive` は出ない。`ended_sessions`・`関係なし`・`反映 a` が出る

- [ ] **Step 5: コミットして push する**

```bash
git add .claude-global/skills/commander/SKILL.md
git commit -m "docs: commander の状況確認で終わった会話を全件、一覧へ反映するか関係なしにする"
git push
```
