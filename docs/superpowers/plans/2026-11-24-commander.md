# 司令塔スキル（/commander）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** todo.md と待ち中の引き継ぎメモを丸ごと読み、優先度別の一覧・起動場所・プロンプトを出し、tmux で作業セッションを立てる司令塔スキル `/commander` を作る。

**Architecture:** 決定的な処理（祝日、参照の抽出と突き合わせ、材料集め、引き継ぐ欄の写しと掃除、GitHub の返ってきた判定）は Python スクリプト。並べ方・理由・文章・Rocket Chat/メール/GitBucket の確認は SKILL.md の手順に従って Claude がやる。司令塔ファイルは `~/memo/commander/<YYYY-MM-DD>.md`。その日最初は前日のファイルを材料に作り直し、日中は更新する。

**Tech Stack:** Python 3 標準ライブラリのみ、`unittest`、`python3 -I`。既存の `~/.dotfiles/scripts/todo-ai/todo_md.py`・`pr_ball.py`・`sync_github.py`、`~/.claude/skills/pickup/scripts/find_handoff.py` を使う。

**Spec:** `docs/superpowers/specs/2026-11-24-commander-design.md`

## Global Constraints

- スキルの置き場所: `~/.dotfiles/.claude-global/skills/commander/`（`~/.claude/skills/commander` として見える）
- スクリプトは `python3 -I` で動く。依存は標準ライブラリだけ。既存モジュールは `sys.path.insert(0, str(Path.home() / ".dotfiles/scripts/todo-ai"))` で読む
- テスト: `python3 -I -m unittest discover -s ~/.dotfiles/.claude-global/skills/commander/scripts/tests -v`
- スクリプトの出力は JSON を1つ標準出力へ。警告は stderr に `warn: ` で始めて出し、落ちない（終了コード 0）。引数の誤りだけ 2
- コメントは非自明な WHY を1行だけ（`rules/code-comments.md`）
- todo.md を書き換えない。外部アクション（PR コメント・マージ・送信）をしない
- 司令塔ファイルの置き場所 `~/memo/commander/<YYYY-MM-DD>.md`。前日のファイルは消さない
- 期限と祝日は今日から14日先まで
- コミットのプレフィックスは `feat:` / `docs:` / `test:`。コミットしたら push（`git@github-aya215:aya-215/dotfiles.git`）

## Review Focus

1. `tmux ls` が失敗（tmux サーバーが動いていない）→ 生きているセッションが「不明」扱いになり、作業中の tmux セッションの行を1行も消さない（Task 4 にテスト）
2. 前日のファイルが無い・`## 引き継ぐ欄` が無い・小見出しの外に行がある → 落ちず、読めなかった行は「メモ」へそのまま残す（Task 4 にテスト）
3. gh の認証失敗・タイムアウト（`sync.log` に TLS handshake timeout の実例あり）→ その参照だけ `returned: null` で理由付き、残りの参照は続けて判定（Task 5 にテスト）
4. todo.md が無い・`todo_md.ParseError` → 引き継ぎメモだけで材料を出し、`warnings` に理由を入れる（Task 3 にテスト）
5. 参照も作業場所も書いていない引き継ぎメモ → 一覧から落とさず `location: null` で出す（Task 3 にテスト）

---

## ファイル構成

| ファイル | 役割 |
|---|---|
| `.claude-global/skills/commander/SKILL.md` | 司令塔の手順（Claude が読む） |
| `.claude-global/skills/commander/scripts/jp_holidays.py` | 日本の祝日の計算 |
| `.claude-global/skills/commander/scripts/refs.py` | 文中の PR・issue・課題No を todo のキー形式に直す、作業場所を引く |
| `.claude-global/skills/commander/scripts/collect.py` | 材料（todo・引き継ぎメモ・祝日・ファイルの場所・tmux）を JSON で出す |
| `.claude-global/skills/commander/scripts/carry.py` | 前の司令塔ファイルの `## 引き継ぐ欄` を読み、掃除して書き出す |
| `.claude-global/skills/commander/scripts/check_waits.py` | GitHub の PR・issue で待ちが返ってきたかを判定する |
| `.claude-global/skills/commander/scripts/tests/test_*.py` | 各スクリプトのテスト |
| `.claude-global/skills/handoff/SKILL.md` | テンプレートに1行足す（Task 7） |

