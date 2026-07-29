# Rocket Chat スレッド探索の syncThreadsList 化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `expand_threads` のスレッドID収集に `chat.syncThreadsList` を加え、親が対象期間外にあるスレッドの期間内返信を取り逃さないようにする。

**Architecture:** `scripts/lib/rocketchat.sh` の `expand_threads` 関数だけを変更する。従来の「期間内 history の `tmid`/`tcount`」由来のIDに、`chat.syncThreadsList` が返す「`tlm` が期間内のスレッド」の親IDを**和集合**で加える。後続の重複排除・期間フィルタ・整形は既存のまま動く。`rocketchat.sh` は日報 cron と work-report の共通層なので1箇所の変更で両経路に効く。

**Tech Stack:** bash / curl / python3（JSON処理）/ Rocket Chat REST API v1

**Spec:** `docs/superpowers/specs/2026-07-29-rocketchat-thread-discovery-design.md`

**調査記録:** `docs/rocketchat-known-limits-investigation-2026-07-28.md`

## Global Constraints

- 対象リポジトリは `/home/aya/.dotfiles`（WSL側のメイン作業場）
- コミットメッセージのプレフィックスは `feat:` / `fix:` / `refactor:` / `docs:` / `chore:`
- **cron が毎晩 22:10 に `fire-daily-review.sh` を実行する。** 各タスクの完了時点で cron が壊れていない状態を保つこと
- テストは既存流儀に従う: `scripts/lib/rocketchat-test.sh` に追記。`assert_grep` / `assert_absent` / `assert_eq` 関数、`ok:` / `NG:` 出力、全通過で `ALL OK` を出して `exit 0`
- **テストは実 API を叩かない。** `RC_CURL` に `$TMP/bin/curl-stub.sh` を差し込み fixture JSON を返させる
- 認証情報（`RC_TOKEN` / `RC_USER_ID`）は fixture・ログ・コミットに一切含めない。テストのダミー値は `dummy-token` / `dummy-user`
- 自分のユーザー名は `mori.a`（環境変数 `RC_ME`、既定 `mori.a`）
- **`chat.getThreadMessages` は `oldest`/`latest` を無視する。** スレッド展開後の `ts` による期間フィルタ（`rocketchat.sh:229`）は削除・変更しない
- **1ルームの失敗で全体を落とさない。** `syncThreadsList` の失敗は stderr に警告して従来経路のみで継続する
- 予算判定はバイト数（`wc -c`）で行う。`${#var}` は cron 環境（`LANG` 未設定）でバイト数になるため使わない
- `shellcheck` の指摘をゼロに保つ（`nix run nixpkgs#shellcheck scripts/lib/rocketchat.sh`）
- 実装完了まで **push しない**（コミットのみ。push はユーザー承認後）

## File Structure

| ファイル | 責務 | 変更 |
|---|---|---|
| `scripts/lib/rocketchat.sh` | Rocket Chat 取得・絞り込み・整形 | `expand_threads`（`:141-235`）のスレッドID収集部のみ |
| `scripts/lib/rocketchat-test.sh` | 上記のテスト（現在67件） | curl スタブに `syncThreadsList` 分岐 + fixture + テストケース追記 |
| `docs/rocketchat-multiroom-2026-07-28.md` | 前回実装のまとめ | 「既知の限界」節を解消済みに更新 |

`rocketchat.sh` は現在419行。変更は `expand_threads` 内に閉じるため分割はしない。

**タスクの流れ:** Task 1 でテスト基盤（スタブ分岐 + fixture）を用意して失敗するテストを書き、Task 2 で実装、Task 3 で失敗時の防御、Task 4 で変異テストによる空証明の排除、Task 5 で実データ回帰確認、Task 6 でドキュメント更新。

---

### Task 1: `syncThreadsList` の fixture と失敗するテストを用意する

親が対象期間外にあるスレッドを再現する fixture を作り、現状の実装では**取り逃すことを確認する**。

**Files:**
- Modify: `scripts/lib/rocketchat-test.sh`（curl スタブ分岐・fixture・テストケース）

**Interfaces:**
- Consumes: 既存の `run_rc()` / `assert_grep` / `assert_absent` / `curl-stub.sh`
- Produces:
  - fixture `sync-ejikunabi.json`（`chat.syncThreadsList` のレスポンス）
  - fixture `thread-ejikunabi-4.json`（親が期間外のスレッドの返信）
  - curl スタブ分岐 `*chat.syncThreadsList*rid=room-ejikunabi*`
  - センチネル文字列 `SYNC-OUTSIDE-PARENT-SENTINEL`（Task 2 以降で採用確認に使う）

- [ ] **Step 1: curl スタブに `syncThreadsList` 分岐を追加する**

