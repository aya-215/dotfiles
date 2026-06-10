# claude -p 自動実行のクラウドルーティン移行 設計書

**日付:** 2026-06-10
**ステータス:** ユーザー承認済み（会話で設計合意）

## 背景

2026-06-15 から `claude -p`（headless実行）はサブスク枠から外れ、**Agent SDKクレジット**（Teamプレミアムシート: $100/月、APIレート課金、繰越なし）を消費するようになる。一方、**クラウドルーティンはAPIトリガー起動を含めサブスク枠のまま**（公式: routines docs「Routines draw down subscription usage the same way interactive sessions do」、/fire APIリファレンス比較表「Billing: Claude Code subscription usage on claude.ai」）。

### claude -p 使用箇所の棚卸しと方針

| 仕組み | 内容 | 6/15以降の影響 | 方針 |
|---|---|---|---|
| daily-review-auto.sh（cron 22:00） | 毎晩Opusでエージェント実行、日報Issue更新 | 月$100超のリスク大 | **クラウドルーティン化（本設計）** |
| summarize.sh（SessionEndフック） | Haikuでセッション要約、1日3〜5件 | 実測ベース月$6程度 | **現状維持**（クレジット消費を容認、月次で監視） |
| nb-sync.sh（cron 30分毎） | git同期のみ、claude不使用 | 影響なし | 変更なし |
| 挨拶 7時/12時 | — | — | ルーティン移行済み（2026-06-10） |

## 制約（設計を縛った事実）

1. **セッション要約はGitHubに無い**: `~/.nb/claude/` は nbリポジトリの .gitignore 対象（トラッキング0件・履歴にも一切なし）。会話由来データをGitHubに上げない方針は維持する。
2. **Rocket Chatはインターネット公開**: クラウドからも到達可能だが、認証情報は極力ローカルに残す。
3. **旧生ログにシークレット残留**: `~/.nb/claude/*.md`（2026年1〜3月、旧claude-nb-sync方式）に GitHub PAT 6個・Anthropic APIキー 2個のパターンを検出。**ローカルのみで外部流出は無し**（gitignoreが機能していた）。ローカル削除のみ実施、キーローテーションは任意。
4. work リポジトリ（ebase-dev）は github.com 上にあり、GitHub API でコミット検索可能。社内GitBucket分の活動はセッション要約から拾う。

## アーキテクチャ

```
【ローカル（22:10 cron、claude不使用＝クレジット消費ゼロ）】
fire-daily-review.sh（新規）
  ├ 当日のセッション要約を連結（~/.nb/claude/sessions/<date>/*.md）
  ├ fetch-rocketchat.sh で RC履歴取得（RC認証はローカルの.env.localのまま）
  ├ redaction: シークレットパターンを [REDACTED] に置換
  ├ 64KB制限ガード: 超過時は古いセッションから切り詰め
  └ curl POST → /fire エンドポイント（text=要約+RC履歴）

【クラウド（APIトリガーでのみ起動、サブスク枠）】
daily-review ルーティン
  ├ トリガー: APIのみ（スケジュール無し。空振り実行と二重日報を防ぐ）
  ├ clone: aya-215/dotfiles（public。.claude-global/skills/daily-review/SKILL.md を参照）
  ├ git活動収集: gh api でコミット検索（env: GH_TOKEN_AYA215, GH_TOKEN_EBASE）
  ├ 入力: textペイロード（セッション要約+RC履歴）
  └ 出力: aya-215/life の日報Issue「📝 サマリー」更新（gh issue edit / close済みならblog md編集+push）
```

### データフローとセキュリティ境界

- 会話由来データの経路: ローカル → HTTPS → Anthropic（クラウドセッション）のみ。**GitHubには一切上がらない**。現行の `claude -p`（プロンプト埋め込み）と同じ到達範囲。
- クラウドに預ける秘密情報: **GitHub PAT 2枚のみ**（ルーティン環境の環境変数）。
  - `GH_TOKEN_AYA215`: fine-grained PAT。スコープ: aya-215/life（Issues RW）+ 自分のリポジトリのコミット参照
  - `GH_TOKEN_EBASE`: fine-grained PAT。スコープ: ebase-dev org の対象リポジトリ read-only
- ローカルに残る秘密情報: RC_TOKEN等（既存の `.env.local`）+ 新規にルーティンの fire 用トークン（`ROUTINE_FIRE_URL` / `ROUTINE_FIRE_TOKEN` を同じ `.env.local` に追記、権限600）。
- fire トークンの被害半径: 単一ルーティンの起動のみ（読み取り不可）。漏洩時はWeb UIで再生成すれば旧トークンは失効。