## 司令塔ファイルの書式（全タスク共通）

```markdown
# 司令塔 2026-11-24（火）

## 祝日と期限
<collect の holidays と、引き継ぐ欄の期限を日付順に並べた表。Claude が書く>

## 引き継ぐ欄
### 期限
- 2026-11-25 シフトオン 先方への修正版の期限
### 済んだこと
- 2026-11-24 RDP で本番 00010 に MSD 登録 [ref:title:AI参考情報 指示2項目の本番登録・配置]
### 作業中の tmux セッション
- pilot-p11: P.11 マージ→検証環境→実機確認
### メモ
- 11/24 #1321 は辻本さんが対応中なので後回し

## 一覧
### 最優先 / ### 高 / ### 中 / ### 低 / ### 返事待ち
<各項目: 理由・今の状態・起動する場所・打つプロンプト。Claude が書く>

## 同じ場所を使うときの注意
```

- 済んだことの行は `- <YYYY-MM-DD> <内容> [ref:<todo の Item.ref>]`。`Item.ref` はキーがあればキー（`epc#1296`）、無ければ `title:<タイトル>`
- tmux の行は `- <セッション名>: <内容>`

---

### Task 1: 祝日の計算

**Files:**
- Create: `.claude-global/skills/commander/scripts/jp_holidays.py`
- Test: `.claude-global/skills/commander/scripts/tests/test_jp_holidays.py`

**Interfaces:**
- Produces: `holidays_between(start: date, end: date) -> list[tuple[date, str]]`（両端を含む、日付順）

- [ ] **Step 1: 失敗するテストを書く**

```python
from datetime import date
from jp_holidays import holidays_between

def d(s): return date.fromisoformat(s)

class HolidaysTest(unittest.TestCase):
    def test_fixed(self):
        self.assertIn((d("2026-11-23"), "勤労感謝の日"), holidays_between(d("2026-11-01"), d("2026-11-30")))
        self.assertIn((d("2026-11-03"), "文化の日"), holidays_between(d("2026-11-01"), d("2026-11-30")))
    def test_happy_monday(self):
        self.assertIn((d("2027-01-11"), "成人の日"), holidays_between(d("2027-01-01"), d("2027-01-31")))
        self.assertIn((d("2026-09-21"), "敬老の日"), holidays_between(d("2026-09-01"), d("2026-09-30")))
    def test_equinox_and_kokumin(self):
        sep = holidays_between(d("2026-09-01"), d("2026-09-30"))
        self.assertIn((d("2026-09-23"), "秋分の日"), sep)
        self.assertIn((d("2026-09-22"), "国民の休日"), sep)
    def test_substitute(self):
        self.assertIn((d("2026-05-06"), "振替休日"), holidays_between(d("2026-05-01"), d("2026-05-31")))
    def test_range_inclusive_and_sorted(self):
        got = holidays_between(d("2026-11-23"), d("2026-11-23"))
        self.assertEqual(got, [(d("2026-11-23"), "勤労感謝の日")])
```

- [ ] **Step 2: 失敗を確かめる**

Run: `python3 -I -m unittest discover -s ~/.dotfiles/.claude-global/skills/commander/scripts/tests -p 'test_jp_holidays.py' -v`
Expected: FAIL（`ModuleNotFoundError: jp_holidays`）

- [ ] **Step 3: `holidays_between` を実装する**

