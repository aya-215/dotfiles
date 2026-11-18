# work-report 共通組み立てルール Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** work-report の月・水・金の出力を「案件 → 流れ → 行」の共通ルールで組み立て、月曜に「現在対応中」「今後の予定」を足す。

**Architecture:** 変更は `.claude-global/skills/work-report/SKILL.md` 1ファイル。分類ロジックの「サブプロジェクト名」「統合ルール」を共通の「組み立てルール」節に置き換え、モード差分は表1つで持つ。対応中の収集は既存スキルと同じく手順内の `gh` コマンドで書く。

**Tech Stack:** Markdown（Claude Code skill）、bash、gh CLI

**Spec:** `docs/superpowers/specs/2026-11-17-work-report-common-rules-design.md`

## Global Constraints

- 作業ブランチは `feat/work-report-common-rules`（main から切る）。コミットは関係ファイルだけを `git add` する（作業ツリーに無関係な変更・未追跡ファイルがある）
- コミットプレフィックス: `feat:` / `docs:`。全コミット後に `git push`
- 金曜の作業内容は「テーマ単位で抽象的・PR番号と技術詳細なし」を維持する（spec 反目標）
- 1PR を2行以上に割らない既存ルールは残す
- レビュー行は「対象名のみ・括弧書きなし・一次記録で裏取り」の既存ルールを残す
- frontmatter の `version` を `1.2.0` → `1.3.0`

## Review Focus

1. 流れが1本だけの案件で、流れの見出しを出してしまう → 見出しを省き行を直接並べる（Task 1 の規則文と Task 3 のドライランで確認）
2. 水曜で「その他」案件（阪急等）と AI 案件が混ざって並ぶ → AI 系を先・その他を後（Task 2 の出力例で固定）
3. 月曜の対象範囲で研修（tamaki-ai-training）を出してしまう → 出さない（Task 1 の表、Task 3 で確認）
4. 対応中に、レビュー依頼が来ているだけで未着手の PR を「〇〇さんのレビュー」と出す → 依頼中は出してよい（対応中は未着手も含む）。実績側のレビューは一次記録必須のまま（Task 2）
5. 「本番反映済み／未反映」を PR 本文から推測して書く → デプロイ workflow の実行記録・リリースタグで確かめる（Task 2 のコマンド例）

---

### Task 1: 共通の組み立てルールとモード差分表

**Files:**
- Modify: `.claude-global/skills/work-report/SKILL.md:14-24`（冒頭のモード表）
- Modify: `.claude-global/skills/work-report/SKILL.md:237-291`（分類ロジック: カテゴリ判定・サブプロジェクト名・統合ルール）
- Add: `docs/superpowers/specs/2026-11-17-work-report-common-rules-design.md`（既に作成済み。このタスクでコミット）

**Interfaces:**
- Produces: 節見出し `### 組み立てルール（月・水・金共通）` と `### モード別の違い`。Task 2 の出力形式節はこの2つを参照する

- [ ] **Step 1: ブランチを切る**

Run: `git -C ~/.dotfiles switch -c feat/work-report-common-rules main`
Expected: `Switched to a new branch`

- [ ] **Step 2: 冒頭のモード表（14-24行）を書き換える**

- AI案件モード: 想定読者「チャットアプリの会議参加者」、出力対象「チャットアプリ関連のみ」、出力「先週の作業実績／現在対応中の作業／今後の作業予定の3セクション」
- 会議報告モード: 出力「案件 → 流れ → 行の実績のみ」
- 週報モード: ①工数まとめを「案件単位」に変更
- 表の下の説明文の「AI関連の案件のみ」を「チャットアプリ関連のみ」に直す

- [ ] **Step 3: 分類ロジックを置き換える**