`scripts/lib/rocketchat-test.sh` の curl スタブ（`$TMP/bin/curl-stub.sh` を作る heredoc 内）の
`case "$url" in` に、既存の `*chat.getThreadMessages*tmid=thr-ejikunabi-3*)` 行の**直後**に以下を追加する。

```bash
  # chat.syncThreadsList: 期間内に更新されたスレッドの親一覧を返す。
  # 親の ts が対象期間外(7/10)でも tlm が期間内(7/22)なら返るという
  # 実APIの挙動を模擬する。oldest/latest のrange-awareフィルタは通さず
  # 生返しする（threads は messages キーではないためフィルタが効かない）。
  *chat.syncThreadsList*rid=room-ejikunabi*) cat "$RC_FIXTURE_DIR/sync-ejikunabi.json"; exit 0 ;;
  # 上記以外のルームの syncThreadsList は空を返す（既定）。
  *chat.syncThreadsList*) echo '{"success":true,"threads":{"update":[],"remove":[]}}'; exit 0 ;;
  *chat.getThreadMessages*tmid=thr-ejikunabi-4*) cat "$RC_FIXTURE_DIR/thread-ejikunabi-4.json"; exit 0 ;;
```

- [ ] **Step 2: fixture を追加する**

既存の `thread-ejikunabi-3.json` の heredoc の**直後**に以下を追加する。

```bash
# sync-ejikunabi: chat.syncThreadsList のレスポンス。
# thr-ejikunabi-4 は「親の ts が対象期間外(7/10)、tlm が期間内(7/22)」という
# 本変更の主目的のケース。history には親も返信も一切現れないため、
# 従来の tmid/tcount 収集では発見できない（= syncThreadsList でのみ発見可能）。
#
# 重要: 親 ts は必ず期間外(7/10)に置く。期間内にすると history 側の
# tcount/tmid 経路でも同じIDが導出され、syncThreadsList を無効化しても
# テストが通ってしまう（既存の空証明「tmid/tcount の独立性」と同型）。
#
# thr-ejikunabi-1 も併記する。これは従来経路でも発見できるIDであり、
# 和集合が正しく重複排除されること（二重取得で壊れないこと）の確認用。
cat > "$TMP/fixtures/sync-ejikunabi.json" <<'EOF'
{"success":true,"threads":{"update":[
 {"_id":"thr-ejikunabi-4","ts":"2026-07-10T00:00:00.000Z","tlm":"2026-07-22T14:30:00.000Z","tcount":2},
 {"_id":"thr-ejikunabi-1","ts":"2026-07-22T00:30:00.000Z","tlm":"2026-07-22T02:00:00.000Z","tcount":3}
],"remove":[]}}
EOF

# thread-ejikunabi-4: 親が期間外のスレッドの全返信。
# ejk4-reply は mori.a の発言なので render_room の第1段階(own)を満たし、
# このスレッドが発見されればルームは採用される。
# ejk4-outside は期間外(7/11)。chat.getThreadMessages は oldest/latest を
# 無視して全件返すため、expand_threads 側の ts フィルタが効くことの検証用。
cat > "$TMP/fixtures/thread-ejikunabi-4.json" <<'EOF'
{"messages":[
 {"_id":"thr-ejikunabi-4","ts":"2026-07-10T00:00:00.000Z","u":{"username":"other.p"},"msg":"期間外の親メッセージ","tmid":"thr-ejikunabi-4"},
 {"_id":"ejk4-outside","ts":"2026-07-11T00:00:00.000Z","u":{"username":"other.p"},"msg":"SYNC-OUTSIDE-RANGE-SENTINEL","tmid":"thr-ejikunabi-4"},
 {"_id":"ejk4-reply","ts":"2026-07-22T14:30:00.000Z","u":{"username":"mori.a"},"msg":"SYNC-OUTSIDE-PARENT-SENTINEL","tmid":"thr-ejikunabi-4"}
]}
EOF
```

- [ ] **Step 3: 失敗するテストを追記する**

`scripts/lib/rocketchat-test.sh` の**末尾**（`if [ "$fails" -eq 0 ]` 行の直前）に追加する。

```bash
# ===== syncThreadsList によるスレッド発見 =====
# 親が対象期間外にあるスレッドの期間内返信が回収されることを検証する。
# 従来の tmid/tcount 収集は期間内 history のみを見るため、このケースを
# 構造的に発見できない（真因は tshow=None の返信が history に出ないこと）。
out="$(run_rc --from 2026-07-21 --to 2026-07-28 2>/dev/null)"
assert_grep "親が期間外のスレッドの期間内返信が回収される" \
  "SYNC-OUTSIDE-PARENT-SENTINEL" "$out"
assert_absent "syncThreadsListで発見したスレッドでも期間外は落ちる" \
  "SYNC-OUTSIDE-RANGE-SENTINEL" "$out"
```