現行の祝日法（2020年以降）。固定日（元日 1/1、建国記念の日 2/11、天皇誕生日 2/23、昭和の日 4/29、憲法記念日 5/3、みどりの日 5/4、こどもの日 5/5、山の日 8/11、文化の日 11/3、勤労感謝の日 11/23）、ハッピーマンデー（成人の日 1月第2月曜、海の日 7月第3月曜、敬老の日 9月第3月曜、スポーツの日 10月第2月曜）、春分・秋分は次の式（1980〜2099年で有効）:

```python
def _equinox(year, base):  # base: 春分 20.8431、秋分 23.2488
    return int(base + 0.242194 * (year - 1980) - (year - 1980) // 4)
```

振替休日（祝日が日曜なら、その後の最初の平日でない祝日の翌日）、国民の休日（前後が祝日の平日）。

- [ ] **Step 4: 通ることを確かめる**（Step 2 と同じコマンドで PASS）

- [ ] **Step 5: コミット**

```bash
git -C ~/.dotfiles add .claude-global/skills/commander/scripts/jp_holidays.py .claude-global/skills/commander/scripts/tests/test_jp_holidays.py
git -C ~/.dotfiles commit -m "feat: commander に日本の祝日の計算を足す"
```

---

### Task 2: 参照の抽出と作業場所

**Files:**
- Create: `.claude-global/skills/commander/scripts/refs.py`
- Test: `.claude-global/skills/commander/scripts/tests/test_refs.py`

**Interfaces:**
- Consumes: `sync_github.REPOS`（`{"epc": "ebase-portal-chat", "emm": ..., "eae": ..., "eas": ...}`）
- Produces:
  - `refs_in_text(text: str) -> set[str]` … todo のキー形式（`epc#1316`、`gb:ebase-web#102`、`ebpm:No00007456`）
  - `workdir_in_memo(text: str) -> str | None` … 引き継ぎメモの `- 作業場所: <path>（ブランチ …）` から path
  - `location_for(ref: str, gitbucket_roots: list[Path] = DEFAULT_GB_ROOTS) -> str | None`
  - `DEFAULT_GB_ROOTS = [Path.home() / "src/192.168.208.80/gitbucket"]`

- [ ] **Step 1: 失敗するテストを書く**

```python
class RefsInTextTest(unittest.TestCase):
    def test_github_pull_and_issue(self):
        t = "PR: https://github.com/ebase-dev/ebase-portal-chat/pull/1316 / issues/1296 は https://github.com/ebase-dev/ebase-portal-chat/issues/1296"
        self.assertEqual(refs_in_text(t), {"epc#1316", "epc#1296"})
    def test_unknown_github_repo_ignored(self):
        self.assertEqual(refs_in_text("https://github.com/other/x/pull/1"), set())
    def test_gitbucket(self):
        t = "http://192.168.208.80:8080/gitbucket/hankyu_kitchenyell/ebase-web/pull/102"
        self.assertEqual(refs_in_text(t), {"gb:ebase-web#102"})
    def test_ebpm_number(self):
        self.assertEqual(refs_in_text("課題No00007456 と No00000005"), {"ebpm:No00007456", "ebpm:No00000005"})
    def test_todo_key_as_is(self):
        self.assertEqual(refs_in_text("epc#1312・eae#141・emm#325"), {"epc#1312", "eae#141", "emm#325"})

class WorkdirTest(unittest.TestCase):
    def test_from_memo(self):
        self.assertEqual(workdir_in_memo("- 作業場所: /mnt/d/tomcat/webapps/hankyu（ブランチ feat/x）"), "/mnt/d/tomcat/webapps/hankyu")
    def test_missing(self):
        self.assertIsNone(workdir_in_memo("本文だけ"))

class LocationTest(unittest.TestCase):
    def test_github_abbr(self):
        self.assertEqual(location_for("epc#1"), str(Path.home() / "src/github.com/ebase-dev/ebase-portal-chat"))
    def test_gitbucket_glob(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "eBASE/ebase-claude-marketplace").mkdir(parents=True)
            self.assertEqual(location_for("gb:ebase-claude-marketplace#99", [Path(tmp)]),
                             str(Path(tmp) / "eBASE/ebase-claude-marketplace"))
    def test_no_location(self):
        self.assertIsNone(location_for("rc:abc"))
        self.assertIsNone(location_for("title:インターン資料修正"))
```