- 「カテゴリ判定」の表は残し、その下に「月曜の対象範囲」を1段落で足す（spec のモード差分表「対象範囲」の月曜セルをそのまま使う）
- 「サブプロジェクト名（表示名マッピング）」節は「案件名」節に改める。案件名は顧客・プロダクト名（プラス社デモ、シフトオン、eBASEサポートAI、阪急キッチンエール 等）。リポジトリ名→表示名の固定マッピング表は削除し、「リポジトリ名は見出しにしない」を書く
- 「統合ルール」節を `### 組み立てルール（月・水・金共通）` に置き換え、spec「共通ルール」1〜8 を番号付きで書く。既存の「1PR=1行の判定手順（ブランチ名・worktree名で束ねる／日報のPR番号で補強）」と「レビュー計上の裏取りコマンド」は、この節の中に残す
- 既存の「関連する複数の作業は可能な限り1行にまとめる」「統合は上方向のみ許可」「判断に迷う軽微な作業は残す」は削除し、共通ルール3・4に置き換える
- `### モード別の違い` として spec のモード差分表を写す

- [ ] **Step 4: 検証**

Run:
```bash
f=~/.dotfiles/.claude-global/skills/work-report/SKILL.md
grep -c '組み立てルール（月・水・金共通）' "$f"   # 1以上
grep -n 'チャットアプリ' "$f" | head              # 冒頭表と月曜の対象範囲に出る
grep -n -E '統合は上方向のみ|判断に迷う軽微な作業' "$f"  # 0件
grep -n 'ebase-portal-chat` | `AI-search' "$f"     # 0件（固定マッピング表の削除）
```
Expected: コメントどおり

- [ ] **Step 5: Commit**

```bash
git -C ~/.dotfiles add .claude-global/skills/work-report/SKILL.md docs/superpowers/specs/2026-11-17-work-report-common-rules-design.md docs/superpowers/plans/2026-11-17-work-report-common-rules.md
git -C ~/.dotfiles commit -m "feat: work-report の月・水・金を案件→流れ→行の共通ルールで組み立てる"
```

### Task 2: 出力形式・対応中の収集コマンド・エラー処理

**Files:**
- Modify: `.claude-global/skills/work-report/SKILL.md:292-429`（出力形式）
- Modify: `.claude-global/skills/work-report/SKILL.md:85-236`（コマンド例に節を追加）
- Modify: `.claude-global/skills/work-report/SKILL.md:430-440`（エラー処理）、frontmatter `version`

**Interfaces:**
- Consumes: Task 1 の `### 組み立てルール（月・水・金共通）` / `### モード別の違い`

- [ ] **Step 1: コマンド例に「対応中・予定の取得（月曜のみ）」節を足す**

`eBASE-Mori` のトークンで3本:
- 自分の open PR: `gh search prs --owner ebase-dev --author eBASE-Mori --state open --json repository,number,title,isDraft`
- レビュー依頼中: `gh search prs --owner ebase-dev --review-requested eBASE-Mori --state open --json repository,number,title,author`
- 担当 open issue: `gh search issues --owner ebase-dev --assignee eBASE-Mori --state open --json repository,number,title,updatedAt`（予定の参考。自分の open PR が紐づくものは除く）

その下に「PR・issue から読めない進行中の作業と issue 化前の予定は AskUserQuestion で聞く」「todo.md は会議時点で更新されていないことが多いため使わない」を書く。

- [ ] **Step 2: コマンド例に「本番反映の確認」節を足す**

```bash
GH_TOKEN="$GH_TOKEN_WORK" gh run list --repo ebase-dev/<repo> --workflow <production-deploy-*.yml> --limit 3 \
  --json createdAt,conclusion,headSha
git -C <repo> merge-base --is-ancestor <マージコミット> <deploy の headSha またはリリースタグ> && echo 反映済み
```
本文に「PR 本文の『反映の順序』から反映状況を推測しない」を1行。

- [ ] **Step 3: 出力形式節を書き換える**

- AI案件モード: 出力例を下の3セクション形にする（2026-11-17 の最終版を元にした例。流れが1本の「プラス社デモ」は流れ見出しなし）

