---
name: review-training-submission
description: Use when reviewing a pull request in the GitBucket repository AI_dev/tamaki-ai-training (新人研修の提出物PR、玉木さんのPR、needs-review の研修PR、「研修PRをレビュー」「提出物を確認して」「どの項目が達成されているか見て」「修正来たので確認して」). Covers both the agent track and the infra track. Not for product-code PRs.
---

# 研修提出物PRのレビュー

tamaki-ai-training の提出PRについて、**形式はスクリプトで、内容は一次情報で**判定し、「Issue が何を求め、PR が何を出し、何を返すか」を短く出す。
投稿はしない。コメント化は `/write-review-comment` に渡す（このリポジトリでのコメントの型は `references/criteria.md` の「コメントの型」）。

## 手順

1. **PRを特定する**: 引数の番号を使う。無ければ `mcp__gitbucket__gitbucket_list_prs`（open）で、1本ならそれ、複数なら本文末尾の質問で番号を聞いて止まる
2. **メタ情報を取る**（MCP）
   - `gitbucket_get_issue` を**PR番号で**呼ぶ → `labels` と最新の `body`。`get_pr` の body は古いことがあるので使わない
   - `gitbucket_get_pr` → `head` / `base`
   - 本文の `closes #N` の Issue を**すべて** `gitbucket_get_issue` → `labels` / `body`
   - `gitbucket_list_comments` をPR番号で呼ぶ → メンターのコメントに**依頼**があり、そのコメントより後に head へコミットが積まれていれば**再レビュー**（下の「再レビュー」）。「明日返します」「確認しました」のような依頼の無いコメントは数えない
3. **meta.json を Write ツールで scratchpad に書く**（形式は `scripts/check_submission.py` の docstring。Issue が複数なら `issue` を配列にする）。body は MCP の値を改変せずに入れる
4. **形式チェックを実行する**
   ```bash
   python3 ~/.claude/skills/review-training-submission/scripts/check_submission.py \
     --repo-dir <tamaki-ai-training の clone> --meta <meta.json>
   ```
   - clone に `refs/review/head` / `refs/review/base` を fetch する（作業ツリーは触らない）
   - 出力は PASS 以外の行と PASS の件数だけ。全行が要るときは `--all`
   - マージ済みPRを見直すときは `--merge-commit <sha>` を足す
5. **内容チェック**: `references/criteria.md` の正本を読み、C1〜C8 を判定する。提出物は `git show refs/review/head:<path>` で読む。指摘の重さは criteria.md の「指摘の重さ」で決める
6. **取り直し**: 結論の直前に `get_issue`（本文）と `git ls-remote origin <head>`（head SHA が `refs/review/head` と同じか）を確認する。変わっていたら 2 からやり直す
7. **結果を出して止まる**（下の出力形式）

## 再レビュー（修正が push された後）

- 見るのは、**直近の依頼コメントで依頼した点が満たされたか**だけ。依頼した点ごとに「満たした / まだ」を1行で出す
- 新しい指摘は足さない（前回言わなかった点を後から言わない）。例外は形式チェックの FAIL と秘匿情報
- 依頼がすべて満たされていれば、推奨は「マージ可」にする

## 出力形式

最初の表示は次の順に、短く出す。C1〜C8 の内容チェック表は**出さない**（判定は内部で行い、深掘りを頼まれたら出す）。空の節は見出しごと省く。

1. **結論（1行）**: 推奨（マージ可 / 修正依頼後マージ / 差し戻し）と、その理由を一言
2. **Issue の要件と PR の対応**: `| Issue の要件 | PR の対応 | 指摘 |`
   - Issue の内容要件1つにつき1行（C1）。太字の要件（C2）は要件の頭に「**太字**」と付ける
   - 「PR の対応」は、提出物のどこに何を書いたかを1文で
   - 「指摘」は `不要` / `依頼` / `任意` のどれか
3. **形式チェック**: スクリプトの出力をそのまま貼る。表に出た行（FAIL / WARN / UNKNOWN）だけ、下に1行ずつ補足する
4. **返す内容**
   - 良かった点: 1〜2点（コメントの書き出しに使う）
   - 依頼: 「指摘の重さ」で `依頼` になったものだけ。0件なら「なし」
   - 任意: 最大2件。無ければ省く
   - 自己評価（C6）: 口頭で伝える材料が要るときだけ1行。PRコメントには入れない
5. **質問への回答案**（C7）: 質問があるときだけ。質問ごとに1〜2行
6. **カリキュラム・運用側の新しい修正候補**: `references/known-curriculum-issues.md` に載っていないものだけ。載っているものが直っていたら「解消済み・リストから削除」とだけ書く
7. 末尾の質問で締める: 「どれを深掘りしますか？（C1〜C8 の内容チェック表も出せます）コメントにするなら /write-review-comment に渡します」

## 判定の注意

- **F03 が FAIL なら内容レビューに進まず止める**（`docs/pr-checklist.md`: 確認事項に全部チェックが無いPRはレビューしない）
- F03 が UNKNOWN（`* task: :` 表記）なら、PRの画面で確かめてもらう。PASS 扱いにしない
- 裏取りしていない推測を「未達」「不正確」にしない。「誤解しているかもしれない」は依頼の根拠にならない
- 受講者やメンターの `settings.json` など、トークンを含みうる設定ファイルは読まない。提出物に書かれた内容だけで判定する
- AskUserQuestion は使わない。本文末尾の質問で止める