- [ ] **Step 4: テストを実行して失敗を確認する**

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | tail -8`

Expected: `NG: 親が期間外のスレッドの期間内返信が回収される → 'SYNC-OUTSIDE-PARENT-SENTINEL' が出力に無い` が出て、末尾が `1 件失敗` で `exit 1`。

もう1件（`期間外は落ちる`）は**この時点では通る**。スレッド自体が発見されていないので期間外メッセージも出力に無いため。これは Task 2 で実装した後に初めて意味を持つ検証になる。

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat-test.sh
git commit -m "test: 親が期間外のスレッドを取り逃す問題の失敗テストを追加

chat.syncThreadsList の fixture とスタブ分岐を用意し、親の ts が
対象期間外にあるスレッドの期間内返信が現状では回収されないことを
確認する失敗テストを追加した。"
```

---

### Task 2: `expand_threads` に `syncThreadsList` 由来のIDを加える

**Files:**
- Modify: `scripts/lib/rocketchat.sh:141-160`（`expand_threads` のスレッドID収集部）

**Interfaces:**
- Consumes: 既存の `rc_api <path> <query-string>` / 変数 `$oldest`
- Produces: `expand_threads` の挙動変更のみ（シグネチャ・入出力形式は不変。stdin に履歴 JSON、stdout に展開済み履歴 JSON）

- [ ] **Step 1: `expand_threads` のシグネチャを変更してルームIDを受け取れるようにする**

`syncThreadsList` は `rid`（ルームID）を必要とするが、現在の `expand_threads` は引数を取らない。
`scripts/lib/rocketchat.sh:141` の関数定義を変更する。

変更前:

```bash
expand_threads() {
  local hist tids tid extra tresp
  hist="$(cat)"
```

変更後:

```bash
expand_threads() {
  local rid="$1"
  local hist tids tid extra tresp sresp stids
  hist="$(cat)"
```

- [ ] **Step 2: 呼び出し側にルームIDを渡す**

`scripts/lib/rocketchat.sh:351`（`collect_blocks` 内）を変更する。

変更前:

```bash
    block="$(room_history "$rid" "$t" | expand_threads | render_room "$name" "$t")"
```

変更後:

```bash
    block="$(room_history "$rid" "$t" | expand_threads "$rid" | render_room "$name" "$t")"
```

- [ ] **Step 3: `syncThreadsList` 由来のIDを収集して和集合を取る**

`scripts/lib/rocketchat.sh` の `tids="$(...)"` ブロック（`:145-159`）の**直後**、
`[ -n "$tids" ] || { ... }` 行の**直前**に以下を挿入する。

```bash
  # chat.syncThreadsList で「期間内に更新されたスレッド」の親IDを直接引く。
  #
  # history 系エンドポイントは tshow=None（通常のスレッド返信）を返さないため、
  # 「親が対象期間外・返信が期間内」のスレッドは tmid/tcount 収集では構造的に
  # 発見できない（実測: 7/27 の e食なび で7件を取り逃していた）。
  # syncThreadsList は各スレッドの tlm(thread last message) を返すので、
  # 親の ts が期間外でも tlm が期間内なら発見できる。
  #
  # 従来の tmid/tcount 由来と和集合を取る。updatedSince の厳密な意味論
  # （境界の開閉・サーバ側の更新判定）を確定できていないため、従来経路を
  # 残して片方が取りこぼしても現状より悪化しないようにしてある。
  # 重複は後段の _id ベース重複排除が吸収する。
  sresp="$(rc_api "chat.syncThreadsList" "rid=${rid}&updatedSince=${oldest}" || true)"
  stids="$(printf '%s' "$sresp" | RC_SYNC_OLDEST="$oldest" python3 -c '
import sys, json, os
oldest = os.environ["RC_SYNC_OLDEST"]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for th in (d.get("threads", {}) or {}).get("update", []) or []:
    # tlm が期間内のスレッドだけを対象にする。updatedSince が期待通り効かない
    # 場合でも、ここで絞れば古いスレッドを引き込まない。
    if (th.get("tlm") or "") >= oldest and th.get("_id"):
        print(th["_id"])
' 2>/dev/null || true)"
  if [ -n "$stids" ]; then
    tids="$(printf '%s\n%s' "$tids" "$stids" | grep -v '^$' | sort -u)"
  fi
```

- [ ] **Step 4: テストを実行して通ることを確認する**

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | tail -6`

Expected: 末尾が `ALL OK`。`ok: 親が期間外のスレッドの期間内返信が回収される` と
`ok: syncThreadsListで発見したスレッドでも期間外は落ちる` の両方が出る。

既存67件が1件も壊れていないことも確認する（`NG:` が1行も無いこと）。

- [ ] **Step 5: shellcheck を通す**

Run: `cd /home/aya/.dotfiles && nix run nixpkgs#shellcheck -- scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh`

Expected: 出力なし（指摘ゼロ）。指摘が出た場合は修正してから次へ進む。

