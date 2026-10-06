---
name: review-training-submission
description: Use when reviewing a pull request in the GitBucket repository AI_dev/tamaki-ai-training (新人研修の提出物PR、玉木さんのPR、needs-review の研修PR、「研修PRをレビュー」「提出物を確認して」「どの項目が達成されているか見て」). Covers both the agent track and the infra track. Not for product-code PRs.
---

# 研修提出物PRのレビュー

tamaki-ai-training の提出PRについて、**形式はスクリプトで、内容は一次情報で**判定し、項目ごとの達成状況を表で出す。
投稿はしない。コメント化は `/write-review-comment` に渡す。

## 手順

1. **PRを特定する**: 引数の番号を使う。無ければ `mcp__gitbucket__gitbucket_list_prs`（open）で、1本ならそれ、複数なら本文末尾の質問で番号を聞いて止まる
2. **メタ情報を取る**（MCP）
   - `gitbucket_get_issue` を**PR番号で**呼ぶ → `labels` と最新の `body`。`get_pr` の body は古いことがあるので使わない
   - `gitbucket_get_pr` → `head` / `base`
   - 本文の `closes #N` の Issue を `gitbucket_get_issue` → `labels` / `body`
3. **meta.json を Write ツールで scratchpad に書く**（形式は `scripts/check_submission.py` の docstring）。body は MCP の値を改変せずに入れる
4. **形式チェックを実行する**
   ```bash
   python3 ~/.claude/skills/review-training-submission/scripts/check_submission.py \
     --repo-dir <tamaki-ai-training の clone> --meta <meta.json>
   ```
   - clone に `refs/review/head` / `refs/review/base` を fetch する（作業ツリーは触らない）
   - マージ済みPRを見直すときは `--merge-commit <sha>` を足す
5. **内容チェック**: `references/criteria.md` の正本を読み、C1〜C8 を判定する。提出物は `git show refs/review/head:<path>` で読む
6. **取り直し**: 結論の直前に `get_issue`（本文）と `git ls-remote origin <head>`（head SHA が `refs/review/head` と同じか）を確認する。変わっていたら 2 からやり直す
7. **結果を出して止まる**（下の出力形式）

## 出力形式

表が論点の一覧になる。全項目の説明を一度に書かず、表と総合を出したら、深掘りは1件ずつ行う。

1. **形式チェック表**: スクリプトの出力をそのまま貼る。FAIL / WARN / UNKNOWN の行だけ、下に1行ずつ補足する
2. **内容チェック表**: `| ID | 観点 | 判定 | 根拠（節・行・一次情報） | 確度 |`
   - 判定: C1〜C3・C5・C6 は 達成 / 部分 / 未達。C4 は 正確 / 不正確 / 未裏取り
   - 確度: CONFIRMED / PLAUSIBLE / REFUTED
   - C1 は Issue の内容要件1つにつき1行
3. **質問への回答案**（C7）: 質問ごとに1〜2行
4. **カリキュラム・運用側の修正候補**: C4・C7 で見つかったカリキュラムや配布物の古さ・誤り。受講者への指摘とは分ける
5. **総合**: 推奨（マージ可 / 修正依頼後マージ / 差し戻し）を1行と、返すべき指摘を重要度順に最大5件
6. 末尾の質問で締める: 「どの項目を深掘りしますか？コメントにするなら /write-review-comment に渡します」

## 判定の注意

- **F03 が FAIL なら内容レビューに進まず止める**（`docs/pr-checklist.md`: 確認事項に全部チェックが無いPRはレビューしない）
- F03 が UNKNOWN（`* task: :` 表記）なら、PRの画面で確かめてもらう。PASS 扱いにしない
- 裏取りしていない推測を「未達」「不正確」にしない
- 受講者やメンターの `settings.json` など、トークンを含みうる設定ファイルは読まない。提出物に書かれた内容だけで判定する
- AskUserQuestion は使わない。本文末尾の質問で止める