- [ ] **Step 2: 失敗を確かめる**（`-p 'test_refs.py'` で FAIL）

- [ ] **Step 3: 3つの関数を実装する**

GitHub は `github.com/ebase-dev/<repo>/(pull|issues)/<n>` を `REPOS` の逆引きで略称にする。GitBucket は `/gitbucket/<owner>/<repo>/(pull|issues)/<n>`。課題No は `No0*\d{5,}` を `ebpm:No` + 8桁ゼロ埋め。todo のキーがそのまま書かれていれば `todo_md.KEY_RE` で拾う。`location_for` の GitBucket は `root.glob(f"*/{repo}")` の最初の実在ディレクトリ。

- [ ] **Step 4: 通ることを確かめる**

- [ ] **Step 5: コミット** `feat: commander に参照の抽出と作業場所の引き当てを足す`

---

### Task 3: 材料集め（collect.py）

**Files:**
- Create: `.claude-global/skills/commander/scripts/collect.py`
- Test: `.claude-global/skills/commander/scripts/tests/test_collect.py`

**Interfaces:**
- Consumes: Task 1 `holidays_between`、Task 2 の3関数、`todo_md.parse`、`find_handoff.py`（引数なしで `{"results":[{"hits":[{path,summary,created,status}]}]}`）
- Produces: `collect(todo_path: Path, handoffs: list[dict], commander_dir: Path, today: date, tmux_sessions: list[str] | None) -> dict`。`handoffs` は find_handoff の hits。戻り値:

```python
{
  "today": "2026-11-24", "range_end": "2026-12-08",
  "holidays": [{"date": "2026-11-23", "name": "勤労感謝の日"}],          # today〜range_end
  "files": {"today": "<dir>/2026-11-24.md", "today_exists": bool, "previous": "<dir>/2026-11-21.md" | None},
  "todo": [{"section": "やる", "ref": "epc#1296", "title": ..., "url": ..., "next": ..., "location": str | None,
            "handoffs": ["<memo path>"]}],                              # 完了は入れない。確認待ちブロックは "confirm_lines" に生の行で
  "confirm_lines": ["..."],
  "handoffs": [{"path": ..., "summary": ..., "since": "2026-11-20T18:22:00+09:00", "refs": ["epc#1308"],
                "location": str | None, "todo_refs": ["epc#1308"]}],
  "tmux_sessions": ["pilot-p11"] | None,                               # None = tmux ls 失敗
  "warnings": ["..."]
}
```

- `since` はメモのファイル名 `handoff-YYYYMMDD-HHMM-*.md` から JST で。合わなければ `created` の 00:00 JST
- `location` はメモの作業場所を優先、無ければ refs の最初で `location_for` が返すもの
- `previous` は `commander_dir` 内で today より前の最新の `YYYY-MM-DD.md`
- CLI: `collect.py [--todo PATH] [--commander-dir PATH] [--today YYYY-MM-DD]`。既定は `~/memo/todo.md`、`~/memo/commander`、今日。find_handoff は subprocess、tmux は `tmux list-sessions -F '#S'`（失敗なら None）

- [ ] **Step 1: 失敗するテストを書く**（一時ディレクトリに todo.md・メモ・司令塔ファイルを作る）