- [ ] **Step 6: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat.sh
git commit -m "feat: expand_threads に chat.syncThreadsList 由来のスレッドIDを追加

親の ts が対象期間外にあるスレッドの期間内返信を回収できるようにした。
真因は tshow=None の返信が history に現れないことで、従来の tmid/tcount
収集では構造的に発見できなかった。従来経路との和集合を取り、取りこぼしが
あっても現状より悪化しない形にしてある。"
```

---

### Task 3: `syncThreadsList` 失敗時に従来経路で継続することを保証する

`room_history` / `chat.getThreadMessages` と同じ防御水準に揃える。

**Files:**
- Modify: `scripts/lib/rocketchat.sh`（`expand_threads` 内の `syncThreadsList` 応答検証）
- Modify: `scripts/lib/rocketchat-test.sh`（スタブ分岐・fixture・テスト）

**Interfaces:**
- Consumes: Task 2 で追加した `sresp` / `stids` 変数
- Produces: stderr メッセージ `(Rocket Chat: ルーム <rid> のスレッド一覧取得に失敗しスキップ)`

- [ ] **Step 1: 失敗を再現するスタブ分岐と fixture を追加する**

`scripts/lib/rocketchat-test.sh` の curl スタブの `case` に、Task 1 で追加した
`*chat.syncThreadsList*)` の**直前**に以下を追加する（より具体的な分岐を先に置く）。

```bash
  # room-syncfail: history と getThreadMessages は正常だが syncThreadsList
  # だけが HTML エラーページを返すケース。従来の tmid/tcount 経路のみで
  # 継続することを検証する。
  *chat.syncThreadsList*rid=room-syncfail*) echo '<html>error</html>'; exit 0 ;;
```

`rooms.json` fixture の `room-tfail` 行の**直後**（末尾）に以下を追加する。
末尾に置くのは Task 5 の budget テスト（優先度1グループの先頭2ルームで break する前提）を壊さないため。

```bash
 {"_id":"room-syncfail","t":"c","name":"sync-fail-room","lm":"2026-07-22T16:00:00.000Z"},
```

注意: 上記の行は `rooms.json` の `"update":[` 配列内に入れる。直前の行（`room-tfail`）の
末尾にカンマが無ければ追加すること。最終要素にはカンマを付けない（JSON構文）。

`thread-ejikunabi-4.json` の heredoc の**直後**に history fixture を追加する。

```bash
# hist-syncfail: syncThreadsList が失敗しても、従来の tmid/tcount 経路で
# 発見できるスレッドは回収され続けることを検証するための history。
# sf-parent は tcount を持つので tmid/tcount 経路で発見できる。
cat > "$TMP/fixtures/hist-syncfail.json" <<'EOF'
{"messages":[
 {"_id":"sf-parent","ts":"2026-07-22T16:00:00.000Z","u":{"username":"mori.a"},"msg":"従来経路の親","tcount":2}
]}
EOF
```

curl スタブの `case` に history 分岐を追加する（`*roomId=room-tfail*)` 行の直後）。

```bash
  *roomId=room-syncfail*) fx="$RC_FIXTURE_DIR/hist-syncfail.json" ;;
```

`chat.getThreadMessages` の分岐を追加する（`*chat.getThreadMessages*tmid=thr-ejikunabi-4*)` の直後）。

```bash
  *chat.getThreadMessages*tmid=sf-parent*) cat "$RC_FIXTURE_DIR/thread-syncfail.json"; exit 0 ;;
```

対応する fixture を `hist-syncfail.json` の heredoc の直後に追加する。

```bash
# thread-syncfail: 従来経路(tcount)で発見されるスレッドの返信。
# syncThreadsList が失敗してもこれが出力に残ることを検証する。
cat > "$TMP/fixtures/thread-syncfail.json" <<'EOF'
{"messages":[
 {"_id":"sf-parent","ts":"2026-07-22T16:00:00.000Z","u":{"username":"mori.a"},"msg":"従来経路の親","tcount":2},
 {"_id":"sf-reply","ts":"2026-07-22T16:30:00.000Z","u":{"username":"other.p"},"msg":"SYNCFAIL-FALLBACK-SENTINEL","tmid":"sf-parent"}
]}
EOF
```

- [ ] **Step 2: 失敗するテストを追記する**

`scripts/lib/rocketchat-test.sh` の末尾（`if [ "$fails" -eq 0 ]` の直前）に追加する。

```bash
# syncThreadsList が失敗しても従来経路(tmid/tcount)で継続する
out="$(run_rc --from 2026-07-21 --to 2026-07-28 2>"$TMP/syncfail.err")"
err="$(cat "$TMP/syncfail.err")"
assert_grep "syncThreadsList失敗でも従来経路のスレッドは残る" \
  "SYNCFAIL-FALLBACK-SENTINEL" "$out"
