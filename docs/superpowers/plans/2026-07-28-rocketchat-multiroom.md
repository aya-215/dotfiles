# Rocket Chat 複数ルーム対応 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 日報（cron）と work-report が `mori.a-times` 1チャンネルしか見ていない問題を解消し、購読ルーム全体から自分に関係する情報を収集できるようにする。

**Architecture:** Rocket Chat REST API を叩く共通シェルモジュール `scripts/lib/rocketchat.sh` を新設し、日報 cron と work-report の両方がこれを呼ぶ。ルーム列挙・期間絞り込み・関連メッセージ抽出という決定的な処理をシェル層に集約し、作業内容の分類という非決定的な処理だけを Claude 側に残す。

**Tech Stack:** bash / curl / python3（JSON処理）/ Rocket Chat REST API v1

**Spec:** `docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md`

## Global Constraints

- 対象リポジトリは `/home/aya/.dotfiles`（WSL側のメイン作業場）
- コミットメッセージのプレフィックスは `feat:` / `fix:` / `refactor:` / `docs:` / `chore:`
- `.env.local` は `scripts/daily-review/.env.local` に置いたまま移動しない。`rocketchat.sh` は環境変数 `RC_ENV_FILE` でパスを受け取り、未指定時は `scripts/daily-review/.env.local` を既定とする
- **cron が毎晩 22:10 に `fire-daily-review.sh` を実行する。** 各タスクの完了時点で cron が壊れていない状態を保つこと
- テストは既存流儀に従う: `*-test.sh` という名前、`assert_*` 関数、`ok:` / `NG:` 出力、全通過で `ALL OK` を出して `exit 0`
- テストは実 API を叩かない。`curl` をスタブに差し替え、fixture JSON を返させて検証する
- 認証情報を含む環境変数（`RC_TOKEN` / `RC_USER_ID`）は、テストの fixture・ログ・コミットに一切含めない
- 自分のユーザー名は `mori.a`（環境変数 `RC_ME` で上書き可能、既定値 `mori.a`）
- 時間窓は起点の前後 **30分**（1800秒）
- 予算超過時は**ルーム単位で丸ごと落とす**。バイト位置での切り捨ては行わない
- **`chat.getThreadMessages` は `oldest`/`latest` を無視する**（実測: 期間指定ありで0件、なしで全9件）。スレッド展開後は必ず `ts` で対象期間外を落とすこと。省くと生きているスレッドの全履歴が毎日の日報に混入する
- **予算判定はバイト数で行われる。** `fire-daily-review.sh` の `${#var}` は cron 環境（`LANG` 未設定）でバイト数を数える。日本語は1文字約3バイトなので、文字数で見積もると実使用率を3倍過小評価する。サイズ確認時は必ず `wc -c`（バイト）も測る
- 1回の実行で数十ルームを叩くため、**1ルームの失敗で全体を落とさない**。失敗したルームはスキップして stderr に記録する

## File Structure

| ファイル | 責務 |
|---|---|
| `scripts/lib/rocketchat.sh`（新規） | Rocket Chat からの取得・絞り込み・整形。単体で実行可能な CLI |
| `scripts/lib/rocketchat-test.sh`（新規） | 上記のテスト。curl スタブ + fixture JSON |
| `scripts/daily-review/fire-daily-review.sh`（修正） | `fetch-rocketchat.sh` の呼び出しを `rocketchat.sh` に差し替え、予算処理を修正 |
| `scripts/daily-review/fetch-rocketchat.sh`（削除） | 共通モジュールに吸収されるため Task 7 で削除 |
| `.claude-global/skills/work-report/SKILL.md`（修正） | MCP ツール手順を `rocketchat.sh` 呼び出しに差し替え |

`rocketchat.sh` は約280行程度になる見込みで、責務が「取得と整形」に閉じているため分割しない。

**タスクの流れ:** Task 1〜5 で `rocketchat.sh` を TDD で組み上げ（列挙 → ルーム判定 → メッセージ絞り込み → スレッド展開 → 予算処理）、Task 6 で実データ回帰確認、Task 7〜8 で2つの呼び出し側を切り替え、Task 9 で全体確認する。

---

### Task 1: ルーム列挙と期間フィルタ

**Files:**
- Create: `scripts/lib/rocketchat.sh`
- Create: `scripts/lib/rocketchat-test.sh`

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces:
  - CLI: `rocketchat.sh --from YYYY-MM-DD --to YYYY-MM-DD [--include-dm] [--budget N]`
  - 環境変数: `RC_ENV_FILE`（`.env.local` のパス）/ `RC_ME`（自分のユーザー名、既定 `mori.a`）
  - 内部関数 `rc_api <endpoint> [query...]`: curl のラッパー。`$RC_CURL` が設定されていればそれを curl の代わりに使う（テスト用のフック）
  - 内部関数 `list_active_rooms <from> <to> <include_dm>`: `_id\t<t>\t<name>` を1行1ルームで stdout に出す

このタスクでは列挙までを作る。履歴取得は Task 2。

- [ ] **Step 1: 失敗するテストを書く**

`scripts/lib/rocketchat-test.sh` を新規作成する:

```bash
#!/bin/bash
# rocketchat-test.sh - rocketchat.sh の動作確認テスト
# 使用方法: bash scripts/lib/rocketchat-test.sh （全部 ok なら ALL OK で exit 0）
# 実APIは叩かない。$RC_CURL にスタブを差し込み fixture JSON を返させる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# ---- ダミー .env.local（実認証情報は使わない） ----
cat > "$TMP/env.local" <<'EOF'
RC_BASE_URL=http://rc.test
RC_TOKEN=dummy-token
RC_USER_ID=dummy-user
RC_CHANNEL=mori.a-times
EOF

# ---- curl スタブ ----
# 引数の URL に応じて fixture を返す。rooms.get と *.history を出し分ける。
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl-stub.sh" <<'EOF'
#!/bin/bash
set -u
url="${!#}"   # 最後の引数が URL
case "$url" in
  *rooms.get*)      cat "$RC_FIXTURE_DIR/rooms.json" ;;
  *roomId=room-own*)  cat "$RC_FIXTURE_DIR/hist-own.json" ;;
  *roomId=room-other*) cat "$RC_FIXTURE_DIR/hist-other.json" ;;
  *roomId=room-noise*) cat "$RC_FIXTURE_DIR/hist-noise.json" ;;
  *roomId=room-dm*)   cat "$RC_FIXTURE_DIR/hist-dm.json" ;;
  *)                echo '{"messages":[]}' ;;
esac
EOF
chmod +x "$TMP/bin/curl-stub.sh"

# ---- fixture ----
mkdir -p "$TMP/fixtures"
# 4ルーム: 自分のtimes / 他人のtimes / 自動投稿(ノイズ) / DM
# lm は期間内(7/22)と期間外(7/10)を混ぜる
cat > "$TMP/fixtures/rooms.json" <<'EOF'
{"update":[
 {"_id":"room-own","t":"p","name":"mori.a-times","lm":"2026-07-22T05:00:00.000Z"},
 {"_id":"room-other","t":"p","name":"kawai.t-times","lm":"2026-07-22T06:00:00.000Z"},
 {"_id":"room-noise","t":"p","name":"grafana-alert","lm":"2026-07-22T07:00:00.000Z"},
 {"_id":"room-dm","t":"d","usernames":["mori.a","hatagami.y"],"lm":"2026-07-22T08:00:00.000Z"},
 {"_id":"room-stale","t":"c","name":"old-channel","lm":"2026-07-10T00:00:00.000Z"}
]}
EOF

run_rc() {
  RC_ENV_FILE="$TMP/env.local" \
  RC_CURL="$TMP/bin/curl-stub.sh" \
  RC_FIXTURE_DIR="$TMP/fixtures" \
  RC_ME=mori.a \
  bash "$SCRIPT_DIR/rocketchat.sh" "$@"
}

assert_grep() {
  local desc="$1" pattern="$2" text="$3"
  if grep -q -- "$pattern" <<<"$text"; then echo "ok: $desc"
  else echo "NG: $desc → '$pattern' が出力に無い"; fails=$((fails + 1)); fi
}
assert_absent() {
  local desc="$1" pattern="$2" text="$3"
  if grep -q -- "$pattern" <<<"$text"; then
    echo "NG: $desc → '$pattern' が出力に含まれている"; fails=$((fails + 1))
  else echo "ok: $desc"; fi
}

# ===== Task 1: ルーム列挙 =====
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --list-rooms)"
assert_grep   "期間内のルームが列挙される(own)"   "mori.a-times"  "$out"
assert_grep   "期間内のルームが列挙される(other)" "kawai.t-times" "$out"
assert_absent "期間外のルームは除外される"        "old-channel"   "$out"
assert_absent "DMは既定で除外される"              "room-dm"       "$out"

out="$(run_rc --from 2026-07-21 --to 2026-07-28 --list-rooms --include-dm)"
assert_grep "--include-dm でDMが含まれる" "room-dm" "$out"

if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "${fails} 件失敗"; exit 1; fi
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: FAIL（`rocketchat.sh` が存在しないため `No such file or directory`）

- [ ] **Step 3: 最小実装を書く**

`scripts/lib/rocketchat.sh` を新規作成する:

```bash
#!/bin/bash
# rocketchat.sh - Rocket Chat の購読ルームから自分に関係するメッセージを収集して整形出力する
#
# 日報 cron（fire-daily-review.sh）と work-report skill の共通データ取得層。
# ルーム列挙・期間絞り込み・関連メッセージ抽出という決定的な処理を担い、
# 作業内容の分類のような非決定的な判断は呼び出し側（Claude）に委ねる。
#
# 設計: docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md
#
# 使用方法:
#   rocketchat.sh --from 2026-07-21 --to 2026-07-28 [--include-dm] [--budget N]
#   rocketchat.sh --from ... --to ... --list-rooms      # 採用ルームの一覧だけ出す（デバッグ用）
#
# 環境変数:
#   RC_ENV_FILE  認証情報ファイル（既定: scripts/daily-review/.env.local）
#   RC_ME        自分のユーザー名（既定: mori.a）
#   RC_CURL      curl の代替コマンド（テスト用フック）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_ENV_FILE="$SCRIPT_DIR/../daily-review/.env.local"
readonly WINDOW_SEC=1800   # 起点の前後30分

env_file="${RC_ENV_FILE:-$DEFAULT_ENV_FILE}"
me="${RC_ME:-mori.a}"
curl_cmd="${RC_CURL:-curl}"

from="" to="" include_dm=0 budget=0 list_rooms=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from)       from="$2"; shift 2 ;;
    --to)         to="$2"; shift 2 ;;
    --include-dm) include_dm=1; shift ;;
    --budget)     budget="$2"; shift 2 ;;
    --list-rooms) list_rooms=1; shift ;;
    *) echo "不明な引数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$from" ] && [ -n "$to" ] || { echo "--from と --to は必須" >&2; exit 2; }

if [ ! -f "$env_file" ]; then
  echo "(Rocket Chat: $env_file が見つかりません)" >&2
  exit 0
fi
# shellcheck disable=SC1090
source "$env_file"

# JST の日付範囲を UTC ISO8601 に変換する
oldest="$(TZ=Asia/Tokyo date -d "$from 00:00" -u +%Y-%m-%dT%H:%M:%S.000Z)"
latest="$(TZ=Asia/Tokyo date -d "$to 00:00 +1 day" -u +%Y-%m-%dT%H:%M:%S.000Z)"

# rc_api <path> [query-string]
rc_api() {
  local path="$1" qs="${2:-}"
  "$curl_cmd" -s -m 25 \
    -H "X-Auth-Token: $RC_TOKEN" \
    -H "X-User-Id: $RC_USER_ID" \
    "$RC_BASE_URL/api/v1/${path}?${qs}"
}

# 期間内に活動があった購読ルームを "_id<TAB>t<TAB>name" 形式で列挙する。
# lm（last message）で絞る。_updatedAt はトピック変更等でも更新されるため使わない。
list_active_rooms() {
  rc_api "rooms.get" | python3 -c '
import sys, json, os
oldest = os.environ["RC_OLDEST"]
include_dm = os.environ["RC_INCLUDE_DM"] == "1"
try:
    rooms = json.load(sys.stdin).get("update", [])
except Exception:
    sys.exit(0)
for r in rooms:
    t = r.get("t")
    if t == "d" and not include_dm:
        continue
    if (r.get("lm") or "") < oldest:
        continue
    if t == "d":
        others = [u for u in (r.get("usernames") or []) if u != os.environ["RC_ME"]]
        name = "DM:" + (",".join(others) or "self")
    else:
        name = r.get("name") or r.get("fname") or "(no-name)"
    print("\t".join([r["_id"], t, name]))
'
}

export RC_OLDEST="$oldest" RC_INCLUDE_DM="$include_dm" RC_ME="$me"

if [ "$list_rooms" -eq 1 ]; then
  list_active_rooms
  exit 0
fi

# 履歴取得・絞り込みは Task 2 以降で実装する
list_active_rooms
```

`chmod +x scripts/lib/rocketchat.sh` を実行する。

- [ ] **Step 4: テストを実行して通過を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: PASS（`ok:` が5行出て `ALL OK`）

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh
rm -f .git/index.lock
git commit -m "feat: Rocket Chat 共通取得層のルーム列挙を追加

rooms.get で購読ルームを列挙し lm で期間フィルタする。
_updatedAt はトピック変更等でも更新されるため lm を使う。
テストは curl をスタブに差し替えて実APIを叩かない。"
```

---

### Task 2: ルーム採用判定（自分の発言 / @me）

**Files:**
- Modify: `scripts/lib/rocketchat.sh`
- Modify: `scripts/lib/rocketchat-test.sh`

**Interfaces:**
- Consumes: Task 1 の `rc_api` / `list_active_rooms` / 環境変数 `RC_ME`
- Produces:
  - 内部関数 `room_history <room_id> <t>`: 該当ルームの期間内メッセージ JSON 配列を stdout に出す
  - 採用判定つきの出力: `===== <room名> [発言N,@meN] =====` ヘッダ + `HH:MM user: msg` 行

**判定ルール（spec の第1段階）:** 以下のいずれかを満たすルームだけ採用する。

1. `username == $RC_ME` の発言が期間内に存在する
2. 本文に `@<RC_ME>` を含むメッセージが期間内に存在する

`@all` / `@here` は条件に含めない（実データで新人紹介・他人のQ&A といったノイズしか拾わなかったため）。

- [ ] **Step 1: 失敗するテストを書く**

`scripts/lib/rocketchat-test.sh` の fixture 定義（`rooms.json` の直後）に履歴 fixture を追加する:

```bash
# hist-own: 自分のtimes。自分の発言2件 + 他人の反応3件（うち2件は自分の最終発言から30分超）
cat > "$TMP/fixtures/hist-own.json" <<'EOF'
{"messages":[
 {"_id":"o1","ts":"2026-07-22T00:42:00.000Z","u":{"username":"mori.a"},"msg":"APIの利用上限に達しました"},
 {"_id":"o2","ts":"2026-07-22T00:45:00.000Z","u":{"username":"mori.a"},"msg":"ログです"},
 {"_id":"o3","ts":"2026-07-22T00:55:00.000Z","u":{"username":"matsumoto.h"},"msg":"自動支払いが止まってました"},
 {"_id":"o4","ts":"2026-07-22T01:47:00.000Z","u":{"username":"matsumoto.h"},"msg":"向こうの対応が変わったってことですかね"},
 {"_id":"o5","ts":"2026-07-22T01:56:00.000Z","u":{"username":"tanaka.k"},"msg":"はい、自分も同じ認識です"}
]}
EOF

# hist-other: 他人のtimes。スレッドを使わないフラット会話。
# 自分の発言1件(07:37)の前後30分に議論があり、遠く離れた雑談もある。
cat > "$TMP/fixtures/hist-other.json" <<'EOF'
{"messages":[
 {"_id":"t1","ts":"2026-07-22T00:35:00.000Z","u":{"username":"kawai.t"},"msg":"殺人的な暑さ過ぎる"},
 {"_id":"t2","ts":"2026-07-22T07:21:00.000Z","u":{"username":"kawai.t"},"msg":"MCP化したがこれでよかったか分からん"},
 {"_id":"t3","ts":"2026-07-22T07:34:00.000Z","u":{"username":"sato.m"},"msg":"モデルが賢くなったのでCLIでいい"},
 {"_id":"t4","ts":"2026-07-22T07:37:00.000Z","u":{"username":"mori.a"},"msg":"自分で作る分には全てskillでいいと思ってます"},
 {"_id":"t5","ts":"2026-07-22T07:40:00.000Z","u":{"username":"kawai.t"},"msg":"確かに認証の有無が一番大きい違いですね"},
 {"_id":"t6","ts":"2026-07-22T09:45:00.000Z","u":{"username":"kawai.t"},"msg":"欠伸が止まらん"}
]}
EOF

# hist-noise: 自動投稿のみ。自分の発言もメンションも無い。
cat > "$TMP/fixtures/hist-noise.json" <<'EOF'
{"messages":[
 {"_id":"n1","ts":"2026-07-22T07:00:00.000Z","u":{"username":"grafana"},"msg":"[FIRING] disk usage high"},
 {"_id":"n2","ts":"2026-07-22T07:01:00.000Z","u":{"username":"grafana"},"msg":"[RESOLVED] disk usage high"}
]}
EOF

# hist-dm: DM。自分の発言1件と相手の発言1件。
cat > "$TMP/fixtures/hist-dm.json" <<'EOF'
{"messages":[
 {"_id":"d1","ts":"2026-07-22T06:05:00.000Z","u":{"username":"hatagami.y"},"msg":"先日の件どうでしょうか"},
 {"_id":"d2","ts":"2026-07-22T06:06:00.000Z","u":{"username":"mori.a"},"msg":"今週中に対応します"}
]}
EOF
```

さらにテストの末尾（`if [ "$fails" -eq 0 ]` の直前）に検証を追加する:

```bash
# ===== Task 2: ルーム採用判定 =====
out="$(run_rc --from 2026-07-21 --to 2026-07-28)"
assert_grep   "自分の発言があるルームは採用"     "mori.a-times"   "$out"
assert_grep   "自分の発言があるルームは採用(他人times)" "kawai.t-times" "$out"
assert_absent "自動投稿のみのルームは除外"       "grafana-alert"  "$out"
assert_grep   "採用理由がヘッダに出る"           "発言"           "$out"
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: FAIL（`grafana-alert` が出力に含まれている、および `発言` ヘッダが無い）

- [ ] **Step 3: 最小実装を書く**

`scripts/lib/rocketchat.sh` の末尾にある以下の2行を削除する:

```bash
# 履歴取得・絞り込みは Task 2 以降で実装する
list_active_rooms
```

その位置に以下を追加する:

```bash
# room_history <room_id> <t> : 期間内のメッセージ JSON を返す
#
# 1回の実行で数十ルーム分を叩くため、1ルームの失敗で全体を落とさない。
# curl が失敗した場合は空の messages を返してそのルームだけスキップさせる
# （set -e 下でも止まらないよう || で受ける）。
room_history() {
  local rid="$1" t="$2" path out
  case "$t" in
    c) path="channels.history" ;;
    p) path="groups.history" ;;
    d) path="im.history" ;;
    *) echo '{"messages":[]}'; return ;;
  esac
  out="$(rc_api "$path" "roomId=${rid}&oldest=${oldest}&latest=${latest}&count=200" || true)"
  # JSON として妥当かを検証する（HTMLエラーページ等が返る場合に備える）
  if printf '%s' "$out" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
    printf '%s' "$out"
  else
    echo "(Rocket Chat: ルーム $rid の取得に失敗しスキップ)" >&2
    echo '{"messages":[]}'
  fi
}

# 1ルーム分を判定・整形する。採用されなければ何も出さない。
# stdin: 履歴 JSON / 引数: ルーム名, ルーム種別
render_room() {
  local name="$1" t="$2"
  RC_ROOM_NAME="$name" RC_ROOM_T="$t" python3 -c '
import sys, json, os
me = os.environ["RC_ME"]
name = os.environ["RC_ROOM_NAME"]
try:
    msgs = [m for m in json.load(sys.stdin).get("messages", []) if (m.get("msg") or "").strip()]
except Exception:
    sys.exit(0)
own = [m for m in msgs if m.get("u", {}).get("username") == me]
men = [m for m in msgs if "@" + me in (m.get("msg") or "")]
if not own and not men:
    sys.exit(0)          # 第1段階: 採用しない
why = []
if own: why.append(f"発言{len(own)}")
if men: why.append(f"@me{len(men)}")
# f-string 内にバックスラッシュを書くと環境によって SyntaxError になるため
# join は必ず変数に退避してから埋め込む
tag = ",".join(why)
print(f"===== {name} [{tag}] =====")
for m in sorted(msgs, key=lambda x: x.get("ts", "")):
    tstr = (m.get("ts") or "")[11:16]
    u = m.get("u", {}).get("username", "?")
    body = (m.get("msg") or "").replace("\n", " / ")
    print(f"  {tstr} {u}: {body}")
'
}

# メイン: 採用ルームを順に処理する
while IFS=$'\t' read -r rid t name; do
  [ -n "$rid" ] || continue
  room_history "$rid" "$t" | render_room "$name" "$t"
done < <(list_active_rooms)
```

- [ ] **Step 4: テストを実行して通過を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: PASS（`ALL OK`）

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh
rm -f .git/index.lock
git commit -m "feat: ルーム採用判定（自分の発言 / @me）を追加

@all/@here は条件に含めない。実データ検証で新人紹介・他人のQ&A
といったノイズしか拾わず、根拠にしていた週報依頼は @mori.a 付きでも
届いていたため。"
```

---

### Task 3: メッセージ絞り込み（時間窓＋自分のtimes全採用）

**Files:**
- Modify: `scripts/lib/rocketchat.sh`
- Modify: `scripts/lib/rocketchat-test.sh`

**Interfaces:**
- Consumes: Task 2 の `render_room` / `room_history`
- Produces: `render_room` が spec の第2段階に従って絞り込んだメッセージだけを出力する

