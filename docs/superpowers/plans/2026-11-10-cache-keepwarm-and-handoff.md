# キャッシュ温め続け mod と引き継ぎスキル Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 外部 mod cache-keeper を取り込んで時刻ルールと ping 回数上限を入れ、あわせて `/handoff` `/pickup` スキルを作る。

**Architecture:** B は chrisvaillancourt/claude-cache-keeper（commit `46570fd`、v0.5.0、MIT）を `.claude-global/mods/cache-keeper/` にコピーし、判断の純粋関数 `hooks/policy.ts` の `decide` だけを書き換える（`register.ts` は設定の読み取りと手動 ping の数え方の 2 か所のみ）。A は `.claude-global/skills/handoff/` と `.claude-global/skills/pickup/` の 2 スキルで、決まった処理（情報収集・検索）はスクリプト、文章は Claude が書く。保存先は agent-memory の `memories/work-in-progress/`。

**Tech Stack:** TypeScript（Claude Code mod / function hooks、`claude-code/testing`）、bash、Python 3（標準ライブラリのみ、`unittest`）

**Spec:** `docs/superpowers/specs/2026-11-10-cache-keepwarm-and-handoff-design.md`

## Global Constraints

- 取得元: `https://github.com/chrisvaillancourt/claude-cache-keeper` commit `46570fd`（clone 済み: `/tmp/claude-1000/-home-aya--dotfiles/99ca8a45-3f8e-44fb-b3d6-36a6811fd6db/scratchpad/ext/claude-cache-keeper/`。無ければ同 commit を clone し直す）
- 時刻ルール（基準は `lastTurnAt ?? lastRequestAt`、ローカル時刻 JST）: 月〜木 → 翌日 12:00 まで / 金 17:00 前 → その日 17:00 まで / 金 17:00 以降・土・日 → 温めない
- ping 回数上限: 1 回の放置につき 20 回（自動 ping の当たりだけ数える。手動 `/keepwarm now` は数えない）。`/keepwarm for|until` の期限内は時刻ルールも回数上限も見ない
- 元の挙動で残すもの: `minContextTokens` 60k、外れたら同バージョンの間は自動 ping を休む、5 分 TTL で止める、`claude -p` 除外、`/keepwarm` コマンド
- mod の検証: `claude plugin test <dir>` / `claude plugin validate <dir>` / `nix shell nixpkgs#typescript -c tsc -p <dir>`
- 引き継ぎの保存先: `~/.claude/skills/agent-memory/memories/work-in-progress/`、frontmatter は `summary` / `created` / `status`（待ち中 `blocked`、終わり `resolved`）/ `tags`（`handoff` を含む）
- `.claude-global/settings.json` にはユーザーの未コミット変更（`advisorModel`）がある。コミットは自分の変更だけを index に載せ、`git diff --cached` の `-` 行を必ず確認する（agent-memory `wsl-git/partial-staging-unidiff-zero-hunk-merge.md`）
- 実機確認の tmux 操作は pane id 宛てのみ（agent-memory `tmux/send-keys-into-throwaway-session-pitfall.md`）
- コメントは `rules/code-comments.md`（非自明な WHY だけ 1 行）、シェルは `rules/shell-conventions.md`
- コミットメッセージは `feat:` / `fix:` / `docs:` / `chore:`、コミット後に push

## Review Focus

- 数字の部分一致: `/pickup 12` が `#1210` や `pull/1210` に当たってはいけない（Task 4 のテストで固定）
- git 管理外・PR の無いブランチ・GitBucket の remote で `/handoff` の収集スクリプトが落ちない（Task 5 のテストで固定）
- 入力欄の下に cache-keeper の状態行（`cache warm until …`）と prompt-cache-control の行が 2 本並ぶ。さらに fork ping で延びた期限を prompt-cache-control は知らないので「切れた」と出る可能性がある（Task 3 の実機確認で記録し、ユーザーに報告する。直すかどうかはユーザーが決める）
- 曜日の境目は端末のタイムゾーンで決まる: `policy.ts` には UTC からの分差を渡し、テストは JST（`-540`）で固定する（Task 2）
- 時刻ルールで止まったセッションに戻ったとき、次の本物のターンで `pings` が 0 に戻り、再び温め始める（元の `register.ts` の挙動。Task 2 の register テストで固定）

---