### redaction 仕様

`fire-daily-review.sh` の送信前と、`summarize.sh` の要約ファイル書き出し後（二重ガード）に適用:

```
ghp_[A-Za-z0-9]{36}            → [REDACTED:ghp]
github_pat_[A-Za-z0-9_]{20,}   → [REDACTED:github_pat]
sk-ant-[A-Za-z0-9_-]{20,}      → [REDACTED:sk-ant]
sk-[A-Za-z0-9]{32,}            → [REDACTED:sk]
AKIA[0-9A-Z]{16}               → [REDACTED:akia]
xox[bporas]-[A-Za-z0-9-]{10,}  → [REDACTED:slack]
Bearer [A-Za-z0-9._=-]{25,}    → Bearer [REDACTED]
X-Auth-Token: \S{20,}          → X-Auth-Token: [REDACTED]
```

### エラーハンドリング

- RC取得失敗: プレースホルダ文字列で続行（現行どおり）
- セッション要約ゼロ件: 「(本日のセッション要約なし)」で続行
- fire POST 失敗（429/503等）: 60秒間隔で最大3回リトライ、全滅時はログに記録して終了（翌日の手動 `/daily-review` でリカバリ可能）
- ルーティン側: textペイロードが無い/空の場合（手動Run now等）は、gh api 収集分とIssueメモだけでサマリー生成し、その旨を明記する

### ルーティン設定

- 名前: `daily-review`
- モデル: Opus（現行 `--model opus` と同等品質を維持）
- 環境: Default（env_01X9JcJWqdgPvER4JA37Gt1U）に GH_TOKEN 2本を追加。ネットワークはTrustedのまま（github.com はデフォルト許可域。RCへはクラウドから接続しない）
- リポジトリ: aya-215/dotfiles（スキル参照用）と aya-215/life（close済み日報のblog md編集・push用）の2つ。「Allow unrestricted branch pushes」は life のみ有効化し、dotfiles はデフォルト（claude/プレフィックスのみ）のまま
- プロンプト: daily-review-auto.sh の現行プロンプトを移植し、(a) git log → gh api 置換、(b) RC/要約はtextペイロード参照、(c) スキルはcloneした dotfiles の `.claude-global/skills/daily-review/SKILL.md` を読む指示、に書き換える

## 実装範囲

1. **fire-daily-review.sh 新規作成**（scripts/daily-review/）: 収集・redaction・切り詰め・POST。ShellCheck準拠
2. **summarize.sh に redaction 追加**: 書き出し後の後処理に置換フィルタを挿入
3. **daily-review ルーティン作成**: RemoteTriggerでベース作成 → ユーザーがWeb UIでAPIトリガー追加・トークン発行・スケジュールトリガー削除・環境変数設定
4. **cron 切替**: `daily-review-auto.sh` の行を `fire-daily-review.sh` に置換（22:00→22:10）
5. **検証**: サンプルペイロードで手動fire → 日報Issue更新を確認 → cron切替
6. **掃除**: daily-review-auto.sh 削除（検証完了後）、旧生ログ `~/.nb/claude/*.md`（2026-01〜03）のローカル削除
7. **メモリ更新**: agent-memory の automation/daily-review-skill-integration.md 等を新構成に更新

## 実装範囲外（明示的に見送り）

- summarize.sh のクラウド化・バッチ化（機密性懸念で却下、クレジット内で現状維持）
- nb-sync.sh への push 前シークレットガード（claude/ はgitignore済みで経路が存在しないため）
- 検出済みキーのローテーション（外部流出なしのため任意。ユーザー判断）
- 週報・月報・mentor等の対話スキル（interactive実行はサブスク枠のままで影響なし）

## ユーザー作業（実装中に発生）

1. GitHub fine-grained PAT 2枚の発行（スコープは上記）
2. claude.ai でルーティンのAPIトリガー追加・トークン発行（CLI不可のため）
3. ルーティン環境への環境変数登録（claude.ai のenvironment設定）
4. （任意）検出された8キーのうち現役のものをローテーション

## 検証基準（Done の定義）

- 手動fireで日報Issueの「📝 サマリー」がWork/Personal分類・レビュー/実装区別付きで更新される
- redactionテスト: ダミーキー（例: `ghp_` + 36文字）を含む偽要約が `[REDACTED:ghp]` に置換されて送信される
- cron起動で22:10に自動実行され、翌朝のIssueに反映されている
- `claude -p` の実行が crontab / hooks から daily-review 経路で消えている（summarize.sh は残る）
