# Claude会話 セッション要約システム 設計

作成日: 2026-06-09

## 背景と目的

現在、Claude Code の会話履歴は `claude-nb-sync.py` が5分ごとに JSONL を差分監視し、
User/Claude の生テキスト（`type: text` のみ）を `~/.nb/claude/YYYY-MM-DD.md` に追記している。
日報サマリー生成（daily-review）はこの生ログを `grep`/`sed` で断片的に拾っていた。

### 現方式の問題点

1. **1日が巨大化** — 1日で580KB・複数MBになり `cat` 不可、断片 grep に頼る
2. **ツール操作が欠落** — `type: text` のみ抽出のため、編集ファイル・実行コマンドが追えない
3. **結論の取りこぼし** — `✅`/`完了` を grep で探す運次第の精度
4. **要約が後付け** — 生ログを溜めてから dailyreview 時に一括要約、新鮮なコンテキストを活かせない

### 最優先目標

**正確な日報サマリーを作ること。** 副次的に作業内容の記録・ナレッジ蓄積。

### 実行基盤とモデル選択の前提

- すべて `claude -p`（Claude Code CLI）で動かす。**API 従量課金は発生せず、サブスクのレート制限枠で完結する。**
- サブスク枠は余裕がある状況のため、コスト最小化は目的ではない。ただし要約は難易度の低いタスクで Haiku で十分な質が出るため、**過剰な Sonnet/Opus は使わず Haiku 固定**とする（タスクに見合う最小モデル。余った枠はレビューや調査など価値の高い作業に回す）。

## アーキテクチャ（案A+B）

セッション終了時に Haiku で都度要約を蓄積（A）し、夜の daily-review でそれを束ねる（B）。

```
[セッション終了]
   ↓ SessionEnd hook（reason フィルタ・subagent 除外）
   summarize-session.sh が バックグラウンドで要約プロセスを起動（即 exit）
   ↓
   ① 前処理: transcript JSONL から text + ツールメタ（ツール名・編集ファイルパス・
      Bash コマンド）を抽出。巨大な tool_result 本体（diff・コマンド出力）は捨てる
   ↓
   ② claude -p --model haiku が前処理済みテキストを6項目で構造化要約
   ↓
   ~/.nb/claude/sessions/YYYY-MM-DD/<session_id>.md に保存

[夜22時 cron] daily-review-auto.sh
   ↓
   その日の sessions/YYYY-MM-DD/*.md を束ねて読む（合計 ~12KB）
   ↓
   Work/Personal 分類 → 📝 サマリー生成 → 日報 Issue 更新
```

### 前処理の根拠（実測）

生 JSONL は最大 1.5MB（推定 40〜50万トークン）に達し、Haiku の 200K コンテキストを超えうる。
内訳を実測すると、巨大さの主因は `tool_result`（コマンド出力・diff 本体、最大セッションで約16万文字）で、
要約に必要な会話 text は最大でも約2万トークン。前処理で text + ツールメタだけ残せば：

- **Haiku 200K に確実に収まる**（巨大セッションへの安全弁）
- **ノイズ除去で要約の質が上がる**（diff 全文は「何をしたか」の要約に不要）
- 6項目の「編集/作成ファイル」「実行したコマンド」は `tool_use` の name/input から拾えるため、
  text だけに削っても作業内容を取りこぼさない

## コンポーネント（責務分離）

| ファイル | 責務 | 依存 |
|---|---|---|
| `~/.claude/hooks/summarize-session.sh` | SessionEnd 入力(JSON)を受け、reason/subagent を判定し、要約をバックグラウンド起動して即 exit 0 | claude CLI |
| `scripts/claude-summarize/extract.py` | JSONL 1本から text + ツールメタを抽出（tool_result 本体は除外）してプレーンテキスト化 | python3 |
| `scripts/claude-summarize/summarize.sh` | extract.py で前処理 → Haiku に渡し6項目要約を生成、`sessions/` に保存 | claude CLI(haiku), extract.py |
| `scripts/daily-review/daily-review-auto.sh`（既存改修） | 生ログ参照をやめ `sessions/` の要約を集約 | summarize.sh の出力 |