**絞り込みルール（spec の第2段階）:**

| 対象 | 方式 |
|---|---|
| 自分の times（`$RC_CHANNEL`）と DM（`t == "d"`） | **全メッセージ採用** |
| その他のルーム | 起点（自分の発言・`@me`）＋そのスレッドの親と兄弟返信＋**起点の前後30分** |

自分の times を全採用にするのは、時間窓が起点からの対称距離で切るため「自分が話題を投げて相手が後から議論を続けた場合に尻尾が切れる」問題への対処。実データで OpenAI 残高切れインシデントの原因究明部分（自分の最終発言から62分後）が欠落した。

- [ ] **Step 1: 失敗するテストを書く**

`scripts/lib/rocketchat-test.sh` の末尾（`if [ "$fails" -eq 0 ]` の直前）に追加する:

```bash
# ===== Task 3: メッセージ絞り込み =====
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --include-dm)"

# (a) 自分のtimesは全採用 → 自分の最終発言(00:45)から62分後の議論も残る
assert_grep "自分のtimesは尻尾が切れない(01:47)" "向こうの対応が変わった" "$out"
assert_grep "自分のtimesは尻尾が切れない(01:56)" "同じ認識です"           "$out"

# (b) 他人のtimesは時間窓で文脈を拾う（自分の発言07:37の前後30分）
assert_grep "起点前の問いが残る(07:21)"   "MCP化したがこれでよかったか" "$out"
assert_grep "起点前の議論が残る(07:34)"   "モデルが賢くなったので"       "$out"
assert_grep "起点後の反応が残る(07:40)"   "認証の有無が一番大きい違い"   "$out"

# (b) 窓外の雑談は落ちる
assert_absent "窓外の雑談は落ちる(00:35)" "殺人的な暑さ" "$out"
assert_absent "窓外の雑談は落ちる(09:45)" "欠伸が止まらん" "$out"

# (a) DMは全採用 → 相手の発言も残る
assert_grep "DMは相手の発言も残る" "先日の件どうでしょうか" "$out"
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: FAIL（`殺人的な暑さ` と `欠伸が止まらん` が出力に含まれている。Task 2 の実装は全メッセージを出しているため）

- [ ] **Step 3: 最小実装を書く**

`scripts/lib/rocketchat.sh` の `render_room` 関数を以下に置き換える:

```bash
# 1ルーム分を判定・絞り込み・整形する。採用されなければ何も出さない。
# stdin: 履歴 JSON / 引数: ルーム名, ルーム種別
render_room() {
  local name="$1" t="$2"
  RC_ROOM_NAME="$name" RC_ROOM_T="$t" RC_WINDOW_SEC="$WINDOW_SEC" \
  RC_MY_TIMES="${RC_CHANNEL:-}" python3 -c '
import sys, json, os, datetime
me      = os.environ["RC_ME"]
name    = os.environ["RC_ROOM_NAME"]
rtype   = os.environ["RC_ROOM_T"]
window  = int(os.environ["RC_WINDOW_SEC"])
mytimes = os.environ.get("RC_MY_TIMES", "")

def ts(m):
    return datetime.datetime.fromisoformat((m.get("ts") or "").replace("Z", "+00:00"))

try:
    msgs = [m for m in json.load(sys.stdin).get("messages", []) if (m.get("msg") or "").strip()]
except Exception:
    sys.exit(0)

own = [m for m in msgs if m.get("u", {}).get("username") == me]
men = [m for m in msgs if "@" + me in (m.get("msg") or "")]
if not own and not men:
    sys.exit(0)                       # 第1段階: 採用しない

# 第2段階(a): 自分の times と DM は全メッセージ採用
if rtype == "d" or (mytimes and name == mytimes):
    sel = msgs
else:
    # 第2段階(b): 起点 + スレッド(親/兄弟) + 起点の前後 window 秒
    seeds = own + men
    tids  = {(m.get("tmid") or m.get("_id")) for m in seeds}
    keep  = {m["_id"] for m in msgs
             if m.get("_id") in tids or m.get("tmid") in tids}
    for s in seeds:
        st = ts(s)
        for m in msgs:
            if abs((ts(m) - st).total_seconds()) <= window:
                keep.add(m["_id"])
    sel = [m for m in msgs if m["_id"] in keep]

why = []
if own: why.append(f"発言{len(own)}")
if men: why.append(f"@me{len(men)}")
# f-string 内にバックスラッシュを書くと環境によって SyntaxError になるため
# join は必ず変数に退避してから埋め込む
tag = ",".join(why)
print(f"===== {name} [{tag}] {len(sel)}/{len(msgs)}件 =====")
for m in sorted(sel, key=lambda x: x.get("ts", "")):
    tstr = (m.get("ts") or "")[11:16]
    u = m.get("u", {}).get("username", "?")
    body = (m.get("msg") or "").replace("\n", " / ")
    print(f"  {tstr} {u}: {body}")
'
}
```

- [ ] **Step 4: テストを実行して通過を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: PASS（`ALL OK`）

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh
rm -f .git/index.lock
git commit -m "feat: メッセージ絞り込み（時間窓＋自分のtimes全採用）を追加

他人のtimesはスレッドを使わないフラット会話が多く、スレッド展開だけでは
文脈が落ちるため起点の前後30分を採用する。自分のtimesとDMは時間窓の
尻尾切れを避けるため全メッセージ採用にする。"
```

---

### Task 4: スレッド展開

**Files:**
- Modify: `scripts/lib/rocketchat.sh`
- Modify: `scripts/lib/rocketchat-test.sh`

**Interfaces:**
- Consumes: Task 3 の `rc_api` / `room_history` / `render_room`
- Produces:
  - 内部関数 `expand_threads <history_json>`: 履歴 JSON を受け取り、含まれるスレッドの全返信を `chat.getThreadMessages` で取得してマージした JSON を返す

**なぜ必要か（実測）:** `channels.history` / `groups.history` はスレッド返信を全件返さない。`e食なび` のスレッド `C2TgNffumtDKqiGaf`（9返信）で実測すると、history が返したのは3件のみで、残り6件は `chat.getThreadMessages` を呼ばないと取得できなかった。

欠落していた6件には以下が含まれていた:

| 時刻 | 発言 | 重要性 |
|---|---|---|
| 07-27 03:13 | m.shitagawa「ありがとうございます」 | effort低下対応の受領確認 |
| 07-27 03:16 | m.shitagawa（Notionリンク共有） | 依頼していた会議資料の受領 |
| 07-27 03:16 | mori.a「そちらです！非常に助かります」 | 完了の確認 |

これらが欠落すると「依頼したが未応答」と誤判定される。実際にこの設計の調査中、スレッド未展開のまま判断して誤った報告をした事例がある（spec の「スレッド展開」節）。

- [ ] **Step 1: 失敗するテストを書く**

`scripts/lib/rocketchat-test.sh` の curl スタブ（`case "$url" in` のブロック）に分岐を追加する。`*rooms.get*` の行の直後に挿入する:

```bash
  *chat.getThreadMessages*tmid=thr-1*) cat "$RC_FIXTURE_DIR/thread-1.json" ;;
```

fixture を追加する（`hist-dm.json` の定義の直後）:

```bash
# hist-thread: スレッドを持つルーム。history はスレッド返信を一部しか返さない。
cat > "$TMP/fixtures/hist-thread.json" <<'EOF'
{"messages":[
 {"_id":"thr-1","ts":"2026-07-22T00:30:00.000Z","u":{"username":"other.p"},"msg":"打ち合わせお願いします","tcount":3},
 {"_id":"th-a","ts":"2026-07-22T00:40:00.000Z","u":{"username":"mori.a"},"msg":"資料いただけますか","tmid":"thr-1"}
]}
EOF

# thread-1: 同スレッドの全返信。
# history に無い th-b / th-c と、対象期間外(7/10)の th-old を含む。
# chat.getThreadMessages は oldest/latest を無視して全返信を返すため、
# 期間外が落ちることを検証する必要がある。
cat > "$TMP/fixtures/thread-1.json" <<'EOF'
{"messages":[
 {"_id":"th-old","ts":"2026-07-10T00:00:00.000Z","u":{"username":"other.p"},"msg":"ずっと前の日程調整です","tmid":"thr-1"},
 {"_id":"th-a","ts":"2026-07-22T00:40:00.000Z","u":{"username":"mori.a"},"msg":"資料いただけますか","tmid":"thr-1"},
 {"_id":"th-b","ts":"2026-07-22T05:00:00.000Z","u":{"username":"other.p"},"msg":"これですかね（リンク）","tmid":"thr-1"},
 {"_id":"th-c","ts":"2026-07-22T05:05:00.000Z","u":{"username":"mori.a"},"msg":"そちらです！助かります","tmid":"thr-1"}
]}
EOF
```

`rooms.json` にスレッド持ちルームを追加する。`{"_id":"room-dm"...}` の行の直後（`room-stale` の前）に挿入する:

```bash
 {"_id":"room-thread","t":"c","name":"e食なび","lm":"2026-07-22T05:05:00.000Z"},
```

curl スタブの履歴分岐にも追加する（`*roomId=room-dm*` の行の直後）:

```bash
  *roomId=room-thread*) cat "$RC_FIXTURE_DIR/hist-thread.json" ;;
```

テストの末尾（`if [ "$fails" -eq 0 ]` の直前）に検証を追加する:

```bash
# ===== Task 4: スレッド展開 =====
out="$(run_rc --from 2026-07-21 --to 2026-07-28)"
assert_grep "history にあるスレッド返信は出る"   "資料いただけますか"     "$out"
assert_grep "history に無い返信も展開される(th-b)" "これですかね"         "$out"
assert_grep "history に無い返信も展開される(th-c)" "そちらです"           "$out"
assert_grep "スレッド親も出る"                   "打ち合わせお願いします" "$out"
# chat.getThreadMessages は期間指定を無視するため自前フィルタが必要
assert_absent "対象期間外のスレッド返信は落ちる" "ずっと前の日程調整" "$out"

# 日次実行でも期間外が混入しないこと（生きているスレッドの全履歴混入の回帰）
out_day="$(run_rc --from 2026-07-22 --to 2026-07-22)"
assert_absent "日次実行でも期間外は混入しない" "ずっと前の日程調整" "$out_day"
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: FAIL（`これですかね` と `そちらです` が出力に無い。history にしか無い2件だけが出ている）

- [ ] **Step 3: 最小実装を書く**

`scripts/lib/rocketchat.sh` の `room_history` 関数の直後に `expand_threads` を追加する:

```bash
# expand_threads : stdin の履歴 JSON に、含まれるスレッドの全返信をマージして返す
#
# history 系エンドポイントはスレッド返信を全件返さない（実測: 9返信中3件のみ）。
# tmid / tcount からスレッドIDを集め、chat.getThreadMessages で補完する。
expand_threads() {
  local hist tids tid extra merged
  hist="$(cat)"
  # スレッドID = 返信の tmid ∪ 親の _id（tcount を持つもの）
  tids="$(printf '%s' "$hist" | python3 -c '
import sys, json
try:
    ms = json.load(sys.stdin).get("messages", [])
except Exception:
    sys.exit(0)
ids = set()
for m in ms:
    if m.get("tmid"):
        ids.add(m["tmid"])
    if m.get("tcount"):
        ids.add(m["_id"])
for i in sorted(ids):
    print(i)
')"
  [ -n "$tids" ] || { printf '%s' "$hist"; return; }

  extra="[]"
  while IFS= read -r tid; do
    [ -n "$tid" ] || continue
    extra="$(printf '%s\n%s' "$extra" \
      "$(rc_api "chat.getThreadMessages" "tmid=${tid}&count=200")" \
      | python3 -c '
import sys, json
lines = sys.stdin.read().split("\n", 1)
try:
    acc = json.loads(lines[0])
except Exception:
    acc = []
try:
    new = json.loads(lines[1]).get("messages", [])
except Exception:
    new = []
print(json.dumps(acc + new, ensure_ascii=False))
')"
  done <<< "$tids"

  # _id で重複排除してマージし、対象期間外のメッセージを落とす
  #
  # chat.getThreadMessages は oldest/latest を無視して全返信を返す（実測: 期間指定
  # ありだと0件になり、なしだと9件全部返る）。API 側で絞れないため取得後に ts で
  # 自前フィルタする。これを省くと、生きているスレッドの全履歴が毎日の日報に
  # 混入し続ける（例: 7/22 の日程調整が 7/27 の日報に入る）。
  printf '%s\n%s' "$hist" "$extra" \
  | RC_OLDEST_F="$oldest" RC_LATEST_F="$latest" python3 -c '
import sys, json, os
oldest = os.environ["RC_OLDEST_F"]
latest = os.environ["RC_LATEST_F"]
raw = sys.stdin.read().split("\n", 1)
try:
    base = json.loads(raw[0]).get("messages", [])
except Exception:
    base = []
try:
    extra = json.loads(raw[1])
except Exception:
    extra = []
seen, out = set(), []
for m in base + extra:
    mid = m.get("_id")
    if not mid or mid in seen:
        continue
    ts = m.get("ts") or ""
    if ts < oldest or ts >= latest:   # 対象期間外は落とす
        continue
    seen.add(mid)
    out.append(m)
print(json.dumps({"messages": out}, ensure_ascii=False))
'
}
```

さらにメインループを変更し、`room_history` の出力を `expand_threads` に通す。以下の行:

```bash
  room_history "$rid" "$t" | render_room "$name" "$t"
```

を以下に置き換える:

```bash
  room_history "$rid" "$t" | expand_threads | render_room "$name" "$t"
```

- [ ] **Step 4: テストを実行して通過を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: PASS（`ALL OK`）

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh
rm -f .git/index.lock
git commit -m "feat: スレッド展開を追加

history 系エンドポイントはスレッド返信を全件返さない（実測: 9返信中3件）。
chat.getThreadMessages で補完しないと「依頼したが未応答」と誤判定する。
実際にこの設計の調査中、未展開のまま判断して誤報告した事例がある。"
```

---

### Task 5: 予算処理（ルーム単位ドロップ）

**Files:**
- Modify: `scripts/lib/rocketchat.sh`
- Modify: `scripts/lib/rocketchat-test.sh`

**Interfaces:**
- Consumes: Task 4 の `expand_threads` を通した `render_room`
- Produces: `--budget N` 指定時、出力を N 文字以内に収める。落としたルームは `（※ 容量制限のため N ルームを省略: room-a, room-b）` を末尾に出力する

**優先度（spec より）:** 1. 自分の発言があるルーム / 2. `@me` のみのルーム / 3. それ以外。予算超過時は優先度の低い方から落とす。**バイト位置での切り捨ては行わない。**

