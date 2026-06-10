# 挨拶cron → Claudeルーティン移行計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 7時・12時の挨拶（5時間ウィンドウのアンカー）をローカルcron＋Windowsタスクスケジューラから、Claudeのクラウドルーティンに置き換える。

**Architecture:** `RemoteTrigger` ツール（`/schedule` スキル経由のAPI）でクラウドルーティンを2本作成し、即時実行（Run now）で動作検証してから、ローカル側の仕掛け（crontab 2行・Windowsタスク2つ・リポジトリ内スクリプト2ファイル）を撤去する。ルーティンはAnthropicクラウドで実行されるため、PCのスリープ解除（WakeToRun）が不要になる。

**Tech Stack:** Claude Code `/schedule` スキル + `RemoteTrigger` ツール、crontab、schtasks.exe（WSLから実行）、git

---

## 背景（実行者向けコンテキスト）

- 現状: WSLのcrontabとWindowsタスクスケジューラの**両方**から `scripts/claude-prompt.sh` が7:00/12:00 JSTに起動され、`claude -p "おはよう"` 等を実行している。
- 目的は挨拶ではなく、**サブスクの5時間使用ウィンドウを定時に開始（アンカー）させること**。公式ドキュメントに「Routines draw down subscription usage the same way interactive sessions do」とあり、ルーティン実行でも同じ効果が見込める。
- ルーティンのスケジュールは**UTC指定**。7:00 JST = `0 22 * * *`（前日22時UTC）、12:00 JST = `0 3 * * *`。
- environment_id: `env_01X9JcJWqdgPvER4JA37Gt1U`（Default / anthropic_cloud。今セッションで自動作成済み）
- リポジトリのcloneは不要（挨拶だけなので `sources` は付けない）。
- 注意: ルーティンには実行開始時刻に数分のstagger（ズレ）がある。ウィンドウのアンカーが7:00→7:03等になりうるが許容する。
- 注意: ルーティンの削除はAPIからはできない。失敗時のやり直しは https://claude.ai/code/routines で削除してから再作成する。

---

### Task 1: 朝7時のルーティン作成

**Files:** なし（クラウド側の操作のみ）

- [ ] **Step 1: RemoteTriggerツールをロード**

`ToolSearch` で `select:RemoteTrigger` を実行してスキーマをロードする（未ロードの場合）。

- [ ] **Step 2: UUIDを生成**

```bash
uuidgen | tr 'A-Z' 'a-z'
```

Expected: 小文字のv4 UUIDが1つ出力される。次のステップの `events[0].data.uuid` に使う。

- [ ] **Step 3: ルーティン作成**

`RemoteTrigger` を `action: "create"` で呼ぶ。body（`<UUID>` はStep 2の値に置換）:

```json
{
  "name": "greeting-morning",
  "cron_expression": "0 22 * * *",
  "enabled": true,
  "job_config": {
    "ccr": {
      "environment_id": "env_01X9JcJWqdgPvER4JA37Gt1U",
      "session_context": {
        "model": "claude-sonnet-4-6",
        "allowed_tools": []
      },
      "events": [
        {"data": {
          "uuid": "<UUID>",
          "session_id": "",
          "type": "user",
          "parent_tool_use_id": null,
          "message": {"content": "おはよう。これは5時間使用ウィンドウを開始するための定時ウォームアップ実行です。ツールは一切使わず、一言だけ挨拶を返して終了してください。", "role": "user"}
        }}
      ]
    }
  }
}
```

Expected: HTTP 200。レスポンスにルーティンID（`trig_...`）とclaude.aiのURLが含まれる。IDを控える。

※ `allowed_tools: []` が validation エラーになる場合は、`allowed_tools` フィールド自体を削除して再実行する。

- [ ] **Step 4: サーバ側のパース結果を確認**

レスポンス末尾のサマリー行（server-parsed run time）が「22:00 UTC = 翌7:00 JST」相当であることを確認する。違っていたら `action: "update"` でcron式を修正する。

### Task 2: 昼12時のルーティン作成

**Files:** なし（クラウド側の操作のみ）

- [ ] **Step 1: UUIDを生成**

```bash
uuidgen | tr 'A-Z' 'a-z'
```