```python
def test_matches_todo_and_handoff_by_ref(self):
    # todo に "[epc#1296](url)"、メモ本文に issues/1296 と pull/1316 と "作業場所: /x"
    out = collect(todo, [hit], cdir, date(2026, 11, 24), ["pilot-p11"])
    row = next(r for r in out["todo"] if r["ref"] == "epc#1296")
    self.assertEqual(row["handoffs"], [str(memo)])
    self.assertEqual(out["handoffs"][0]["todo_refs"], ["epc#1296"])
    self.assertEqual(out["handoffs"][0]["location"], "/x")
    self.assertEqual(out["handoffs"][0]["since"], "2026-11-20T17:42:00+09:00")  # handoff-20261120-1742-x.md

def test_range_and_holidays(self):
    out = collect(todo, [], cdir, date(2026, 11, 20), None)
    self.assertEqual(out["range_end"], "2026-12-04")
    self.assertIn({"date": "2026-11-23", "name": "勤労感謝の日"}, out["holidays"])

def test_previous_file(self):
    # cdir に 2026-11-20.md と 2026-11-21.md と 2026-11-24.md
    out = collect(todo, [], cdir, date(2026, 11, 24), [])
    self.assertTrue(out["files"]["today_exists"])
    self.assertTrue(out["files"]["previous"].endswith("2026-11-21.md"))

def test_completed_items_excluded(self): ...  # "## 完了" の行が todo に出ない

def test_missing_todo_still_returns_handoffs(self):  # Review Focus 4
    out = collect(tmp / "none.md", [hit], cdir, date(2026, 11, 24), [])
    self.assertEqual(out["todo"], [])
    self.assertEqual(len(out["handoffs"]), 1)
    self.assertTrue(any("todo" in w for w in out["warnings"]))

def test_memo_without_refs_kept(self):  # Review Focus 5
    out = collect(todo, [bare_hit], cdir, date(2026, 11, 24), [])
    self.assertIsNone(out["handoffs"][0]["location"])
    self.assertEqual(out["handoffs"][0]["refs"], [])
```

- [ ] **Step 2: 失敗を確かめる**
- [ ] **Step 3: `collect` と `main` を実装する**
- [ ] **Step 4: 通ることを確かめる**。あわせて実データで `python3 -I .../collect.py | python3 -m json.tool | head -50` が JSON を出すこと
- [ ] **Step 5: コミット** `feat: commander の材料集めスクリプトを足す`

---

### Task 4: 引き継ぐ欄（carry.py）

**Files:**
- Create: `.claude-global/skills/commander/scripts/carry.py`
- Test: `.claude-global/skills/commander/scripts/tests/test_carry.py`

**Interfaces:**
- Consumes: 上の「司令塔ファイルの書式」
- Produces:
  - `@dataclass Carry: deadlines: list[str]; done: list[str]; tmux: list[str]; memo: list[str]`（各行は `- ` から始まる元の行のまま）
  - `extract(text: str) -> Carry`
  - `prune(c: Carry, live_sessions: list[str] | None, open_refs: set[str]) -> tuple[Carry, dict]`。dict は `{"removed_tmux": [...], "removed_done": [...], "done_still_in_todo": [...], "unparsed_done": [...]}`
  - `render(c: Carry) -> str`（`## 引き継ぐ欄` から4つの小見出しまで。空の小見出しも出す）
  - CLI: `carry.py --prev PATH [--todo PATH]` → `{"section": "<render の結果>", ...prune の dict}`。`--prev` が無い・読めないなら空の Carry

- [ ] **Step 1: 失敗するテストを書く**