- [ ] **Step 1: 失敗するテストを書く**

`scripts/lib/rocketchat-test.sh` の末尾（`if [ "$fails" -eq 0 ]` の直前）に追加する:

```bash
# ===== Task 5: 予算処理 =====
# 全ルーム分では収まらない小さな予算を与える
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --include-dm --budget 400)"
len="${#out}"
if [ "$len" -le 600 ]; then   # 省略マーカー分の余裕を見て 600
  echo "ok: 予算内に収まる（${len}文字）"
else
  echo "NG: 予算超過（${len}文字）"; fails=$((fails + 1))
fi
assert_grep "省略マーカーが出る" "容量制限のため" "$out"
assert_grep "優先度の高いルームが残る" "mori.a-times" "$out"

# 予算未指定なら省略マーカーは出ない
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --include-dm)"
assert_absent "予算未指定なら省略マーカーなし" "容量制限のため" "$out"
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: FAIL（`--budget` が未実装のため出力が予算を超え、省略マーカーも出ない）

- [ ] **Step 3: 最小実装を書く**

`scripts/lib/rocketchat.sh` のメインループを置き換える。Task 4 適用後は以下の3行になっているはずなので、これを丸ごと差し替える:

```bash
while IFS=$'\t' read -r rid t name; do
  [ -n "$rid" ] || continue
  room_history "$rid" "$t" | expand_threads | render_room "$name" "$t"
done < <(list_active_rooms)
```

置き換え後（`expand_threads` を維持したまま予算処理を追加する）:

```bash
# メイン: 採用ルームをブロックごとに集め、予算に応じて落とす
# 各ブロックは "優先度<TAB>ルーム名<TAB>本文(base64)" の1行にして扱う
collect_blocks() {
  while IFS=$'\t' read -r rid t name; do
    [ -n "$rid" ] || continue
    local block prio
    # Task 4 で追加した expand_threads を必ず通す（外すとスレッド返信が欠落する）
    block="$(room_history "$rid" "$t" | expand_threads | render_room "$name" "$t")"
    [ -n "$block" ] || continue
    # 優先度: 発言ありなら1、@meのみなら2、それ以外3
    if grep -q '\[発言' <<<"$block"; then prio=1
    elif grep -q '\[@me' <<<"$block"; then prio=2
    else prio=3; fi
    printf '%s\t%s\t%s\n' "$prio" "$name" "$(printf '%s' "$block" | base64 -w0)"
  done < <(list_active_rooms)
}

blocks="$(collect_blocks)"
[ -n "$blocks" ] || { echo "(Rocket Chat: 対象期間の該当メッセージなし)"; exit 0; }

# 優先度昇順に採用し、予算を超えたら以降を落とす
dropped=()
out=""
while IFS=$'\t' read -r prio name b64; do
  [ -n "$b64" ] || continue
  block="$(printf '%s' "$b64" | base64 -d)"
  if [ "$budget" -gt 0 ]; then
    candidate="${out}${block}"$'\n\n'
    if [ "${#candidate}" -gt "$budget" ] && [ -n "$out" ]; then
      dropped+=("$name")
      continue
    fi
  fi
  out="${out}${block}"$'\n\n'
done < <(printf '%s\n' "$blocks" | sort -t$'\t' -k1,1n)

printf '%s' "$out"
if [ "${#dropped[@]}" -gt 0 ]; then
  printf '（※ 容量制限のため %d ルームを省略: %s）\n' \
    "${#dropped[@]}" "$(IFS=, ; echo "${dropped[*]}")"
fi
```

- [ ] **Step 4: テストを実行して通過を確認**

Run: `bash scripts/lib/rocketchat-test.sh`
Expected: PASS（`ALL OK`）

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/lib/rocketchat.sh scripts/lib/rocketchat-test.sh
rm -f .git/index.lock
git commit -m "feat: 予算処理をルーム単位ドロップで実装

バイト位置での切り捨てをやめ、優先度の低いルームから丸ごと落として
省略マーカーを出す。セッション要約側の既存パターンに合わせた。"
```

---

### Task 6: 実データでの回帰確認

**Files:**
- 変更なし（検証のみ。必要なら `scripts/lib/rocketchat.sh` を修正）

**Interfaces:**
- Consumes: Task 5 完成後の `rocketchat.sh`
- Produces: 実データで spec の検証項目を満たしていることの確認結果

このタスクは実 API を叩く。`scripts/daily-review/.env.local` の実認証情報を使う。**取得のみで投稿は行わない。**

- [ ] **Step 1: 期間指定で実行してサイズを実測・記録する**

**注意:** spec に記載の 13,633文字 / 日次最大4,303文字は**スレッド展開の実装前に計測した値**であり、Task 4 で history が返さない返信が追加されるため増加する。ここでは固定値を assert せず、実測して記録する（Step 5 で spec を更新する）。

Run:
```bash
cd /home/aya/.dotfiles
bash scripts/lib/rocketchat.sh --from 2026-07-21 --to 2026-07-28 --include-dm > /tmp/rc-week.txt
echo "文字数: $(python3 -c 'print(len(open("/tmp/rc-week.txt").read()))')"
echo "バイト数: $(wc -c < /tmp/rc-week.txt)"
echo "採用ルーム数: $(grep -c '^=====' /tmp/rc-week.txt)"
```

Expected: 採用ルームが 11件以上（スレッド展開で `e食なび` 等の内容が増える）。文字数・バイト数は記録して Step 5 で spec に反映する。

**バイト数を測る理由:** `fire-daily-review.sh` の予算判定は bash の `${#var}` で行われ、これは cron 環境（`LANG` 未設定）では**バイト数**を数える。日本語は1文字約3バイトなので、文字数ベースの見積もりでは実使用率を3倍過小評価する。

- [ ] **Step 2: spec の検証項目1〜3を確認**

Run:
```bash
echo "--- 1. 取り逃していた実例 ---"
grep -c "websol-dev-ai-hub" /tmp/rc-week.txt   # 週報提出依頼
grep -c "e食なび" /tmp/rc-week.txt              # 増田さんの打診
grep -c "hatagami" /tmp/rc-week.txt            # DMの未完の約束
echo "--- 2. 自動投稿チャンネルの除外（0であること） ---"
grep -c "grafana-alert" /tmp/rc-week.txt || true
grep -c "reviewboard" /tmp/rc-week.txt || true
echo "--- 3. @allのみのルームの除外（0であること） ---"
grep -c "新人紹介\|玉木さんがAIチーム" /tmp/rc-week.txt || true
```

Expected: 1〜3 は各1以上、2 と 3 は 0

- [ ] **Step 3: spec の検証項目4（文脈の欠落がないこと）を確認**

Run:
```bash
echo "--- kawai.t-times の文脈（3つとも出ること） ---"
grep -c "MCP化" /tmp/rc-week.txt
grep -c "skillでいい" /tmp/rc-week.txt
grep -c "認証の有無" /tmp/rc-week.txt
echo "--- mori.a-times の尻尾（2つとも出ること） ---"
grep -c "向こうの対応が変わった" /tmp/rc-week.txt
grep -c "同じ認識です" /tmp/rc-week.txt
echo "--- 雑談の除外（0であること） ---"
grep -c "殺人的な暑さ\|欠伸が止まらん" /tmp/rc-week.txt || true
```

Expected: 文脈5項目は各1以上、雑談は 0

- [ ] **Step 4: 日次実行のサイズを実測し、バイト数で予算内か確認**