assert_grep "syncThreadsList失敗がstderrに記録される" \
  "ルーム room-syncfail のスレッド一覧取得に失敗しスキップ" "$err"
assert_grep "syncThreadsList失敗後も他のルームは正常処理される" \
  "mori.a-times" "$out"
```

- [ ] **Step 3: テストを実行して stderr のテストが失敗することを確認する**

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | grep -E 'NG:|ALL OK|件失敗'`

Expected: `NG: syncThreadsList失敗がstderrに記録される → ...` が出る。
`SYNCFAIL-FALLBACK-SENTINEL` の方は**この時点で既に通る**（不正JSONでも `stids` が空になり
従来経路が生きるため）。stderr 警告だけが未実装。

- [ ] **Step 4: JSON 妥当性検証と stderr 警告を実装する**

`scripts/lib/rocketchat.sh` の Task 2 で追加した `sresp="$(...)"` 行の**直後**に挿入する。

```bash
  # room_history と同じ防御: HTMLエラーページ等が返った場合に無音で
  # スレッド発見が消えないよう、JSON妥当性を検証して警告を出す。
  # 失敗しても従来の tmid/tcount 経路は生きているため処理は継続する。
  if ! printf '%s' "$sresp" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
    echo "(Rocket Chat: ルーム $rid のスレッド一覧取得に失敗しスキップ)" >&2
    sresp='{"threads":{"update":[]}}'
  fi
```

- [ ] **Step 5: テストを実行して全部通ることを確認する**

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | tail -6`

Expected: 末尾が `ALL OK`。`NG:` が1行も無いこと。

- [ ] **Step 6: shellcheck を通す**

Run: `cd /home/aya/.dotfiles && nix run nixpkgs#shellcheck -- scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh`

Expected: 出力なし。

- [ ] **Step 7: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh
git commit -m "fix: syncThreadsList の失敗を検知して従来経路で継続する

HTMLエラーページ等が返った際に無音でスレッド発見が消えないよう、
room_history と同じJSON妥当性検証と stderr 警告を追加した。"
```

---

### Task 4: 変異テストで空証明を排除する

「テストが通る」と「テストが機能する」は別。各テストについて**該当コードを壊してテストが落ちるか**を確認する。

**Files:**
- Modify: `scripts/lib/rocketchat.sh`（一時的に壊して戻す。最終的に変更は残さない）
- Modify: `scripts/lib/rocketchat-test.sh`（空証明が見つかった場合のみ fixture 修正）

**Interfaces:**
- Consumes: Task 2/3 の実装
- Produces: なし（検証タスク。空証明が見つかった場合のみテスト修正をコミット）

- [ ] **Step 1: `syncThreadsList` 収集を無効化してテストが落ちるか確認する**

`scripts/lib/rocketchat.sh` の `if [ -n "$stids" ]; then` ブロックを一時的に無効化する。

```bash
# 変異: 和集合を取らない（syncThreadsList の結果を捨てる）
  if false; then
    tids="$(printf '%s\n%s' "$tids" "$stids" | grep -v '^$' | sort -u)"
  fi
```

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | grep -E 'NG:|ALL OK'`

Expected: `NG: 親が期間外のスレッドの期間内返信が回収される` が出ること。

**出なかった場合は空証明。** fixture の親 `ts` が期間内になっていないか確認する
（期間内だと従来の `tmid`/`tcount` 経路で同じIDが導出されてしまう）。
`sync-ejikunabi.json` の `thr-ejikunabi-4` の `ts` が `2026-07-10T00:00:00.000Z`
であることを確認し、`hist-ejikunabi.json` に `thr-ejikunabi-4` を指す `tmid` や
`tcount` を持つメッセージが**存在しない**ことを確認する。

確認後、変異を元に戻す（`if false` → `if [ -n "$stids" ]`）。

- [ ] **Step 2: `tlm` フィルタを無効化してテストが落ちるか確認する**

`scripts/lib/rocketchat.sh` の python 内の `tlm` 判定を一時的に緩める。

```python
# 変異: tlm フィルタを外す
    if th.get("_id"):
        print(th["_id"])
```

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | grep -E 'NG:|ALL OK'`

Expected: `ALL OK`（このテストセットでは落ちない）。

理由: fixture の2スレッドは両方 `tlm` が期間内なので、フィルタを外しても結果が変わらない。
これは**意図的に許容する空証明**である。`updatedSince` がサーバ側で効くため二重の防御であり、
`tlm` フィルタは「`updatedSince` が期待通り効かない場合の保険」に過ぎない。

保険が効くことを検証したい場合は `sync-ejikunabi.json` に `tlm` が期間外のスレッドを
追加することになるが、それは `updatedSince` を無視するスタブを書くことでしか再現できず、
実 API の挙動から乖離する。**このタスクでは追加しない**（後追い候補に記録する）。

変異を元に戻す。

- [ ] **Step 3: 期間フィルタを無効化してテストが落ちるか確認する**

`scripts/lib/rocketchat.sh:229` の期間外除外を一時的に無効化する。

```bash
# 変異: 期間フィルタを外す
    if False:   # ← 元は: if ts < oldest or ts >= latest:
        continue
