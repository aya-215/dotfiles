# commander の状況確認に「終わった会話の結論」を出す 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `status.py` の出力に、`last_check` 以降に終わった会話の要約の `## 結論` を tmux 名つきで並べた `ended_sessions` を足し、SKILL.md の「変わった」段に出す。

**Architecture:** `status.py` に純粋関数 `ended_sessions()` を足す。要約フォルダと map.tsv の中身を引数で受け取る。`main()` は `build()` の後でこの関数を呼び、`out["ended_sessions"]` に入れる（`mail`・`rocketchat` と同じ後付け）。`build()` の引数は変えないので、既存テストはそのまま通る。

**Tech Stack:** Python 3（標準ライブラリのみ）、unittest

**Spec:** `docs/superpowers/specs/2026-11-25-commander-ended-sessions-design.md`

## Global Constraints

- 要約の形式（`scripts/claude-summarize/`）は変えない
- 判定はしない。結論は全文をそのまま渡し、1行に縮めるのは SKILL.md 側（Claude）に任せる
- 読めないファイルは `warnings` に足して飛ばす。ほかの材料の取得は止めない
- コードコメントは非自明な WHY だけを1行で書く（`~/.claude/rules/code-comments.md`）
- テストの実行: `python3 -m unittest discover -s /home/aya/.dotfiles/.claude/worktrees/feat-commander-closed-session-summary/.claude-global/skills/commander/scripts/tests`（pytest は入っていない）

## Review Focus

- 前日の最後の確認から翌朝に初めて確認する（`last_check` が前日）→ 前日フォルダの要約も拾う（Task 1 `test_scans_previous_day_folder`）
- 23:58 に終わった会話の要約が 0:02 に前日フォルダへ書かれる → 0時を挟んでも拾う（前日フォルダを見るので同じテストで押さえる）
- frontmatter の `end:` が無い・壊れている要約 → warning を出して飛ばし、残りは出す（`test_bad_end_is_warned_and_skipped`）
- map.tsv が無い・tmux 外で起動した会話 → `cwd` のフォルダ名で出す（`test_falls_back_to_cwd_name`）
- tmux が取れない（`sessions` が `None`）→ `alive` は `None`。司令塔自身は外せないので全部出す（`test_sessions_unknown`）

---

### Task 1: `ended_sessions()` と main への組み込み

**Files:**
- Modify: `.claude-global/skills/commander/scripts/status.py`（`closed_sessions` の近くに関数を足す。`main()` に引数2つと呼び出しを足す）
- Test: `.claude-global/skills/commander/scripts/tests/test_status.py`（import に `ended_sessions` を足し、`EndedSessionsTest` を足す）

**Interfaces:**
- Produces: `ended_sessions(sessions_dir: Path, pane_map: "str | None", last_check: datetime, live: "list[dict] | None", warnings: "list[str]") -> "list[dict]"`
  - 要素: `{"tmux": str, "project": str, "end": str（JST の isoformat）, "alive": bool | None, "conclusion": str, "path": str}`。`end` の昇順
  - `live` は `status.py` の `sessions`（`name`・`self` を持つ dict の list）
- 出力 JSON に `ended_sessions` キーが増える（Task 2 が SKILL.md に書く）

決まっている振る舞い（spec から）:
- 見るのは `sessions_dir/<YYYY-MM-DD>/*.md` のうち、フォルダ名の日付が `last_check`（JST）の日付の前日以降のもの。日付でないフォルダ名は無視する
- 拾うのは、ファイルの更新時刻が `last_check` より後で、かつ frontmatter の `end:`（`2026-11-25T01:47:14.527Z` の形の UTC）が `last_check - 1日` より後のもの
- tmux 名: frontmatter の `session_id` と6列目が一致する、`END` で始まらない map.tsv の行のうち最後の行の1列目。無ければ frontmatter の `cwd:` の末尾のフォルダ名。`cwd:` も無ければ `project:`
- `conclusion`: `## 結論` の次の行から次の `## ` 見出しの手前まで。空行を除いて `\n` でつなぐ。見出しが無ければ `""`
- `live` に `self: true` の要素があれば、その `name` と同じ tmux 名の会話は除く
- `alive`: `live` が `None` なら `None`。それ以外は tmux 名が `live` の `name` にあるか
- 読めないファイル（OSError・UnicodeDecodeError）と、`end:` が無いか読めないファイルは `warnings` に `終わった会話の要約を読めない: <ファイル名>: <理由>` の形で足して飛ばす