Run:
```bash
cd /home/aya/.dotfiles
for d in 2026-07-21 2026-07-22 2026-07-23 2026-07-24 2026-07-27; do
  f=/tmp/rc-day-$d.txt
  bash scripts/lib/rocketchat.sh --from "$d" --to "$d" > "$f"
  printf '%s: %s文字 / %sバイト\n' "$d" \
    "$(python3 -c "print(len(open('$f').read()))")" "$(wc -c < "$f")"
done
```

Expected: **バイト数**が `MAX_RC_CHARS=15000` を下回ること（bash の `${#var}` はバイト数で判定するため、こちらが実際の制約）。1日でも超える場合は Step 5 で `MAX_RC_CHARS` の引き上げか `--budget` の調整を検討する。

- [ ] **Step 4.5: 期間外スレッド返信の混入がないことを確認**

`chat.getThreadMessages` は期間指定を無視するため、日次実行で古いスレッド返信が混入しないことを実データで確認する。`e食なび` のスレッド `C2TgNffumtDKqiGaf` は 7/22〜7/27 に跨る。

Run:
```bash
cd /home/aya/.dotfiles
echo "--- 7/27単日に7/22の日程調整が混入していないこと（0であること） ---"
grep -c "通院のため遅刻" /tmp/rc-day-2026-07-27.txt || true
echo "--- 7/27単日に7/27の資料受領が入っていること（1以上） ---"
grep -c "そちらです" /tmp/rc-day-2026-07-27.txt || true
```

Expected: 前者が 0、後者が 1以上

- [ ] **Step 5: spec の実測値を更新してコミット**

Step 2・3・4.5 の内容チェックが1つでも失敗したら `rocketchat.sh` を修正し、Step 1〜4.5 を再実行する。

内容チェックが全て通ったら、spec の「#### 実測値」表と「#### 実測: cron では予算問題は発生しない」表を Step 1・4 で得た**実測値（スレッド展開込み）**に書き換える。合わせて以下を明記する:

- 週次の文字数・バイト数
- 日次の最大文字数・最大バイト数
- `MAX_RC_CHARS=15000` に対するバイト数ベースの使用率
- スレッド展開の追加によって旧値（13,633文字 / 日次4,303文字）からどれだけ増えたか

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md scripts/lib/rocketchat.sh
rm -f .git/index.lock
git commit -m "docs: スレッド展開込みの実測値でspecの数値を更新