```
先週の作業実績

- プラス社デモ
    - デモのフィードバック4点の調査、getItemGroups導入の方針決定（実データでの件数比較・まとめる単位の比較評価）
    - getItemGroupsへの素材タイトル条件・優先表示（prefer）の追加とebase-web-v3への配置
    - 種類で探す検索のgetItemGroups切替（品番単位のまとめ・既存評価での精度維持確認）
- シフトオン
    - 第1弾フィードバック対応
        - AI参考情報の指示文を設定項目で変更可能に
            - 設定項目への指示2項目の追加と管理画面への配置
            - 設定を返すJSPへの2項目追加、検証ai-searchへの配置
            - 指示文をAI参考情報の生成に渡す実装（銘柄禁止ルールの固定・想定問答41問での指示有無の比較）
        - 車両詳細取得の時間切れ対策（eB-APIの遅延原因の実測・12項目ずつの分割取得）
    - 画面・機能の改修
        - 電話番号の受付時間カンマの登録時チェック
        - レビュー: 車両候補の選択肢バブル表示
- eBASEサポートAI
    - 社外向け公開（ASP9疎通確認・Apacheリバースプロキシ設定・X-Forwarded-For詐称対策の動作確認）

現在対応中の作業

- プラスのデモ対応（実装は完了済みで、動作確認と依頼文の作成を行っている）
- シフトオン対応
    - 車両情報のリンクボタン
    - AI参考情報のeBASE読み込み
- 辻本さんのレビュー

今後の作業予定

- 車両検索時に項目が一つでも明らかになっている場合は候補をバブルで出す
```

- 会議報告モード: 出力例を「AI 系案件 → その他案件」の順で、カテゴリ見出しなし・案件 → 流れ → 行にする。その他の例は「阪急キッチンエール」1件
- 週報モード: 工数を案件単位に（出力例の `AI-search: 3人日` 等を案件名に）。作業内容は案件見出し＋テーマ単位の行（抽象度は従来どおり）。工数配分手順（N の決定的カウント・正規化）は変更しない
- 各モードの説明から、Task 1 で削除したルール（上方向統合等）への言及を消す

- [ ] **Step 4: エラー処理と version**

- 439行: 「AI案件モードでAIカテゴリの活動が0件」→「AI案件モードでチャットアプリ関連の活動が0件」
- frontmatter `version: 1.3.0`

- [ ] **Step 5: 検証**

Run:
```bash
f=~/.dotfiles/.claude-global/skills/work-report/SKILL.md
grep -n -E '^先週の作業実績|^現在対応中の作業|^今後の作業予定' "$f"   # 各1件
grep -n 'review-requested' "$f"                                  # 1件以上
grep -n '反映の順序' "$f"                                        # 1件以上
grep -n '^version: 1.3.0' "$f"                                   # 1件
grep -n -E '^- AI$|^    - AI-search$' "$f"                       # 0件（旧形式の例が残っていない）
```
Expected: コメントどおり

- [ ] **Step 6: Commit**

```bash
git -C ~/.dotfiles add .claude-global/skills/work-report/SKILL.md
git -C ~/.dotfiles commit -m "feat: work-report の月曜に対応中・今後の予定を出し、出力例を案件単位にする"
```

### Task 3: ドライランで最終版と突き合わせる

**Files:**
- なし（検証のみ。結果は会話で報告）

- [ ] **Step 1: 新しいスキルで 2026-11-10〜2026-11-17 の月曜モードを生成する**

fresh なサブエージェントに「`~/.dotfiles/.claude-global/skills/work-report/SKILL.md` に従い、2026-11-10〜2026-11-17 を AI案件モードで集計して出力だけ返す。AskUserQuestion の代わりに、聞きたい事項を末尾に列挙する」と依頼する。

- [ ] **Step 2: ユーザーの最終版（spec 作成時の会話にあるもの）と比べる**

合格条件:
- 案件見出しがリポジトリ名でない（`ebase-portal-chat`・`eb-api-extended` 等が見出しに出ない）
- 研修（エージェント開発研修）が出ない
- 「ローカル開発からの復号API到達不可の調査」「Google API等への流用可否の整理」「先方確認事項の精査」が出ない
- 実績の行に（対応中）が付かない
- 対応中に #1276・#1278 由来の2件と「辻本さんのレビュー」が出る
- プラスの「動作確認・依頼文作成中」と issue 化前の予定は「聞きたい事項」に挙がる

不合格項目があれば、該当ルールの文面を Task 1/2 の節で直して再コミットし、Step 1 からやり直す（最大2回。超えたらユーザーに相談）。

- [ ] **Step 3: Push**

Run: `git -C ~/.dotfiles push -u origin feat/work-report-common-rules`
Expected: push 成功（失敗時は `git remote set-url origin git@github-aya215:aya-215/dotfiles.git`）