### Task 1: cache-keeper を mods に取り込む（無改造）

**Files:**
- Create: `.claude-global/mods/cache-keeper/`（取得元から `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `hooks/*`, `types/index.d.ts`, `LICENSE`, `README.md` をコピー。`AGENTS.md` / `CLAUDE.md` / `.DS_Store` / `.git` はコピーしない）
- Create: `.claude-global/mods/cache-keeper/tsconfig.json`
- Modify: `.claude-global/mods/cache-keeper/.gitignore`（取得元は `tsconfig.json` を無視しているので外す）

**Interfaces:**
- Produces: 以降のタスクが触る `hooks/policy.ts` / `hooks/register.ts` / `types/index.d.ts` / テスト 2 本が、取得元と同じ内容でリポジトリにある状態

- [ ] **Step 1: コピーする**（上の一覧のとおり。`.gitignore` は `.claude-plugin/types/` の 1 行だけにする）
- [ ] **Step 2: `tsconfig.json` を作る**: `.claude-global/mods/session-autoname/tsconfig.json` と同じ内容で `"allowImportingTsExtensions": true` を足し、`include` は `[".claude-plugin/types", "hooks", "types"]`
- [ ] **Step 3: 取得元のテストが通ることを確かめる**

Run: `claude plugin test .claude-global/mods/cache-keeper && claude plugin validate .claude-global/mods/cache-keeper`
Expected: 全テスト pass、`✔ Validation passed`（型ファイルは test 実行時に書き出される。その後 `nix shell nixpkgs#typescript -c tsc -p .claude-global/mods/cache-keeper` が exit 0。テストファイルの型エラーで落ちる場合は `include` から外して理由を README に書く）

- [ ] **Step 4: Commit**

```bash
git add .claude-global/mods/cache-keeper
git commit -m "chore: cache-keeper mod を取得元のまま取り込む"
```

### Task 2: 時刻ルールと ping 回数上限

**Files:**
- Modify: `.claude-global/mods/cache-keeper/hooks/policy.ts`（`Facts`, `StopReason`, `decide`、新関数 `warmDeadline`）
- Modify: `.claude-global/mods/cache-keeper/types/index.d.ts`（`Config`: `maxIdleMs` を削り `maxPings: number` を足す）
- Modify: `.claude-global/mods/cache-keeper/hooks/register.ts`（`configFrom` と `decide` 呼び出し、`ping` 内の `pings` 加算）
- Modify: `.claude-global/mods/cache-keeper/.claude-plugin/plugin.json`（`userConfig.maxIdleHours` を削り `maxPings` を足す。default 20）
- Test: `.claude-global/mods/cache-keeper/hooks/policy.test.ts`, `.claude-global/mods/cache-keeper/hooks/register.test.ts`

**Interfaces:**
- Consumes: Task 1 の取り込み済みファイル
- Produces:
  - `export const warmDeadline = (base: number, tzOffsetMinutes: number): number | null` — 温めてよい最終時刻（epoch ms）。温めない日は `null`。`tzOffsetMinutes` は `Date#getTimezoneOffset()`（JST は `-540`）
  - `export type Facts = { contextTokens: number; tzOffsetMinutes: number }`
  - `export type StopReason = 'off' | 'expired' | 'short-ttl' | 'calendar' | 'ping-limit' | 'small-context'`（`idle-limit` は削除）
  - `Config.maxPings: number`

- [ ] **Step 1: `policy.test.ts` に失敗するテストを書く**（`config` の `maxIdleMs` を `maxPings: 20` に置き換え、`facts` に `tzOffsetMinutes: -540`。時刻は JST の具体日で作る: `const jst = (iso: string) => Date.parse(iso + '+09:00')`。2026-11-12 は木、11-13 は金、11-14 は土）

```ts
describe('warmDeadline', () => {
  test('Mon-Thu: until noon the next day', () => {
    expect(warmDeadline(jst('2026-11-12T23:59:00'), -540)).toBe(jst('2026-11-13T12:00:00'))
    expect(warmDeadline(jst('2026-11-10T09:00:00'), -540)).toBe(jst('2026-11-11T12:00:00'))
  })
  test('Friday before 17:00: until 17:00 that day', () => {
    expect(warmDeadline(jst('2026-11-13T16:59:00'), -540)).toBe(jst('2026-11-13T17:00:00'))
  })
  test('Friday from 17:00, Saturday and Sunday: not at all', () => {
    expect(warmDeadline(jst('2026-11-13T17:00:00'), -540)).toBeNull()
    expect(warmDeadline(jst('2026-11-14T10:00:00'), -540)).toBeNull()
    expect(warmDeadline(jst('2026-11-15T10:00:00'), -540)).toBeNull()
  })
})
```

`decide` のテスト（`session({ lastRequestAt, lastTurnAt })` と、ping 窓の中の `now` で）:
- 木 15:00 に最後の作業、`now` = 金 12:01 の ping 窓 → `{ action: 'stop', reason: 'calendar' }`
- 金 17:30 に最後の作業、その 56 分後 → `stop: calendar`
- 木 10:00 に最後の作業、`pings: 20`、期限内の ping 窓 → `stop: ping-limit`、`pings: 19` なら `{ action: 'ping' }`
- 金 17:30 に最後の作業でも `untilMs` が `now` より後 → `{ action: 'ping' }`（時刻ルールを見ない）
- `untilMs` 内なら `pings: 25` でも `{ action: 'ping' }`
- 取得元の `idle-limit` を期待するテストは削除し、上のテストで置き換える

- [ ] **Step 2: 失敗を確かめる**

Run: `claude plugin test .claude-global/mods/cache-keeper`
Expected: FAIL（`warmDeadline` が無い、`reason: 'calendar'` にならない）

- [ ] **Step 3: `policy.ts` を実装する**: `warmDeadline` は `base - tzOffsetMinutes * MIN` をローカルの壁時計として曜日（`getUTCDay`）と時分を読み、上の表の期限を同じ変換の逆で epoch に戻す。`decide` は取得元の `keepUntil` の行を、「`untilMs` の期限内でなければ、`warmDeadline(lastTurnAt ?? lastRequestAt, facts.tzOffsetMinutes)` が `null` か `now` を過ぎていたら `calendar`、`s.pings >= config.maxPings` なら `ping-limit`」に置き換える。判定順は取得元の `idle-limit` と同じ位置（期限・lead 判定の後、`small-context` の前）

- [ ] **Step 4: `register.ts` を直す**: `configFrom` の `maxIdleMs` 行を `maxPings: num(options.maxPings, 20)` に、`decide` 呼び出しの `facts` に `tzOffsetMinutes: new Date(now).getTimezoneOffset()` を足す。`ping()` の当たり時の `pings: cur.pings + 1` を `pings: isManual ? cur.pings : cur.pings + 1` にする。`plugin.json` の `userConfig` も合わせる（`maxPings`: number, default 20, 説明 1 文）

- [ ] **Step 5: `register.test.ts` を直す**: `idle-limit` を期待している 2 テスト（取得元の 227 行・418 行付近）を、偽の時計を時刻ルールの期限の後へ進めて `reason: 'calendar'` を期待する形にする。偽の時計の起点が端末のタイムゾーンで何曜日になるかに依存するので、起点を JST の木曜（例 `2026-11-12T10:00:00+09:00`）に置くか、テスト内で明示する。加えて「手動 `/keepwarm now` の当たりで `/keepwarm status` の ping 数が増えない」テストを 1 本足す

- [ ] **Step 6: 全部通ることを確かめる**

Run: `claude plugin test .claude-global/mods/cache-keeper && claude plugin validate .claude-global/mods/cache-keeper && nix shell nixpkgs#typescript -c tsc -p .claude-global/mods/cache-keeper`
Expected: 全 pass、Validation passed、tsc exit 0

- [ ] **Step 7: Commit**

```bash
git add .claude-global/mods/cache-keeper
git commit -m "feat: cache-keeper の止め方を時刻ルールと ping 回数上限に変える"
```

### Task 3: 有効化と実機確認

**Files:**
- Modify: `.claude-global/settings.json`（`env.CLAUDE_CODE_PLUGIN_DIRS` の末尾に `:/home/aya/.dotfiles/.claude-global/mods/cache-keeper`）
- Modify: `.claude-global/mods/README.md`（一覧に `cache-keeper` の行: 外部製、取得元・commit `46570fd`・MIT、手を入れた箇所 = `policy.ts` の止め方・`register.ts` の設定と手動 ping の数え方・`tsconfig.json`/`.gitignore`、記録は `~/.claude/cache-keeper/<セッションID>.jsonl`）

- [ ] **Step 1: 2 ファイルを編集する**
- [ ] **Step 2: 使い捨て tmux セッションで確認する**: `P=$(tmux new-session -d -s kwcheck -x 200 -y 45 -c /home/aya/.dotfiles -P -F '#{pane_id}' zsh)` → `claude` を起動 → 短い質問を 1 つ送る → `/keepwarm now` → `/keepwarm status`

Expected: `/keepwarm now` がキャッシュに当たったと表示され、`ls ~/.claude/cache-keeper/` にそのセッションの jsonl ができて ping の行がある。`/keepwarm status` の ping 数は 0 のまま（手動は数えない）

- [ ] **Step 3: 入力欄の下の表示を記録する**: `tmux capture-pane -p -t "$P"` で、cache-keeper の状態行と prompt-cache-control の行がどう並ぶか、`/keepwarm now` の後に prompt-cache-control の残り時間が延びたかを控え、`tmux kill-session -t kwcheck`。結果はユーザーへの報告に含める
- [ ] **Step 4: Commit（自分の変更だけを index に載せる）**: `settings.json` は HEAD 版に `CLAUDE_CODE_PLUGIN_DIRS` の変更だけを入れたものを `git hash-object -w` + `git update-index --cacheinfo` で載せ、`git diff --cached` に `advisorModel` が無く、`-` 行が `CLAUDE_CODE_PLUGIN_DIRS` の旧値 1 行だけであることを確認する

```bash
git add .claude-global/mods/README.md
git commit -m "feat: cache-keeper mod を有効にする"
git push
```

### Task 4: 引き継ぎの検索スクリプト

**Files:**
- Create: `.claude-global/skills/pickup/scripts/find_handoff.py`
- Test: `.claude-global/skills/pickup/scripts/test_find_handoff.py`

**Interfaces:**
- Produces:
  - CLI: `python3 -I find_handoff.py [--root <memories dir>] [terms...]`（`--root` の既定は `~/.claude/skills/agent-memory/memories`）。標準出力に JSON 1 つ: `{"stage": "handoff-open" | "handoff-all" | "work-in-progress" | "all" | "none", "hits": [{"path": str, "summary": str, "created": str, "status": str}]}`。`hits` は `created` の新しい順
  - `def matches(text: str, terms: list[str]) -> bool`
  - `def search(root: Path, terms: list[str]) -> dict`

- [ ] **Step 1: 失敗するテストを書く**（`unittest`、`tempfile.TemporaryDirectory` に frontmatter 付きの md を作る）
  - `matches("…/pull/1210 …", ["1210"])` は True、`["#1210"]` `["PR1210"]` `["pr1210"]` も True
  - `matches("課題 No00007400", ["7400"])` は True、`["No7400"]` も True
  - `matches("…/pull/1210 …", ["12"])` は False、`matches("#12", ["1210"])` も False
  - `matches("阪急 アイコン 修正", ["阪急", "アイコン"])` は True、`["阪急", "ロゴ"]` は False（全語を含む・大小文字無視）
  - `search`: `handoff` タグで `blocked` のものに当たれば `stage == "handoff-open"`。それに無く `resolved` の handoff にあれば `"handoff-all"`。handoff に無く `work-in-progress/` の別メモにあれば `"work-in-progress"`。それ以外のカテゴリにだけあれば `"all"`。どこにも無ければ `{"stage": "none", "hits": []}`
  - 引数なし: `handoff` タグで `blocked` のものだけを新しい順に返す（`stage == "handoff-open"`）

- [ ] **Step 2: 失敗を確かめる**

Run: `python3 -I -m unittest discover -s .claude-global/skills/pickup/scripts -v`
Expected: FAIL（`find_handoff` が無い）

- [ ] **Step 3: 実装する**: 数字の語は `^(?:#|pr|no)?0*(\d+)$`（大小文字無視）で番号 `n` にし、本文に `(?<!\d)0*n(?!\d)` で当てる。それ以外の語は小文字化した部分一致。frontmatter（先頭の `---` 区切り）から `summary` / `created` / `status` / `tags` を行単位の正規表現で読む（YAML ライブラリは使わない）。照合対象はファイル全文
- [ ] **Step 4: 通ることを確かめる**

Run: `python3 -I -m unittest discover -s .claude-global/skills/pickup/scripts -v`
Expected: 全 OK

- [ ] **Step 5: Commit**

```bash
git add .claude-global/skills/pickup/scripts
git commit -m "feat: 引き継ぎを番号や言葉でゆるく探すスクリプトを追加する"
```

### Task 5: `/handoff` と `/pickup` のスキル

**Files:**
- Create: `.claude-global/skills/handoff/SKILL.md`
- Create: `.claude-global/skills/handoff/scripts/collect.sh`
- Test: `.claude-global/skills/handoff/scripts/test_collect.sh`
- Create: `.claude-global/skills/pickup/SKILL.md`

**Interfaces:**
- Consumes: Task 4 の `find_handoff.py` の CLI と JSON
- Produces:
  - `collect.sh`: 引数なし、作業ディレクトリについて `key=value` 行を出す: `cwd` / `remote`（`origin` の URL、無ければ空）/ `branch`（無ければ空）/ `pr_url` / `pr_number`（remote が github.com のときだけ `gh pr view --json url,number` で取り、失敗・PR 無しは空）/ `created`（`date '+%Y-%m-%d %H:%M'`）。どの項目が取れなくても exit 0
  - 引き継ぎファイル: `memories/work-in-progress/handoff-<YYYYMMDD-HHMM>-<slug>.md`

- [ ] **Step 1: `test_collect.sh` を書く**（`mktemp -d` の中で: git 管理外のディレクトリ → exit 0 で `remote=` と `branch=` が空 / `git init` して `origin` を `https://gitbucket.example/x.git` にしたリポジトリ → `branch=` に値があり `pr_url=` は空で exit 0）
- [ ] **Step 2: 失敗を確かめる**: `bash .claude-global/skills/handoff/scripts/test_collect.sh` → FAIL（`collect.sh` が無い）
- [ ] **Step 3: `collect.sh` を実装する**（`set -euo pipefail`、各 git/gh 呼び出しは失敗しても空で続ける）。通ることを確かめる: 同じコマンド → 全 OK
- [ ] **Step 4: セッション ID の取り方を決める**: スキル本文で `${CLAUDE_SESSION_ID}` が置換されるかを試し（使い捨てスキルで値を echo させる）、置換されるならそれを使う。されなければ他の確実な方法を調べ、どの方法にしたかを `handoff/SKILL.md` に 1 行書く
- [ ] **Step 5: `handoff/SKILL.md` を書く**: frontmatter の `description` は「/handoff」「引き継ぎを書いて」「引き継ぎ残して」で起動する旨。手順: `collect.sh` を実行 → GitBucket の remote なら MCP でブランチの PR を調べる → 引き継ぎファイルを書く（frontmatter: `summary` に題名と待ち相手と PR/課題番号、`created`、`status: blocked`、`tags: [handoff, <リポジトリ名>]`。本文の見出し: 待っているもの（誰の何）/ 今の状態 / 決めたことと理由 / 次にやること / 関連（PR URL・課題No・スレッド）/ 元のセッション（`cwd` と `claude --resume <ID>`））→ パスと題名をユーザーに示し、「このセッションは消してよい」と伝える
- [ ] **Step 6: `pickup/SKILL.md` を書く**: `description` は「/pickup」「引き継ぎから再開」「続きから」で起動する旨。手順: `find_handoff.py <引数>` を実行 → `stage` が `none` なら `find-session` スキルを提案 → 1 件ならその md を読み、複数なら題名・日付・待ち相手を並べてユーザーに選ばせる → 読んだら内容を短く示し、記録された `cwd` が今と違えば伝え、`claude --resume <ID>` で元の会話に戻れることを示す → ユーザーの指示どおり続ける → 作業が終わったら `status: resolved` に書き換える
- [ ] **Step 7: 通しで確かめる**: このリポジトリで `/handoff` を 1 回実行して引き継ぎを作り、新しいセッションで `/pickup <その PR 番号か題名の語>` が 1 件で当たって読み込めること。確認後、試しに作った引き継ぎは `status: resolved` にする
- [ ] **Step 8: Commit**

```bash
git add .claude-global/skills/handoff .claude-global/skills/pickup
git commit -m "feat: 引き継ぎを書く /handoff と再開する /pickup スキルを追加する"
git push
```