Expected: 小文字のv4 UUIDが1つ出力される（Task 1とは別の値）。

- [ ] **Step 2: ルーティン作成**

`RemoteTrigger` を `action: "create"` で呼ぶ。body（Task 1との差分は `name`・`cron_expression`・`uuid`・`message.content` のみ）:

```json
{
  "name": "greeting-noon",
  "cron_expression": "0 3 * * *",
  "enabled": true,
  "job_config": {
    "ccr": {
      "environment_id": "env_01X9JcJWqdgPvER4JA37Gt1U",
      "session_context": {
        "model": "claude-sonnet-4-6",
        "allowed_tools": []
      },
      "events": [
        {"data": {
          "uuid": "<UUID>",
          "session_id": "",
          "type": "user",
          "parent_tool_use_id": null,
          "message": {"content": "こんにちは。これは5時間使用ウィンドウを開始するための定時ウォームアップ実行です。ツールは一切使わず、一言だけ挨拶を返して終了してください。", "role": "user"}
        }}
      ]
    }
  }
}
```

Expected: HTTP 200。「03:00 UTC = 12:00 JST」相当のサマリーを確認。

- [ ] **Step 3: 一覧で2本登録されたことを確認**

`RemoteTrigger` を `action: "list"` で呼ぶ。

Expected: `greeting-morning`（`0 22 * * *`）と `greeting-noon`（`0 3 * * *`）が両方 `enabled: true` で並ぶ。

### Task 3: Run nowで動作検証

**Files:** なし（クラウド側の操作のみ）

- [ ] **Step 1: greeting-morningを即時実行**

`RemoteTrigger` を `action: "run"`、`trigger_id` にTask 1で控えたIDを指定して呼ぶ。

Expected: HTTP 200。セッションID/URLが返る。

- [ ] **Step 2: 実行結果を確認**

返ってきたセッションURL（`https://claude.ai/code/...`）をユーザーに提示し、セッションが起動して挨拶が返っていることを確認する。緑ステータス＝起動成功なだけなので、**トランスクリプトで実際に挨拶して終了していること**まで見る。

Expected: 短い挨拶応答のみで終了している（ツール実行なし）。

- [ ] **Step 3: 使用量ウィンドウへの反映を確認**

ローカルのClaude Codeで `/usage` を確認するか、 https://claude.ai/settings/usage を開く。

注意: この時点で既に対話セッションのウィンドウが開いている場合、Run nowは既存ウィンドウ内の消費になるため「新規アンカー」の確認はできない。その場合この検証は**ウィンドウが閉じた状態で発火する翌朝のTask 7に委ねる**（Task 4〜6には進んでよい。ロールバック手段が揃っているため）。

Expected: 使用量にルーティン実行分が反映されている（＝サブスク使用量を消費している＝アンカー効果の傍証）。

### Task 4: WSL crontabから挨拶2行を削除

**Files:** crontab（ファイル外）

- [ ] **Step 1: 現状をバックアップ**

```bash
crontab -l > /tmp/crontab-backup-$(date +%Y%m%d).txt && cat /tmp/crontab-backup-$(date +%Y%m%d).txt
```

Expected: 4行（nb-sync, おはよう, こんにちは, daily-review）が表示・保存される。

- [ ] **Step 2: claude-prompt.shの2行だけを除去して再登録**

```bash
crontab -l | grep -v 'claude-prompt.sh' | crontab -
```

- [ ] **Step 3: 結果確認**

```bash
crontab -l
```

Expected: 残るのは以下の2行のみ。

```
*/30 * * * * /home/aya/.dotfiles/scripts/nb-sync.sh
0 22 * * * /home/aya/.dotfiles/scripts/daily-review/daily-review-auto.sh >> /tmp/daily-review-auto-cron.log 2>&1
```

### Task 5: Windowsタスクスケジューラのタスク削除

**Files:** なし（Windows側の操作のみ）

- [ ] **Step 1: 2つのタスクを削除**

```bash
schtasks.exe /delete /tn "ClaudeGreeting-Morning" /f
schtasks.exe /delete /tn "ClaudeGreeting-Noon" /f
```