旧値はスレッド展開の実装前に計測したもの。history が返さない
スレッド返信が加わるため増加する。予算判定は bash の \${#var}
=バイト数で行われるため、バイト数も併記する。"
```

---

### Task 7: 日報 cron の切り替え

**Files:**
- Modify: `scripts/daily-review/fire-daily-review.sh:49-53`
- Delete: `scripts/daily-review/fetch-rocketchat.sh`

**Interfaces:**
- Consumes: Task 5 完成後の `rocketchat.sh`（`--budget` / `--from` / `--to`）
- Produces: cron から複数ルームの情報が収集される状態

**重要:** cron が毎晩 22:10 に走る。このタスクは `--dry-run` での差分確認を必ず先に行う。

- [ ] **Step 1: 変更前のペイロードを保存**

Run:
```bash
cd /home/aya/.dotfiles
bash scripts/daily-review/fire-daily-review.sh --dry-run > /tmp/payload-before.txt 2>/dev/null
wc -c /tmp/payload-before.txt
sed -n '/Rocket Chat/,/^【/p' /tmp/payload-before.txt | head -20
```

Expected: 変更前は `mori.a-times` のみの履歴が入っている

- [ ] **Step 2: 呼び出しを差し替える**

`scripts/daily-review/fire-daily-review.sh` の以下の部分（L48-53）:

```bash
# Rocket Chat 当日履歴（失敗してもプレースホルダで続行）
rocketchat_log="$(bash "$SCRIPT_DIR/fetch-rocketchat.sh" "$target_date" 2>/dev/null || echo "(Rocket Chat: 取得失敗)")"
if [ "${#rocketchat_log}" -gt "$MAX_RC_CHARS" ]; then
  rocketchat_log="${rocketchat_log:0:$MAX_RC_CHARS}
（※ Rocket Chat 履歴が長いため切り詰め）"
fi
```

を以下に置き換える:

```bash
# Rocket Chat 当日履歴（失敗してもプレースホルダで続行）
# 購読ルーム全体から自分の発言・メンションに関係するものを収集する。
# DM は外部送信のため含めない（設計: docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md）。
# 文字数制御は rocketchat.sh 側の --budget（ルーム単位ドロップ）に委ねるため、
# ここでのバイト位置切り詰めは行わない。
rocketchat_log="$(bash "$SCRIPT_DIR/../lib/rocketchat.sh" \
  --from "$target_date" --to "$target_date" \
  --budget "$MAX_RC_CHARS" 2>/dev/null || echo "(Rocket Chat: 取得失敗)")"
```

- [ ] **Step 3: 変更後のペイロードを取得して差分を確認**

Run:
```bash
cd /home/aya/.dotfiles
bash scripts/daily-review/fire-daily-review.sh --dry-run > /tmp/payload-after.txt 2>/dev/null
wc -c /tmp/payload-before.txt /tmp/payload-after.txt
echo "--- Rocket Chat セクションのルーム数 ---"
grep -c '^=====' /tmp/payload-after.txt
echo "--- 全体が上限内か（60000以下であること） ---"
test "$(wc -c < /tmp/payload-after.txt)" -le 60000 && echo "OK" || echo "NG: 上限超過"
echo "--- セッション要約が落ちていないか（省略マーカーが無いこと） ---"
grep -c "古い.*セッションを省略" /tmp/payload-after.txt || echo "0（省略なし）"
```

Expected: 全体が60,000文字以内、セッション要約の省略マーカーが出ていない

- [ ] **Step 4: `fetch-rocketchat.sh` を削除して再確認**

Run:
```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git rm scripts/daily-review/fetch-rocketchat.sh
bash scripts/daily-review/fire-daily-review.sh --dry-run > /tmp/payload-after2.txt 2>/dev/null
diff <(grep -c '^=====' /tmp/payload-after.txt) <(grep -c '^=====' /tmp/payload-after2.txt) && echo "OK: 削除の影響なし"
```

Expected: `OK: 削除の影響なし`（他に参照が無いことの確認）

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add scripts/daily-review/fire-daily-review.sh
rm -f .git/index.lock
git commit -m "feat: 日報cronを複数ルーム対応に切り替え

fetch-rocketchat.sh（1チャンネル固定）を共通層 rocketchat.sh に置き換える。
文字数制御はバイト位置切り詰めから rocketchat.sh の --budget による
ルーム単位ドロップに移す。DM は外部送信のため含めない。"
```

---

### Task 8: work-report skill の切り替え

**Files:**
- Modify: `.claude-global/skills/work-report/SKILL.md`

**Interfaces:**
- Consumes: Task 5 完成後の `rocketchat.sh`（`--include-dm`）
- Produces: work-report が MCP ツールではなく `rocketchat.sh` を使う手順

- [ ] **Step 1: 現在の Rocket Chat 記述を確認**

Run:
```bash
cd /home/aya/.dotfiles
grep -n -A10 "### Rocket Chat 取得" .claude-global/skills/work-report/SKILL.md
grep -n "Rocket Chat" .claude-global/skills/work-report/SKILL.md
```

Expected: 「### Rocket Chat 取得」節と、データソース表の行が見つかる

- [ ] **Step 2: 「### Rocket Chat 取得」節を置き換える**

`.claude-global/skills/work-report/SKILL.md` の以下の節:

```markdown
### Rocket Chat 取得

```bash
# room_id特定
# mcp__rocketchat__list_channels（filter: "mori.a-times"）を使う

# 対象期間の発言取得（oldest/latestで絞り込み、JST→UTC変換に注意）
# mcp__rocketchat__get_channel_history（room_id, oldest: "${start_date}T00:00:00.000Z", latest: "${end_date}T23:59:59.000Z"）
# username = mori.a の発言のみ抽出
# threadIdがあるメッセージは mcp__rocketchat__get_thread_messages でスレッド展開
```
```

を以下に置き換える:

```markdown
### Rocket Chat 取得

MCP ツールは使わない。共通シェル層 `scripts/lib/rocketchat.sh` を呼ぶ。
購読ルーム全体から自分の発言・`@mori.a` メンションに関係するものが収集される
（自分の times と DM は全メッセージ、他ルームは起点の前後30分＋スレッド）。

```bash
bash ~/.dotfiles/scripts/lib/rocketchat.sh \
  --from "$start_date" --to "$end_date" --include-dm
```

出力形式は `===== <ルーム名> [発言N,@meN] M/N件 =====` のヘッダごとに
`HH:MM username: 本文` が並ぶプレーンテキスト。

- `--include-dm` を付けるのは work-report（ローカル処理）のみ。日報 cron は
  外部エンドポイントへ送信するため DM を含めない
- `grafana-alert` のような自動投稿チャンネルは判定で自動的に落ちる
- スレッド展開・ルーム絞り込みはスクリプト側で完結するため、追加の MCP 呼び出しは不要
- 設計の詳細: `docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md`
```

- [ ] **Step 3: データソース表の記述を更新**

同ファイルのデータソース表にある以下の行:

```markdown
| Rocket Chat（`mori.a-times`） | `mcp__rocketchat__*` ツール | 自分の作業・レビュー作業を対象期間で取得 |
```

を以下に置き換える:

```markdown
| Rocket Chat（購読ルーム全体） | `scripts/lib/rocketchat.sh` | 自分の作業・レビュー作業・自分宛の依頼を対象期間で取得 |
```

- [ ] **Step 4: 実際に skill の手順どおり実行できることを確認**

Run:
```bash
cd /home/aya/.dotfiles
grep -n "mcp__rocketchat" .claude-global/skills/work-report/SKILL.md || echo "OK: MCP参照が残っていない"
bash ~/.dotfiles/scripts/lib/rocketchat.sh --from 2026-07-21 --to 2026-07-28 --include-dm | head -5
```

Expected: `OK: MCP参照が残っていない` と、実際の出力の先頭5行

- [ ] **Step 5: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add .claude-global/skills/work-report/SKILL.md
rm -f .git/index.lock
git commit -m "feat: work-report のRocket Chat取得を共通層に切り替え

MCPツール（mori.a-times固定）から scripts/lib/rocketchat.sh に変更。
購読ルーム全体が対象になり、自分宛の依頼も収集される。"
```

---

### Task 9: 動作確認とドキュメント整合

**Files:**
- Modify: `docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md`（スコープ外セクションの更新）

**Interfaces:**
- Consumes: Task 1〜8 の全成果
- Produces: cron を跨ぐ前の最終確認と、後追い対象の明示

- [ ] **Step 1: テストと dry-run を通す**

Run:
```bash
cd /home/aya/.dotfiles
bash scripts/lib/rocketchat-test.sh
bash scripts/lib/redact-test.sh
bash scripts/daily-review/fire-daily-review.sh --dry-run > /dev/null 2>&1 && echo "dry-run OK"
```

Expected: 両テストが `ALL OK`、dry-run が `dry-run OK`

- [ ] **Step 2: redaction が効いていることを確認**

**注意:** トークンの値をコマンドライン引数に展開しない（argv はプロセス一覧・シェル履歴・トランスクリプトに残る）。`grep -f` でファイル経由で渡す。

Run:
```bash
cd /home/aya/.dotfiles
bash scripts/daily-review/fire-daily-review.sh --dry-run > /tmp/payload-check.txt 2>/dev/null

echo "--- X-Auth-Token の生値が出ていないこと ---"
grep -c "X-Auth-Token: [^[]" /tmp/payload-check.txt || echo "0（露出なし）"

echo "--- RC_TOKEN / RC_USER_ID の生値が出ていないこと ---"
# パターンを一時ファイル経由で渡し、値を argv に載せない
grep -hE '^(RC_TOKEN|RC_USER_ID)=' scripts/daily-review/.env.local \
  | sed -E 's/^[^=]+=//' > /tmp/secrets.pat
grep -c -F -f /tmp/secrets.pat /tmp/payload-check.txt || echo "0（露出なし）"
shred -u /tmp/secrets.pat 2>/dev/null || rm -f /tmp/secrets.pat
rm -f /tmp/payload-check.txt
```

Expected: どちらも 0

- [ ] **Step 3: 他スキルへの影響を確認**

Run:
```bash
cd /home/aya/.dotfiles
grep -rn "fetch-rocketchat" . --include="*.sh" --include="*.md" 2>/dev/null | grep -v "^./docs/" || echo "OK: 参照なし"
grep -rln "mcp__rocketchat" .claude-global/skills/
```

Expected: `fetch-rocketchat` への参照が無い。`mcp__rocketchat` は `effort-estimate` / `quarterly-dev-report` / `rocketchat-search` / `daily-review` に残る（後追い対象）

- [ ] **Step 4: spec のスコープ外セクションを更新**

`docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md` の「スコープ外」セクションの以下の部分:

```markdown
以下は同じ「`mori.a-times` だけ」ロジックを保持しているが、今回は変更しない。共通層の完成後に後追いで寄せる。

- `effort-estimate`
- `quarterly-dev-report`
- `rocketchat-search`（リファレンス用途のため MCP ツールの記述を残す価値がある）
```

を以下に置き換える:

```markdown
以下は同じ「`mori.a-times` だけ」ロジックを保持しているが、今回は変更しない。共通層（`scripts/lib/rocketchat.sh`）が完成したため、後追いで寄せられる状態になっている。

- `effort-estimate` — `mcp__rocketchat__*` で `mori.a-times` のみ取得
- `quarterly-dev-report` — 同上（月単位ループ）
- `daily-review` の SKILL.md — 手順書側に MCP 経由の記述が残る（cron 経路は Task 7 で切り替え済み。対話で `/daily-review` を実行した場合のみ MCP を使う状態）
- `rocketchat-search` — MCP ツールのリファレンスとして記述を残す（用途が異なるため寄せない）
```

- [ ] **Step 5: コミットして push**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md
rm -f .git/index.lock
git commit -m "docs: 実装完了に伴い後追い対象を明確化"
rm -f .git/index.lock
git remote -v | grep -q "github-aya215" || git remote set-url origin git@github-aya215:aya-215/dotfiles.git
git push
```

Expected: push 成功

---

## 後追い候補（この計画のスコープ外）

- `daily-review` SKILL.md の対話経路を `rocketchat.sh` に寄せる（cron 経路は Task 7 で完了済みだが、手順書側は MCP のまま）
- `effort-estimate` / `quarterly-dev-report` を `rocketchat.sh` に寄せる
- 時間窓（30分）の調整。実データでは±30分で十分だったが、会話密度が変わった場合は再計測する