```

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | grep -E 'NG:|ALL OK'`

Expected: `NG: syncThreadsListで発見したスレッドでも期間外は落ちる` が出ること。

**出なかった場合は空証明。** `thread-ejikunabi-4.json` の `ejk4-outside`（`ts=2026-07-11`）が
時間窓（起点±30分）にも入らない位置にあることを確認する。`room-ejikunabi` は `t="c"` で
`RC_CHANNEL`（`mori.a-times`）と名前が違うため時間窓分岐を通る。起点は `ejk4-reply`
（`2026-07-22T14:30`）なので、11日前の `ejk4-outside` は窓外である。

変異を元に戻す。

- [ ] **Step 4: stderr 警告を無効化してテストが落ちるか確認する**

`scripts/lib/rocketchat.sh` の Task 3 で追加した警告行を一時的に削る。

```bash
  if ! printf '%s' "$sresp" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
    sresp='{"threads":{"update":[]}}'
  fi
```

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | grep -E 'NG:|ALL OK'`

Expected: `NG: syncThreadsList失敗がstderrに記録される` が出ること。

変異を元に戻す。

- [ ] **Step 5: 全テストが通る状態に戻っていることを確認する**

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | tail -4 && git diff --stat scripts/lib/rocketchat.sh`

Expected: `ALL OK` が出て、`git diff --stat` が**何も出力しない**（変異が全て戻っている）。

`git diff` に差分が残っている場合は変異が戻っていない。`git checkout scripts/lib/rocketchat.sh`
で Task 3 のコミット状態に戻す（Task 3 でコミット済みなので実装は失われない）。

- [ ] **Step 6: 空証明が見つかった場合のみコミット**

Step 1/3/4 で空証明が見つかり fixture を修正した場合のみコミットする。
見つからなければこのタスクはコミット不要。

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat-test.sh
git commit -m "test: 変異テストで見つかった空証明を修正"
```

---

### Task 5: 実データでの回帰確認

**Files:**
- なし（測定のみ。結果は Task 6 でドキュメントに記録する）

**Interfaces:**
- Consumes: Task 2/3 の実装
- Produces: 測定結果（Task 6 の記録内容）

- [ ] **Step 1: 6日分の出力バイト数を測定する**

Run:

```bash
cd /home/aya/.dotfiles
set -a; source scripts/daily-review/.env.local; set +a
for d in 2026-07-21 2026-07-22 2026-07-23 2026-07-24 2026-07-27 2026-07-28; do
  b=$(bash scripts/lib/rocketchat.sh --from "$d" --to "$d" --budget 15000 2>/dev/null | wc -c)
  echo "$d = ${b}バイト"
done
```

Expected（実装前の実測値と比較する）:

| 日付 | 実装前 | 期待値 |
|---|---|---|
| 2026-07-21 | 1,494 | 1,494（不変） |
| 2026-07-22 | 6,333 | 6,333（不変） |
| 2026-07-23 | 9,608 | 9,608（不変・最大日） |
| 2026-07-24 | 5,786 | 5,786（不変） |
| 2026-07-27 | 5,781 | **約 7,197**（+1,416） |
| 2026-07-28 | 2,703 | 2,703（不変） |

最大日（7/23）が 9,608 のままであること（`MAX_RC_CHARS` 15,000 の 64%）を確認する。
7/27 以外が変化した場合は原因を調査すること（意図しないスレッドの引き込みの可能性）。

- [ ] **Step 2: 7/27 に `e食なび` が現れることを確認する**

Run:

```bash
cd /home/aya/.dotfiles
set -a; source scripts/daily-review/.env.local; set +a
bash scripts/lib/rocketchat.sh --from 2026-07-27 --to 2026-07-27 --budget 15000 2>/dev/null \
  | grep -A9 'e食なび'