Expected: それぞれ「成功」メッセージ（文字化けする場合があるが SUCCESS/成功 を確認）。
アクセス拒否になった場合: ユーザーに「Windows側で管理者PowerShellを開いて同コマンドを実行してほしい」と依頼する（`! ` プレフィックスでは権限昇格できないため）。

- [ ] **Step 2: 削除を確認**

```bash
schtasks.exe /query /tn "ClaudeGreeting-Morning" 2>&1; schtasks.exe /query /tn "ClaudeGreeting-Noon" 2>&1
```

Expected: 両方とも「指定されたファイルが見つかりません」相当のエラー（＝削除済み）。

- [ ] **Step 3（任意・ユーザー判断）: スリープ解除タイマーを元に戻す**

Register-ClaudeGreeting.ps1 が有効化したRTCWAKEは、もう挨拶用には不要。ただし他の用途（PCを定時に起こす運用）があるかもしれないので、**勝手に戻さずユーザーに確認**する。戻す場合はWindows側で:

```powershell
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 0
powercfg /setactive SCHEME_CURRENT
```

### Task 6: リポジトリのスクリプト削除とコミット

**Files:**
- Delete: `scripts/claude-prompt.sh`
- Delete: `scripts/claude-reset/Register-ClaudeGreeting.ps1`（ディレクトリごと）

事前確認済み: 両ファイルへの参照は過去のplan/docs内の記述のみで、実行時依存はない。git履歴に残るためロールバック可能。

- [ ] **Step 1: ファイル削除**

```bash
git -C /home/aya/.dotfiles rm scripts/claude-prompt.sh
git -C /home/aya/.dotfiles rm -r scripts/claude-reset/
```

Expected: 2ファイルがインデックスから削除される。

- [ ] **Step 2: 計画書を含めてコミット**

このリポジトリは作業途中の変更（modified多数）があるため、**今回の削除と計画書だけをステージ**してコミットする:

```bash
git -C /home/aya/.dotfiles add docs/superpowers/plans/2026-06-10-greeting-routine-migration.md
git -C /home/aya/.dotfiles commit -m "refactor: 挨拶cron/タスクスケジューラをClaudeクラウドルーティンに移行"
```

Expected: 削除2ファイル＋計画書1ファイルのコミットが作成される。

- [ ] **Step 3: push**

```bash
git -C /home/aya/.dotfiles push
```

Expected: 成功。失敗時はCLAUDE.mdの手順どおり `git remote set-url origin git@github-aya215:aya-215/dotfiles.git` を実行して再push。

### Task 7: 翌朝の自動実行確認（翌日の手動確認）

**Files:** なし

- [ ] **Step 1: 翌朝7時すぎに発火を確認**

翌日7:00 JST以降に https://claude.ai/code/routines で `greeting-morning` の実行履歴（Runs）に新しい実行が記録されていることを確認する。`/schedule list` でも next run / 履歴を確認できる。

Expected: 7:00 JST（＋数分のstagger）に実行されている。

- [ ] **Step 2: ウィンドウのアンカーを確認**

`/usage` でリセット時刻が「12:00 JST前後」を指していることを確認する。

Expected: 7時台に開始した5時間ウィンドウが見える。

- [ ] **Step 3: 問題があった場合のロールバック**

ルーティンが発火しない・ウィンドウに効かない場合:

```bash
# crontabを復元
crontab /tmp/crontab-backup-<日付>.txt
# スクリプトを復元
git -C /home/aya/.dotfiles revert <Task6のコミットhash>
git -C /home/aya/.dotfiles push
```

Windowsタスクは復元したPS1（`scripts/claude-reset/Register-ClaudeGreeting.ps1`）を管理者PowerShellで再実行して再登録する。

---

## 補足メモ

- **モデル**: `claude-sonnet-4-6` をデフォルト採用。1日2回・1往復のみなので使用量への影響は微小。さらに削りたければ作成後に `/schedule update` でhaikuを試せる。
- **デイリー実行回数上限**: ルーティンにはアカウント単位の「1日あたり実行開始回数」の上限がある（research preview中）。本移行は2回/日。将来 daily-review 等もルーティン化する場合は枠に注意。
- **22時のdaily-review・30分毎のnb-syncはローカルに残す**（ローカルファイルに依存するためルーティン化の対象外）。