- [ ] **Step 1: 失敗するテストを書く**

テスト用の小道具（クラス内のヘルパーで可）:
- `_summary(dir, day, name, sid, end, conclusion="...", cwd="/home/aya/src/x/ebase-portal-chat", mtime=None)`。`dir/day/name` に frontmatter（`project`・`session_id`・`start`・`end`・`cwd`）と `## 意図`・`## 結論`・`## 編集/作成ファイル` を持つ要約を書く。`mtime` を渡したら `os.utime` で設定する
- `LC = datetime.fromisoformat("2026-11-25T10:00:00+09:00")`
- map.tsv の文字列は `"\t".join([...])` で組む

```python
class EndedSessionsTest(unittest.TestCase):
    def test_picks_summary_written_after_last_check(self):
        # end 10:47 JST（01:47Z）、mtime は今。map に shifton-00002-check の行と END 行
        out = ended_sessions(Path(d), pane_map, LC, [{"name": "shifton-00002-check", "self": False}], w)
        self.assertEqual(out, [{"tmux": "shifton-00002-check", "project": "ebase-portal-chat",
                                "end": "2026-11-25T10:47:14.527000+09:00", "alive": True,
                                "conclusion": "本番 00002 は0件。\n残りはリリースのみ。",
                                "path": str(Path(d) / "2026-11-25" / "ebase-portal-chat-1047-3a140506.md")}])
        self.assertEqual(w, [])

    def test_late_summary_is_picked_next_time(self):
        # end は LC より前（09:55 JST）でも、mtime が LC より後なら拾う
        self.assertEqual(len(out), 1)

    def test_old_mtime_is_skipped(self):
        # mtime を LC の1分前にする
        self.assertEqual(out, [])

    def test_backfilled_old_summary_is_skipped(self):
        # 2026-11-23 フォルダ、end 2026-11-23T03:00:00Z、mtime は今
        self.assertEqual(out, [])

    def test_scans_previous_day_folder(self):
        # LC = 2026-11-25T09:00+09:00。2026-11-24 フォルダに end 2026-11-24T14:58:00Z（23:58 JST）の要約、mtime は今
        self.assertEqual([x["end"] for x in out], ["2026-11-24T23:58:00+09:00"])

    def test_uses_last_live_row_for_tmux_name(self):
        # 同じ sid の行が "_dotfiles" → "hankyu-102" の順、最後に END 行
        self.assertEqual(out[0]["tmux"], "hankyu-102")

    def test_falls_back_to_cwd_name(self):
        # pane_map=None、cwd=/home/aya/src/github.com/ebase-dev/ebase-portal-chat
        self.assertEqual(out[0]["tmux"], "ebase-portal-chat")

    def test_excludes_commander_self(self):
        # live=[{"name": "commander", "self": True}]、map で sid → commander
        self.assertEqual(out, [])

    def test_sessions_unknown(self):
        # live=None
        self.assertIsNone(out[0]["alive"])

    def test_no_conclusion_heading(self):
        # 本文に ## 結論 が無い
        self.assertEqual(out[0]["conclusion"], "")

    def test_bad_end_is_warned_and_skipped(self):
        # 1本は end: 行なし、1本は正常 → 正常な1本だけ出て、warnings が1件
        self.assertEqual(len(out), 1)
        self.assertEqual(len(w), 1)
        self.assertIn("終わった会話の要約を読めない", w[0])

    def test_sorted_by_end(self):
        # end 11:00 と 10:30 の2本を、ファイル名順と逆になるように置く
        self.assertEqual([x["end"][11:16] for x in out], ["10:30", "11:00"])
```

- [ ] **Step 2: テストが落ちるのを確かめる**

Run: `python3 -m unittest discover -s /home/aya/.dotfiles/.claude/worktrees/feat-commander-closed-session-summary/.claude-global/skills/commander/scripts/tests -k EndedSessions`
Expected: `ImportError: cannot import name 'ended_sessions'`

- [ ] **Step 3: `status.py` に `ended_sessions()` を実装する**

frontmatter は既存の `_front(text, key)` で読む。`end:` のパースは既存の `_ts()`（`Z` を `+00:00` に置き換える）を使い、`.astimezone(JST)` する。