```python
SAMPLE = """# 司令塔 2026-11-24（火）
## 引き継ぐ欄
### 期限
- 2026-11-25 修正版の期限
### 済んだこと
- 2026-11-24 RDP 作業 [ref:title:AI参考情報 指示2項目の本番登録・配置]
- 2026-11-24 マージ済み [ref:epc#1300]
### 作業中の tmux セッション
- pilot-p11: P.11
- hankyu-102: PR #102
### メモ
- 1は後回し
## 一覧
- ここは写さない
"""

def test_extract(self):
    c = extract(SAMPLE)
    self.assertEqual(c.tmux, ["- pilot-p11: P.11", "- hankyu-102: PR #102"])
    self.assertEqual(c.memo, ["- 1は後回し"])

def test_prune_tmux_and_done(self):
    c, info = prune(extract(SAMPLE), ["pilot-p11"], {"title:AI参考情報 指示2項目の本番登録・配置"})
    self.assertEqual(c.tmux, ["- pilot-p11: P.11"])
    self.assertEqual(info["removed_done"], ["- 2026-11-24 マージ済み [ref:epc#1300]"])   # todo から消えた
    self.assertEqual(info["done_still_in_todo"], ["- 2026-11-24 RDP 作業 [ref:title:AI参考情報 指示2項目の本番登録・配置]"])

def test_tmux_unknown_keeps_all(self):  # Review Focus 1
    c, info = prune(extract(SAMPLE), None, set())
    self.assertEqual(len(c.tmux), 2)
    self.assertEqual(info["removed_tmux"], [])

def test_no_section_or_stray_lines(self):  # Review Focus 2
    self.assertEqual(extract("# 古い形式\n本文だけ\n"), Carry([], [], [], []))
    c = extract("## 引き継ぐ欄\n- 見出しの外の行\n### メモ\n- a\n")
    self.assertEqual(c.memo, ["- 見出しの外の行", "- a"])

def test_done_without_ref_kept(self):
    c, info = prune(extract("## 引き継ぐ欄\n### 済んだこと\n- 2026-11-24 ref なし\n"), [], set())
    self.assertEqual(c.done, ["- 2026-11-24 ref なし"])
    self.assertEqual(info["unparsed_done"], ["- 2026-11-24 ref なし"])

def test_render_roundtrip(self):
    c = extract(SAMPLE)
    self.assertEqual(extract(render(c)), c)
```

- [ ] **Step 2: 失敗を確かめる**
- [ ] **Step 3: 実装する**。CLI の `open_refs` は todo.md の 確認待ち以外の未完了 Item の `ref` と、確認待ちブロックの行に出る `todo_md.KEY_RE` のキー。todo.md が読めなければ `done` を1行も消さない（`warn:`）
- [ ] **Step 4: 通ることを確かめる**
- [ ] **Step 5: コミット** `feat: commander の引き継ぐ欄の写しと掃除を足す`

---

### Task 5: 返ってきたかの判定（check_waits.py）

**Files:**
- Create: `.claude-global/skills/commander/scripts/check_waits.py`
- Test: `.claude-global/skills/commander/scripts/tests/test_check_waits.py`

**Interfaces:**
- Consumes: `pr_ball.gh_json`・`pr_ball._login`・`pr_ball._is_bot`・`pr_ball.get_me`・`pr_ball.FetchError`、`sync_github.REPOS`・`ORG`・`get_token`・`ensure_gh_path`、collect の `handoffs[].refs` と `since`
- Produces:
  - `returned(state: str, events: list[dict], me: set[str], since: datetime) -> dict` … `{"returned": bool, "reason": str, "events": [...]}`。events の要素は `{"user", "ts", "kind"}`
  - `fetch(repo: str, number: int, token: str) -> tuple[str, list[dict]]` … PR として取り、`FetchError` で 404 なら issue（state と issue コメント）として取る。bot（`_is_bot`）の発言は events に入れない
  - CLI: 標準入力に `[{"ref": "epc#1308", "since": "2026-11-20T18:22:00+09:00"}, ...]` → 標準出力に `[{"ref", "kind": "github"|"gitbucket"|"other", "returned": bool|null, "reason", "events"}]`

- [ ] **Step 1: 失敗するテストを書く**