### hook の登録（Nix ソース）

SessionEnd hook は既に `.claude-global/settings.json` で稼働中（tmux-agent-sidebar）。
そこに `summarize-session.sh` を1コマンド追加する。settings.json は Home Manager 生成物のため、
Nix ソース側を編集する。

## セッション要約フォーマット（6項目）

Haiku が各セッション JSONL から生成する Markdown:

```markdown
---
project: ebase-portal-chat
session_id: abc123
start: 2026-06-09T15:07
end: 2026-06-09T16:30
cwd: /home/aya/src/github.com/ebase-dev/ebase-portal-chat
---

## 意図
（このセッションで何をしようとしたか）

## 作業内容
- （実際に行った調査・実装のステップ）

## 結論
（何が分かった・何ができたか）

## 編集/作成ファイル
- （変更したファイルパス。なければ「調査のみ」）

## 実行した主なコマンド
- （特徴的なコマンド）

## ナレッジ候補
- （memory に残す価値のある発見。なければ省略）
```

## 主要な設計判断

1. **SessionEnd hook を使う（Stop ではない）**
   - Stop は毎ターン発火 → 多重要約・状態管理が必要
   - SessionEnd は終了時1回 → 重複制御が原理的に不要
   - `transcript_path` が直接渡る（JSONL 絶対パス、最終ターンまで記録済み）
2. **Haiku 固定** — 要約は難易度の低いタスクで Haiku で質が足りる。サブスク枠で動くため
   API 課金はなく、枠も余裕があるが、過剰な Sonnet/Opus を使う理由がない（タスクに見合う最小モデル）
3. **前処理で text + ツールメタのみ抽出** — Haiku 200K 上限超えへの安全弁＋ノイズ除去（上記「前処理の根拠」参照）
4. **subagent 除外** — `~/.claude/projects/*/subagents/` 配下は対象外。
   情報はメインセッションに集約済みで、個別要約は二重記録になる（全体の約44%を削減）
5. **バックグラウンド非同期** — `&` でデタッチし hook は即 `exit 0`。セッション終了を待たせない
6. **生ログ方式（claude-nb-sync.py）は完全廃止** — 検索は元 JSONL（`~/.claude/projects/`）で代替

## reason フィルタ

SessionEnd の `reason` で要約要否を判定:

| reason | 要約するか |
|---|---|
| `prompt_input_exit` / `logout` / `clear` | する（セッション完了とみなす） |
| `resume` | しない（続きをやるだけ） |
| `bypass_permissions_disabled` / `other` | する（取りこぼし防止に倒す） |

`resume` で再開したセッションが後で改めて終了した場合、同じ `session_id` で再要約される。
出力ファイルは `<session_id>.md` 固定とし、**上書き（最新優先）** とする。

## エラーハンドリング

- 要約対象外の reason ならスキップして `exit 0`
- subagent セッション（パスで判定）ならスキップ
- Haiku 呼び出しが失敗しても hook は必ず `exit 0`（セッション操作を絶対に妨げない）
- バックグラウンドプロセスのログ・エラーは `~/.local/log/claude-summarize.log` にリダイレクト
- daily-review は「その日の要約が一部欠損」を許容し、存在するものだけ集約する

## 廃止対象（段階移行なし・一括切替）

1. crontab の `*/5 * * * * .../claude-nb-sync.py` 行
2. `scripts/claude-sync/`（claude-nb-sync.py, install.sh, README.md）
3. `~/.claude/nb-sync-state.json`（状態ファイル）
4. daily-review-auto.sh / SKILL.md 内の生ログ参照ロジック → `sessions/` 参照へ書き換え

## 動作確認方針

- summarize.sh を既存の JSONL 1本に対して手動実行し、6項目要約が出るか確認
- SessionEnd hook を実際にセッション終了で発火させ、`sessions/` にファイルが生成されるか確認
- daily-review-auto.sh が `sessions/` を集約して正しいサマリーを作るか確認