- [ ] **Step 4: テストが通るのを確かめる**

Run: `python3 -m unittest discover -s /home/aya/.dotfiles/.claude/worktrees/feat-commander-closed-session-summary/.claude-global/skills/commander/scripts/tests`
Expected: 全件 OK（既存98件＋新規）

- [ ] **Step 5: `main()` に組み込む**

- argparse に `--sessions-dir`（既定 `Path.home() / ".nb/claude/sessions"`）と `--pane-map`（既定 `Path.home() / ".local/share/claude-pane-session/map.tsv"`）を足す
- `out = build(...)` の直後に `out["ended_sessions"] = ended_sessions(a.sessions_dir, _read(str(a.pane_map)), datetime.fromisoformat(out["last_check"]), out["sessions"], out["warnings"])` を入れる。`warnings` を stderr に出すループより前に置く

- [ ] **Step 6: 実データで動くのを確かめる**

Run: `mkdir -p /tmp/claude-1000/-home-aya--dotfiles/e3c4b352-e225-41e1-8c5a-7bf7bdaf8e8e/scratchpad/empty-commander && python3 -I /home/aya/.dotfiles/.claude/worktrees/feat-commander-closed-session-summary/.claude-global/skills/commander/scripts/status.py --commander-dir /tmp/claude-1000/-home-aya--dotfiles/e3c4b352-e225-41e1-8c5a-7bf7bdaf8e8e/scratchpad/empty-commander 2>/dev/null | jq '.last_check, [.ended_sessions[] | {tmux, end, alive}]'`
（空の司令塔フォルダを渡すので `last_check` は今日の0時になる。本物の `~/memo/commander` には書き込まない）
Expected: `last_check` が `2026-11-25T00:00:00+09:00`。今日終わった会話（`shifton-00002-check` など）が tmux 名つきで並び、`alive` が true/false で入る

- [ ] **Step 7: コミットして push する**

```bash
git add .claude-global/skills/commander/scripts/status.py .claude-global/skills/commander/scripts/tests/test_status.py
git commit -m "feat: commander の status.py で前回の確認以降に終わった会話の結論を出す"
git push
```

### Task 2: SKILL.md に反映する

**Files:**
- Modify: `.claude-global/skills/commander/SKILL.md`（31行目の `status.py` の出力の説明、3. の手順と「表示の形」の節）

**Interfaces:**
- Consumes: Task 1 の出力キー `ended_sessions`（`tmux`・`project`・`end`・`alive`・`conclusion`・`path`）

- [ ] **Step 1: 出力の説明に足す**

31行目の `status.py` の出力の列挙で、`closed_sessions` の後に足す: `ended_sessions`（`last_check` 以降に終わった会話の要約（`~/.nb/claude/sessions/`）ごとに `tmux`・`project`・`end`・`alive`（その tmux がまだあるか）・`conclusion`（`## 結論` の全文）・`path`。司令塔自身の会話は除く）

- [ ] **Step 2: 手順と表示の形に足す**

- 3. の手順 2 に1行足す: 「終わった会話: `ended_sessions` の `conclusion` を1行に縮めて「変わった」段に出す。一覧・引き継ぐ欄と食い違っていても判定はせず、並べるだけにする（直すのはユーザーが「〇〇終わった」と言ったとき）」
- 表示の形のコードブロックで、「変わった」行の下に spec と同じ「終わった会話」の2行を足す:

```
変わった  epc#1316・epc#1313 マージ ・ RDP 作業完了 ・ epc-1316 は閉じた
  終わった会話
          shifton-00002-check  本番 00002 の該当項目は0件。残りはリリースと eae#142 のマージ
          pilot-p11            P.11 の課題DB への返信案を作った
```

- 段の説明（「- 段: 変わった（…）」の行）に「変わった段の下に、終わった会話を1件1行で（tmux 名・縮めた結論）」と足す

- [ ] **Step 3: 確かめる**

Run: `grep -n 'ended_sessions\|終わった会話' /home/aya/.dotfiles/.claude/worktrees/feat-commander-closed-session-summary/.claude-global/skills/commander/SKILL.md`
Expected: 出力の説明・手順・表示の形・段の説明の4か所に出る

- [ ] **Step 4: コミットして push する**

```bash
git add .claude-global/skills/commander/SKILL.md
git commit -m "docs: commander の状況確認の表示に終わった会話の結論を足す"
git push
```