```python
ME = {"eBASE-Mori", "森彪人", "mori.a"}
SINCE = datetime.fromisoformat("2026-11-20T18:22:00+09:00")

def test_merged(self):
    self.assertEqual(returned("merged", [], ME, SINCE)["returned"], True)
def test_partner_after_since(self):
    ev = [{"user": "ebase-sato", "ts": "2026-11-20T09:50:00Z", "kind": "comment"}]   # 18:50 JST
    r = returned("open", ev, ME, SINCE)
    self.assertTrue(r["returned"]); self.assertEqual(r["events"], ev)
def test_partner_before_since_or_me_only(self):
    ev = [{"user": "ebase-sato", "ts": "2026-11-20T09:00:00Z", "kind": "comment"},
          {"user": "eBASE-Mori", "ts": "2026-11-21T00:00:00Z", "kind": "comment"}]
    self.assertFalse(returned("open", ev, ME, SINCE)["returned"])
def test_gitbucket_and_other_not_fetched(self):  # main に stdin を渡して確かめる
    # gb:ebase-web#102 → kind "gitbucket", returned None, reason に "MCP"
    # ebpm:No00007456 → kind "other", returned None
def test_fetch_failure_isolated(self):  # Review Focus 3
    # fetch を mock: epc#1 は FetchError("TLS handshake timeout")、epc#2 は ("merged", [])
    # 出力: epc#1 は returned None で reason に "TLS"、epc#2 は returned True
def test_bot_comments_ignored(self):
    # gh_json を mock: issue コメントに user.type == "Bot" のものだけ → events が空
```

- [ ] **Step 2: 失敗を確かめる**
- [ ] **Step 3: 実装する**。token が取れなければ GitHub の参照はすべて `returned: null`（理由付き）
- [ ] **Step 4: 通ることを確かめる**。実データで `echo '[{"ref":"epc#1308","since":"2026-11-20T18:22:00+09:00"}]' | python3 -I .../check_waits.py` が佐藤さんの 11/20 18:50 のコメントで `returned: true` になること
- [ ] **Step 5: コミット** `feat: commander に GitHub の待ちが返ってきたかの判定を足す`

---

### Task 6: SKILL.md

**Files:**
- Create: `.claude-global/skills/commander/SKILL.md`

**Interfaces:**
- Consumes: Task 3〜5 の CLI、agent-memory `user-preferences/commander-launch-tmux-sessions.md`

