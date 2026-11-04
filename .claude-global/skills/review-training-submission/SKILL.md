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
   - 出力は PASS・N/A 以外の行と、PASS・N/A の ID の1行だけ。全行が要るときは `--all`
   - マージ済みPRを見直すときは `--merge-commit <sha>` を足す
5. **内容チェック**: `references/criteria.md` の正本を読み、C1〜C8 を判定する。提出物は `git show refs/review/head:<path>` で読む。指摘の重さは criteria.md の「指摘の重さ」で決める
6. **取り直し**: 結論の直前に `get_issue`（本文）と `git ls-remote origin <head>`（head SHA が `refs/review/head` と同じか）を確認する。変わっていたら 2 からやり直す
7. **1段目を出して止まる**（下の出力形式。再レビューなら依頼した点ごとの「満たした / まだ」が1段目）

## 再レビュー（修正が push された後）

- 見るのは、**直近の依頼コメントで依頼した点が満たされたか**だけ。依頼した点ごとに「満たした / まだ」を1行で出す
- 新しい指摘は足さない（前回言わなかった点を後から言わない）。例外は形式チェックの FAIL と秘匿情報
- 依頼がすべて満たされていれば、推奨は「マージ可」にする

## 出力形式

判定（手順1〜6）は最初に全部済ませ、**表示だけを段階に分ける**。1回の返答では1段だけ出し、次に何を出せるかを示して止まる。

### 1段目（最初の返答）: Issue と PR をざっと伝える

これ以外は出さない。

1. **Issue の要件と PR の対応**: `| Issue の要件 | PR の対応 | 指摘 |`
   - Issue の内容要件1つにつき1行（C1）。Issue で太字の語は、要件の文の中で同じ語を太字にする（C2。例: 「写経で書いた Runnable 合成1本（**手書き**）」）。ラベルは付けない
   - 「PR の対応」は30字程度の1文。節名や細部は書かない
   - 「指摘」は `不要` / `依頼` / `任意` のどれか
2. **推奨（1行）**: マージ可 / 修正依頼後マージ / 差し戻し と、理由を一言
3. **形式（1行）**: 問題が無ければ「形式チェックは問題なし」。FAIL / WARN / UNKNOWN があれば ID と一言だけ（例: 「F01 WARN: Issue 2件を1本で閉じている」）
4. **次に出せるもの（1行）**: 中身があるものだけを件数付きで並べ、「どれを出しますか？」で止める
   - 例: 「次に出せるもの: 返す内容（依頼1・任意1）／カリキュラム側の候補2件／形式チェックの全行／内容チェック表（C1〜C8）」

### 2段目以降（頼まれたものを1つずつ）

- **返す内容**
  - 良かった点: 1〜2点（コメントの書き出しに使う）
  - 依頼: 「指摘の重さ」で `依頼` になったものだけ。0件なら「なし」
  - 任意: 最大2件。無ければ省く
  - 自己評価（C6）: 口頭で伝える材料が要るときだけ1行。PRコメントには入れない
  - 末尾: 「コメントにするなら /write-review-comment に渡します」
- **質問への回答案**（C7）: 質問があるときだけ。質問ごとに1〜2行
- **カリキュラム・運用側の候補**: `references/known-curriculum-issues.md` に載っていないものだけ。載っているものが直っていたら「解消済み・リストから削除」とだけ書く
- **形式チェックの全行**: スクリプトの出力をそのまま貼る。FAIL / WARN / UNKNOWN の行だけ下に1行ずつ補足する
- **内容チェック表**: `| ID | 観点 | 判定 | 根拠（節・行・一次情報） | 確度 |`。C1〜C3・C5・C6 は 達成 / 部分 / 未達、C4 は 正確 / 不正確 / 未裏取り、確度は CONFIRMED / PLAUSIBLE / REFUTED

例外: F03 が FAIL なら、1段目は「確認事項にチェックが無いのでレビューしない」と該当行の引用だけにする。

## 判定の注意

- **F03 が FAIL なら内容レビューに進まず止める**（`docs/pr-checklist.md`: 確認事項に全部チェックが無いPRはレビューしない）
- F03 が UNKNOWN（`* task: :` 表記）なら、PRの画面で確かめてもらう。PASS 扱いにしない
- 裏取りしていない推測を「未達」「不正確」にしない。「誤解しているかもしれない」は依頼の根拠にならない
- 受講者やメンターの `settings.json` など、トークンを含みうる設定ファイルは読まない。提出物に書かれた内容だけで判定する
- AskUserQuestion は使わない。本文末尾の質問で止める