```

Expected: `===== e食なび [発言1,@me1] ...` のヘッダが出て、以下が含まれる。

- `そちらです！` （資料受領。以前「依頼したが未応答」と誤報告した原因）
- `ちらし検索用APIについて` （`@mori.a` 直指名の仕様変更共有）

- [ ] **Step 3: DM込み（work-report 経路）の増分を測定する**

Run:

```bash
cd /home/aya/.dotfiles
set -a; source scripts/daily-review/.env.local; set +a
bash scripts/lib/rocketchat.sh --from 2026-07-21 --to 2026-07-28 --include-dm 2>/dev/null | wc -c
```

Expected: 実装前の実測値は 35,042バイト / 11ルーム。増分を記録する。
work-report は対話経路で上限が無いため、増えても問題にはならない。
値は Task 6 でドキュメントに記録する。

- [ ] **Step 4: stderr に予期しない警告が出ていないことを確認する**

Run:

```bash
cd /home/aya/.dotfiles
set -a; source scripts/daily-review/.env.local; set +a
bash scripts/lib/rocketchat.sh --from 2026-07-27 --to 2026-07-27 --budget 15000 2>&1 >/dev/null
```

Expected: `スレッド一覧取得に失敗` が出ないこと。出た場合は `syncThreadsList` が
実環境で失敗しているため原因を調査する（権限・エンドポイント名・パラメータ）。

`WARN: RC_CHANNEL` の警告は出ない想定（`RC_CHANNEL=mori.a-times` が設定済み）。

- [ ] **Step 5: 日報 cron のペイロード全体を確認する**

Run:

```bash
cd /home/aya/.dotfiles
set -a; source scripts/daily-review/.env.local; set +a
d=2026-07-27
rc=$(bash scripts/lib/rocketchat.sh --from "$d" --to "$d" --budget 15000 2>/dev/null)
sess=$(cat /home/aya/.nb/claude/sessions/$d/*.md 2>/dev/null)
payload="【対象日】${d}

【git活動（当日コミット・ローカル収集）】
(省略)

【Rocket Chat 当日履歴（購読ルーム横断・DM除く）】
${rc}

【セッション要約（${d}・時刻順）】
${sess}"
printf '%s' "$payload" | wc -c
```

Expected: `MAX_PAYLOAD_CHARS`（60,000）を大きく下回ること。
実装前の 7/23 が 37,156バイト＝61% だったため、7/27 は余裕がある想定。

60,000 を超える場合は `build_sessions` のセッション要約が削られる
（`fire-daily-review.sh:174-180`）ため、Rocket Chat ログではなくセッション要約が
犠牲になる。その場合はユーザーに報告して判断を仰ぐこと。

---

### Task 6: ドキュメントを更新する

**Files:**
- Modify: `docs/rocketchat-multiroom-2026-07-28.md`（「既知の限界（未対応）」節）
- Modify: `docs/rocketchat-known-limits-investigation-2026-07-28.md`（実装済みの追記）

**Interfaces:**
- Consumes: Task 5 の測定結果
- Produces: なし（最終タスク）

- [ ] **Step 1: 前回実装のまとめから「既知の限界」を解消済みに更新する**

`docs/rocketchat-multiroom-2026-07-28.md` の `## 既知の限界（未対応）` 節の冒頭
（`**history が0件のルームでスレッドが取り逃される。**` の段落の直前）に以下を挿入する。

```markdown
> **【2026-07-29 更新】この節のスレッド取り逃し問題は解消済み。**
> 調査の結果、真因は「history 0件」ではなく `tshow` フィールドだった
> （`tshow=None` の通常のスレッド返信は history に現れない）。history が
> 6件あるルームでも取り逃していた。`chat.syncThreadsList` を使う実装に
> 変更して解消した。下記の案A/B/C の比較は**前提が誤っていた**ため
> 参考情報として残す（案B のコストも +16% ではなく実測 +88% だった）。
>
> - 調査: `docs/rocketchat-known-limits-investigation-2026-07-28.md`
> - 設計: `docs/superpowers/specs/2026-07-29-rocketchat-thread-discovery-design.md`
> - 計画: `docs/superpowers/plans/2026-07-29-rocketchat-thread-discovery.md`
```

- [ ] **Step 2: 調査記録に実装済みの追記と実測値を記録する**

`docs/rocketchat-known-limits-investigation-2026-07-28.md` の冒頭
（`## 結論サマリ` の直前）に以下を挿入する。Task 5 で測定した実際の値を埋めること。

```markdown
> **【2026-07-29】案D を実装して解消済み。**
> 実装後の実測値は下記のとおり（Task 5 の測定結果）。
>
> | 日付 | 実装前 | 実装後 |
> |---|---|---|
> | 2026-07-23（最大日） | 9,608バイト | <Task 5 Step 1 の実測値> |
> | 2026-07-27 | 5,781バイト | <Task 5 Step 1 の実測値> |
>
> work-report 経路（`--include-dm`・週次）: 35,042バイト → <Task 5 Step 3 の実測値>
>
> 実装: `scripts/lib/rocketchat.sh` の `expand_threads`
```

`<...>` のプレースホルダは必ず Task 5 の実測値に置き換えること。置き換えずにコミットしないこと。

- [ ] **Step 3: 後追い候補に `tlm` フィルタの空証明を記録する**

`docs/rocketchat-known-limits-investigation-2026-07-28.md` の末尾
（`## 推奨` 節の最後、`いずれの方針でも` の段落の後）に以下を追加する。

```markdown
### 実装後に残った検証上の限界（2026-07-29）

`expand_threads` の `tlm >= oldest` フィルタは**テストで機能が証明できていない**。
fixture の全スレッドが `tlm` 期間内であるため、フィルタを外してもテストは通る
（変異テストで確認済みの空証明）。

これは意図的に許容している。`updatedSince` がサーバ側で効くため `tlm` フィルタは
二重の防御であり、「`updatedSince` が期待通り効かない場合の保険」に過ぎない。
保険を検証するには `updatedSince` を無視するスタブが必要で、実 API の挙動から
乖離したテストになる。

`updatedSince` の厳密な意味論（境界の開閉・サーバ側の更新判定）は未確定のまま。
```

- [ ] **Step 4: テストが通る状態を最終確認する**

Run: `cd /home/aya/.dotfiles && bash scripts/lib/rocketchat-test.sh 2>&1 | tail -3 && nix run nixpkgs#shellcheck -- scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh && echo "shellcheck OK"`

Expected: `ALL OK` と `shellcheck OK` の両方が出ること。

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add docs/rocketchat-multiroom-2026-07-28.md docs/rocketchat-known-limits-investigation-2026-07-28.md
git commit -m "docs: スレッド取り逃し問題の解消を記録

真因が tshow フィールドであったこと、旧ドキュメントの案B は前提が
誤っていたことを追記した。実装後の実測値と、tlm フィルタがテストで
証明できていない点も記録した。"
```

- [ ] **Step 6: push の可否をユーザーに確認する**

**push はしない。** 以下を報告してユーザーの判断を仰ぐ。

- 追加したテスト件数と `ALL OK` であること
- Task 5 の実測値（6日分のバイト数・最大日が不変であること・7/27 の増分）
- `e食なび` が回収され、`そちらです！` と `ちらし検索用API` が含まれること
- 変異テストの結果（空証明が見つかったか、`tlm` フィルタの空証明は許容した旨）
- コミット数と各コミットの内容

---

## 自己レビュー結果

**1. Spec coverage**

| Spec の要求 | 対応タスク |
|---|---|
| `expand_threads` のID収集を `syncThreadsList` ベースに | Task 2 |
| 従来の `tmid`/`tcount` と和集合を取る | Task 2 Step 3 |
| 期間フィルタは現状のまま維持 | Task 1 Step 3（テスト）/ Task 4 Step 3（変異） |
| 失敗時は stderr 警告 + 従来経路で継続 | Task 3 |
| DM 経路も同時に有効化 | Task 2（共通層）/ Task 5 Step 3（測定） |
| `lm` ゲート修正はやらない | 実装対象外。Task 6 Step 3 で記録 |
| テスト6ケース追加 | Task 1（2件）/ Task 3（3件）。計5件 |
| 変異テストの実施 | Task 4 |
| 実データ6日での検証 | Task 5 |
| `shellcheck` ゼロ | Task 2 Step 5 / Task 3 Step 6 / Task 6 Step 4 |

**Spec との差異1件:** Spec のテスト方針は6ケースを挙げていたが、本計画では5ケースになった。
Spec の「2. `tshow=None` の返信が拾えること」は「1. 親が期間外・返信が期間内」と
同一の fixture・同一のアサーションで検証される（`SYNC-OUTSIDE-PARENT-SENTINEL` が
history に存在しないことが `tshow=None` の模擬そのもの）ため、独立したテストにしていない。
Spec の「6. DM でも `syncThreadsList` を呼ぶこと」は実 API での確認済み事項であり、
スタブテストでは `t="d"` のルームに対しても同じコードパスが通ることが
既存の `room-dm` fixture で担保されるため、Task 5 Step 3 の実測に委ねた。

**2. Placeholder scan**

Task 6 Step 2 に意図的なプレースホルダ `<Task 5 Step 1 の実測値>` がある。
これは実測値を埋める指示であり、同ステップ内に「置き換えずにコミットしないこと」を明記した。
それ以外の「TBD」「TODO」「適切にエラー処理」等は無い。

**3. Type consistency**

- `expand_threads` のシグネチャ変更（引数なし → `$1` にルームID）は Task 2 Step 1 で定義し、
  Step 2 で呼び出し側（`collect_blocks`）を同時に修正している。整合。
- 変数名 `sresp` / `stids` は Task 2 Step 1 の `local` 宣言に含め、Step 3 で使用。整合。
- stderr メッセージ `(Rocket Chat: ルーム <rid> のスレッド一覧取得に失敗しスキップ)` は
  Task 3 Step 4 の実装と Step 2 のテスト（`ルーム room-syncfail のスレッド一覧取得に失敗しスキップ`）で一致。
- センチネル文字列 `SYNC-OUTSIDE-PARENT-SENTINEL` / `SYNC-OUTSIDE-RANGE-SENTINEL` /
  `SYNCFAIL-FALLBACK-SENTINEL` は fixture 定義とアサーションで一致。