- [ ] **Step 1: SKILL.md を書く**。frontmatter の `name: commander`、`description` は起動の言葉（「/commander」「司令塔」「残りを全部出して」「返ってきたもの有る？」「〇〇のセッションを起動して」「〇〇終わった」）と役割（todo と待ち中の引き継ぎメモを丸ごと読み、優先度別に出して tmux で起動する）。本文に入れる手順:
  1. **開いたとき**: `collect.py` → `today_exists` が false なら `carry.py --prev <previous>` で引き継ぐ欄を作り、ファイル書式どおりに今日のファイルを作り直す（一覧・祝日と期限・注意は Claude が書く。期限は todo の next・メモ本文から拾って引き継ぐ欄の「期限」に足す）。true なら今日のファイルを読んで更新。どちらも一覧を出す前に `check_waits.py` で GitHub の待ちを照合し、GitBucket の待ちは `mcp__gitbucket__gitbucket_get_pr` と `gitbucket_list_comments` で確かめる。`removed_*`・`done_still_in_todo`・`unparsed_done` はユーザーに1行ずつ伝える（`done_still_in_todo` は「todo 側も `/todo-edit` で閉じる？」）。メモの行で古そうなものは「消してええ？」とまとめて聞き、OK のものだけ消す。照合で待ちが済んでいる（マージ済み・クローズ済み）のに `status: blocked` のままの引き継ぎメモは、閉じてよいか聞く
  2. **一覧の出し方**: 最優先（期限当日に直接かかわる）／高（その前に済ませたい）／中（今週中・期限あり）／低（期限なし）／返事待ち。各項目に理由・今の状態・起動する場所・打つプロンプト。打つプロンプトまで付けるのは引き継ぎメモがある項目と場所が分かる項目だけ
  3. **「返ってきたもの有る？」**: 上の照合に加え、Rocket Chat（引き継ぎメモ・todo の部屋リンク、無ければ相手のユーザー名で `mcp__rocketchat__list_channels`）とメール（`mcp__thunderbird__search_messages` を差出人と `since` で絞る。GitHub の通知メールは外す）。取るのは `since` 以降の相手の発言だけ、要約して出す。履歴を丸ごと出さない。課題DB は見る場所だけ出す。MCP がつながらなければ「見られなかった」と出して続ける
  4. **「〇〇終わった／止まった」**: 今日のファイルを更新（終わったものは引き継ぐ欄の「済んだこと」に `[ref:…]` 付きで）、一覧を出し直す。引き継ぎメモの待ちが済んだなら `status: resolved` にしてよいか聞く
  5. **「〇〇のセッションを起動して」**: agent-memory の tmux 手順に従う（セッション名「場所-課題番号」、`claude '<プロンプト>'`、`"${s}:tmp"`、フォルダ信頼の確認はユーザーに任せる、動いているセッションは kill しない）。起動したら引き継ぐ欄の「作業中の tmux セッション」に足す
  6. **やらないこと**: todo.md を書き換える、`/todo-edit` を呼ぶ、外部アクション、頼まれていない起動、自分で作業する
  7. **最初の1回**: 前日のファイルが無く `~/memo/weekly-plan-*.md` があれば、その中の判断・tmux セッション・チェックリスト・期限の表を引き継ぐ欄へ手で移す

- [ ] **Step 2: 読み込まれることを確かめる**

Run: `ls ~/.claude/skills/commander/SKILL.md && head -4 ~/.claude/skills/commander/SKILL.md`
Expected: ファイルがあり `name: commander`

- [ ] **Step 3: コミット** `feat: 司令塔スキル commander を足す`

---

### Task 7: handoff テンプレートに連絡先を足す

**Files:**
- Modify: `.claude-global/skills/handoff/SKILL.md`（テンプレートの `## 待っているもの` の行）

- [ ] **Step 1: テンプレートの `<誰の、何の返事・作業か。どこに届くか（PR・課題DB・Rocket Chat・メール）>` の下に1行足す**

```markdown
   <Rocket Chat なら部屋のリンク（DM は相手のユーザー名も）、メールなら相手のアドレス>
```

- [ ] **Step 2: 確かめる** `grep -n "部屋のリンク" ~/.dotfiles/.claude-global/skills/handoff/SKILL.md` が1行出る
- [ ] **Step 3: コミット** `feat: handoff の待ち先に Rocket Chat の部屋とメールの相手を書く`

---

### Task 8: 最初の1回と通し確認

**Files:**
- Create: `~/memo/commander/<実行日>.md`（リポジトリ外。コミットしない）

- [ ] **Step 1: 全テストを通す**

Run: `python3 -I -m unittest discover -s ~/.dotfiles/.claude-global/skills/commander/scripts/tests -v`
Expected: すべて OK

- [ ] **Step 2: 新しい Claude セッションで `/commander` を打ち、最初の1回の手順で `~/memo/weekly-plan-2026-11-23.md` から引き継ぐ欄を移した今日のファイルができることを確かめる**。確かめる点: tmux セッション（`pilot-p11`・`hankyu-102` のうち生きているもの）、シフトオンのチェックリスト、期限の表が引き継ぐ欄にあること
- [ ] **Step 3: 同じセッションで「返ってきたもの有る？」と打ち、epc#1312（松本さん 11/24 Approve）が返ってきたものとして出ることを確かめる**
- [ ] **Step 4: push**

```bash
git -C ~/.dotfiles push
```
