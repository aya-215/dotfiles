# セッション要約バックフィル 設計書

作成日: 2026-07-24
対象: `~/.dotfiles/scripts/claude-summarize/`

## 背景と問題

セッション要約システム（SessionEnd hook → `summarize.sh`）を全期間監査した結果、要約欠損の実態が判明した（詳細は監査レポート参照）。

| 問題 | 実測 | 確度 |
|---|---|---|
| ① 要約処理が一度も起動していない（never-started） | 387件（うち380件=98%が20KB以上の実作業） | CONFIRMED |
| ② 起動したが失敗して今も欠損 | 8件 | CONFIRMED |
| ③ 生成済みmdのフォーマット構造破損 | 68本 | CONFIRMED |

①が最大の穴。原因は「SessionEnd イベントが端末クローズ・クラッシュ等で発火せず要約処理が起動しなかった」疑い（**PLAUSIBLE**、未確定）。副次発見として `summarize-session.sh:23` の `reason=resume` 除外はデッドコード（SessionEnd reason に resume は存在しない、実測0件）。

## 目的

SessionEnd hook の発火有無に依存せず、取りこぼしたセッションを定期的に拾って要約する。これにより ①387件 ②失敗8件 の両方を回収し、日報生成が当日分を取りこぼさないようにする。

## スコープ

### やること
- `backfill.sh`（新規）: 現存jsonl のうち要約 md が未生成のものを検出し、既存 `summarize.sh` に投入する薄い層
- crontab に 21:00 実行を1行追加（日報生成 22:10 の前に当日分を拾い切る）

### やらないこと（後続タスクへ）
- ① の原因究明（SessionEnd 非発火メカニズムの切り分け、PLAUSIBLE→CONFIRMED化）
- ③ フェンス破損68本の後処理強化＋再生成

## 設計

### 責務分離（決定的 / 非決定的）
- **決定的（backfill.sh）**: 対象セッションの選定（未生成判定・サイズによる薄いセッション除外の入口）
- **非決定的（既存 summarize.sh）**: Haiku による要約生成。薄いセッションの最終判定・失敗ハンドリングも既存ガードに一任

二重管理を避けるため、backfill.sh は要約ロジックを持たず summarize.sh を呼ぶだけにする。

### コンポーネント: `backfill.sh`（新規）

処理:
1. 現存 jsonl（`~/.claude/projects/**/*.jsonl`、`*/subagents/*` 除外）を走査
2. 各 jsonl のファイル名から full session-id と sid8 を取得
3. `~/.nb/claude/sessions/**/*-<sid8>.md` が既に存在するものは除外（生成済み。dedup キーと同一）
4. 残り（未生成）を `summarize.sh <jsonl> <full-session-id>` に順次投入
5. 薄いセッション・失敗は summarize.sh 既存ガードに一任（ガードA、必須見出し検証）
6. ログを `~/.local/log/claude-summarize-backfill.log` に追記

特性:
- **冪等**: md がある sid はスキップ。毎回実行しても無害。失敗8件は「md無し」なので自動で再試行対象になる
- **多重起動ガード**: `flock` で二重実行防止（cron重複・長引き対策）
- **1本失敗しても継続**: summarize.sh が個別失敗を握るため、backfill は次へ進む
- **`--dry-run`**: 対象 sid リストだけ出力し summarize を呼ばない（検証用）

### データフロー
```
cron (0 21 * * *) → backfill.sh
  → 全jsonl走査（subagents除外）
  → md有無で未生成を抽出（sid8突合）
  → 各未生成 jsonl を summarize.sh に投入（stdin渡し済みなのでARG_MAX回避）
  → summarize.sh が sessions/YYYY-MM-DD/ に .md 生成
  → backfill ログに件数・成否を追記
22:10 → fire-daily-review.sh（既存・変更なし）が当日分の要約を収集して日報生成
```

### crontab（既存2本と同じ流儀・手動管理）
```
*/30 * * * * /home/aya/.dotfiles/scripts/nb-sync.sh                    # 既存
0 21 * * *   /home/aya/.dotfiles/scripts/claude-summarize/backfill.sh >> ~/.local/log/claude-summarize-backfill.log 2>&1  # 新規
10 22 * * *  /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh >> ...  # 既存
```
- 21:00 なら日報 22:10 まで 70分の猶予。初回387件一括（重い本で20〜30秒/本）でも収まる。2回目以降は差分のみで数分。
- crontab 自体は Nix 管理外（既存も手動）。スクリプト本体は dotfiles でバージョン管理される。WSL は systemd user bus 無効のため systemd timer は使えない（実機確認済み）。

### エラー処理・規約
- `set -euo pipefail`、ログは `~/.local/log/`、日本語ドキュメントコメント（既存 nb-sync.sh / fire-daily-review.sh 踏襲）
- shell-conventions 準拠（UPPER_SNAKE 環境変数 / lower_snake ローカル / 関数に local）

### テスト
- `--dry-run` で未生成 sid リストを出力 → 件数が実測387近辺か検証
- 数本だけ実際に生成させ md が `sessions/YYYY-MM-DD/` に出るか確認
- 2回目の dry-run で生成済みが除外され対象が減ることを確認（冪等性）

## 後続タスク
- ① SessionEnd 非発火の原因究明（PLAUSIBLE→CONFIRMED）
- ③ フェンス破損68本の後処理強化＋既存分の再生成
- 初回 387件の一括流し込み（cron 初回を待つか手動で一発流すか、実装後に判断）
