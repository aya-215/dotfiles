# Claude Code チートシート（日本語訳）

**バージョン:** Claude Code v2.1.88  
**最終更新:** 2026年3月31日  
**原文:** https://cc.storyfox.cz/  
**作者:** [@phasE89](https://x.com/phasE89)

---

## 最近の変更（変更履歴）

- `CLAUDE_CODE_NO_FLICKER=1` 代替画面レンダリング (v2.1.88)
- `PermissionDenied` フックイベント (v2.1.88)
- `@` メンション候補に名前付きサブエージェント対応 (v2.1.88)
- 思考サマリーをデフォルト無効化（`showThinkingSummaries`）(v2.1.88)
- Windows用PowerShellツール（オプトインプレビュー）(v2.1.84)
- フック用条件付き `if` フィールド（権限ルール構文）(v2.1.85)

---

## ⌨️ キーボードショートカット

### 基本操作

| ショートカット | 動作 |
|---|---|
| Ctrl+C | 入力・生成をキャンセル |
| Ctrl+D | セッション終了 |
| Ctrl+L | 画面クリア |
| Ctrl+O | 詳細表示・トランスクリプト切替 |
| Ctrl+R | 履歴逆順検索 |
| Ctrl+G | エディタでプロンプトを開く |
| Ctrl+X Ctrl+E | エディタで開く（エイリアス） |
| Ctrl+B | タスクをバックグラウンド実行 |
| Ctrl+T | タスクリスト切替 |
| Ctrl+V | 画像貼り付け（`[Image #N]` チップ表示） |
| Ctrl+X Ctrl+K | バックグラウンドエージェントを停止 |
| Esc Esc | 会話を巻き戻す・要約する |

### モード切替

| ショートカット | 動作 |
|---|---|
| Shift+Tab | 権限モードを循環切替 |
| Alt+P | モデル切替 |
| Alt+T | 思考モード切替 |
| Alt+O | 高速モード切替 |

### 入力

| ショートカット | 動作 |
|---|---|
| `\`+Enter | 改行（クイック） |
| Ctrl+J | 改行（コントロールシーケンス） |

### プレフィックス

| プレフィックス | 機能 |
|---|---|
| `/` | スラッシュコマンド |
| `!` | Bashコマンド直接実行 |
| `@` | ファイルメンション＋オートコンプリート |

### セッション選択画面

| キー | 動作 |
|---|---|
| ↑↓ | 上下移動 |
| ←→ | 展開・折りたたみ |
| / | 検索 |

> ⚠️ 注意: 原文では `P`（プレビュー）、`R`（名前変更）、`A`（全プロジェクト）、`B`（現在のブランチ）も記載されているが、実際には文字入力はすべて検索欄に入るため動作しない可能性あり（未確認・バージョン依存）

### トランスクリプトモード（Ctrl+O）

| キー | 動作 |
|---|---|
| / | トランスクリプト内検索 |
| N / Shift+N | 次・前の一致へ移動 |
| Ctrl+E | 全表示切替 |
| Q / Esc | トランスクリプト終了 |

---

## 🔌 MCPサーバー

### サーバー追加

- `--transport http` - リモートHTTP（推奨）
- `--transport stdio` - ローカルプロセス
- `--transport sse` - リモートSSE

### スコープ

- **Local（ローカル）** - `~/.claude.json`（自分のみ）
- **Project（プロジェクト）** - `.mcp.json`（共有・VCS管理）
- **User（ユーザー）** - `~/.claude.json`（グローバル）

### 管理

- `/mcp` - インタラクティブUI
- `claude mcp list` - サーバー一覧表示
- `claude mcp serve` - Claude CodeをMCPサーバーとして起動

### 機能

- **Elicitationサーバー** - タスク中に入力を要求可能
- **2KBの上限** - ツール説明＋サーバー指示の合計制限

---

## ⚡ スラッシュコマンド

### セッション系

- `/clear` - 会話をクリア
- `/compact [フォーカス]` - コンテキストを圧縮
- `/resume` - セッションの再開・切替
- `/rename [名前]` - 現在のセッションに名前をつける
- `/branch [名前]` - 会話を分岐（`/fork` エイリアス）
- `/cost` - トークン使用量の統計
- `/context` - コンテキストの可視化（グリッド表示）
- `/diff` - インタラクティブなdiffビューア
- `/copy [N]` - 最後（またはN番目）のレスポンスをコピー
- `/rewind` - 会話・コードのチェックポイントに巻き戻す
- `/export` - 会話をエクスポート

### 設定系

- `/config` - 設定を開く
- `/model [モデル]` - モデル切替（←→でエフォート調整）
- `/fast [on|off]` - 高速モード切替
- `/vim` - Vimモード切替
- `/theme` - カラーテーマ変更
- `/permissions` - 権限の表示・更新
- `/effort [レベル]` - エフォートレベル設定（low/medium/high/max/auto）
- `/color [色]` - プロンプトバーの色設定
- `/keybindings` - キーボードショートカットのカスタマイズ
- `/terminal-setup` - ターミナルキーバインドの設定

### ツール系

- `/init` - CLAUDE.mdを作成
- `/memory` - CLAUDE.mdファイルを編集
- `/mcp` - MCPサーバー管理
- `/hooks` - フック管理
- `/skills` - 利用可能なスキル一覧
- `/agents` - エージェント管理
- `/chrome` - Chrome連携
- `/reload-plugins` - プラグインのホットリロード
- `/add-dir <パス>` - 作業ディレクトリを追加

### 特殊コマンド

- `/btw <質問>` - コンテキストなしのサイドクエスチョン
- `/plan [説明]` - プランモード（自動スタートも可）
- `/loop [間隔]` - 定期実行タスクのスケジュール
- `/voice` - プッシュトゥトーク音声入力（20言語対応）
- `/doctor` - インストール診断
- `/pr-comments [PR]` - GitHub PRのコメント取得
- `/stats` - 使用状況のストリーク＆設定
- `/insights` - セッションレポートの分析
- `/desktop` - デスクトップアプリで継続
- `/remote-control` - claude.ai/codeへのブリッジ（`/rc`）
- `/usage` - プランの制限・レート状況
- `/schedule` - クラウドスケジュールタスク
- `/security-review` - 変更内容のセキュリティ分析
- `/help` - ヘルプ＋コマンド一覧
- `/feedback` - フィードバック送信（`/bug` エイリアス）
- `/release-notes` - 全変更履歴の表示
- `/stickers` - ステッカーを注文！🎉

---

## 📁 メモリ＆ファイル

### CLAUDE.mdの配置場所

- `./CLAUDE.md` - プロジェクト（チーム共有）
- `~/.claude/CLAUDE.md` - 個人用（全プロジェクト共通）
- `/etc/claude-code/` - 管理用（組織全体）

### ルール＆インポート

- `.claude/rules/*.md` - プロジェクトルール
- `~/.claude/rules/*.md` - ユーザールール
- `paths:` フロントマター - パス固有のルール
- `@path/to/file` - CLAUDE.md内でのインポート

### 自動メモリ

- `~/.claude/projects/<プロジェクト>/memory/`
- MEMORY.md＋トピックファイル、自動読み込み（最大25KB/200行）

---

## 🧠 ワークフロー＆Tips

### プランモード

- Shift+Tab - 通常 → 自動承認 → プランモードを循環
- `--permission-mode plan` - プランモードで起動

### 思考＆エフォート

- Alt+T - 思考モードのオン・オフ切替
- "ultrathink" - そのターンだけ最大エフォートで実行
- Ctrl+O - 思考内容を表示（詳細モード）
- `/effort` - ○ low · ◐ medium · ● high · ★ max

### Gitワークツリー

- `--worktree name` - 機能ごとに独立ブランチを作成
- `isolation: worktree` - エージェントを専用ワークツリーで実行
- `sparsePaths` - 必要なディレクトリだけをチェックアウト
- `/batch` - ワークツリーを自動作成して並列実行

### 音声モード

- `/voice` - プッシュトゥトークを有効化
- Space（長押し）- 録音、離すと送信
- 20言語対応 - EN, ES, FR, DE, CZ, PLなど

### コンテキスト管理

- `/context` - 使用量＋最適化のヒント
- `/compact [フォーカス]` - フォーカスを指定して圧縮
- 容量約95%で自動圧縮
- 1Mコンテキスト - Opus 4.6（Max/Team/Enterpriseプラン）
- **CLAUDE.mdは圧縮後も残る！**

### セッション活用術

- `claude -c` - 最後の会話を継続
- `claude -r "名前"` - 名前で会話を再開
- `/btw 質問` - コンテキスト消費なしのサイドクエスチョン

### SDK・ヘッドレス実行

- `claude -p "クエリ"` - 非インタラクティブ実行
- `--output-format json` - 構造化出力
- `--max-budget-usd 5` - コスト上限設定
- `cat file | claude -p` - パイプ入力

### スケジュール＆リモート

- `/loop 5m メッセージ` - 5分ごとに定期実行
- `/rc` - リモートコントロール
- `--remote` - claude.aiでウェブセッション開始

---

## ⚙️ 設定＆環境変数

### 設定ファイル

- `~/.claude/settings.json` - ユーザー設定
- `.claude/settings.json` - プロジェクト設定（共有）
- `.claude/settings.local.json` - ローカルのみ
- `~/.claude.json` - OAuth、MCP、状態管理
- `.mcp.json` - プロジェクトのMCPサーバー設定
- `managed-settings.d/` - ドロップイン方式のポリシー設定

### 主要設定項目

- `modelOverrides` - モデルピッカーのカスタムIDへのマッピング
- `autoMemoryDirectory` - カスタムメモリディレクトリ
- `worktree.sparsePaths` - スパースチェックアウト対象ディレクトリ
- `sandbox.failIfUnavailable` - サンドボックス利用不可時に終了
- `hooks: if` - 条件付きフック（権限ルール構文）
- `PermissionDenied` - フック：自動モードの拒否イベント
- `showThinkingSummaries` - 思考サマリー表示（デフォルト無効）
- `allowedChannelPlugins` - 管理者向けチャンネルプラグイン許可リスト

### 主要環境変数

- `ANTHROPIC_API_KEY`
- `ANTHROPIC_MODEL`
- `CLAUDE_CODE_EFFORT_LEVEL` - low/medium/high/max/auto
- `MAX_THINKING_TOKENS` - 0で無効化
- `ANTHROPIC_CUSTOM_MODEL_OPTION` - `/model` のカスタムエントリ
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` - サブプロセスから認証情報を除去
- `CLAUDE_STREAM_IDLE_TIMEOUT_MS` - ストリーミングのウォッチドッグ（デフォルト90秒）
- `CLAUDE_CODE_NO_FLICKER` - 代替画面レンダリング（=1）
- `CLAUDECODE` - Claude Codeシェルの検出（=1）

---

## 🔧 スキル＆エージェント

### 組み込みスキル

- `/simplify` - コードレビュー（3つの並列エージェント）
- `/batch` - 大規模な並列変更（5〜30ワークツリー）
- `/debug [説明]` - デバッグログからトラブルシューティング
- `/loop [間隔]` - 定期スケジュールタスク
- `/claude-api` - API＋SDKリファレンスの読み込み

### カスタムスキルの配置場所

- `.claude/skills/<名前>/` - プロジェクトスキル
- `~/.claude/skills/<名前>/` - 個人スキル

### スキルのフロントマター

- `description` - 自動呼び出しのトリガー
- `allowed-tools` - 権限プロンプトをスキップ
- `model` - スキル用のモデルをオーバーライド
- `effort` - エフォートレベルをオーバーライド
- `paths: [globs]` - パス固有のスキル（YAMLリスト）
- `context: fork` - サブエージェントで実行
- `$ARGUMENTS` - ユーザー入力のプレースホルダー
- `${CLAUDE_SKILL_DIR}` - スキル自身のディレクトリ
- `` !`cmd` `` - 動的コンテキストの注入

### 組み込みエージェント

- **Explore** - 高速リードオンリー（Haiku使用）
- **Plan** - プランモード用の調査エージェント
- **General** - フルツール・複雑なタスク用
- **Bash** - 別コンテキストのターミナル

### エージェントのフロントマター

- `permissionMode` - default/acceptEdits/plan/dontAsk/bypassPermissions
- `isolation: worktree` - Gitワークツリーで実行
- `memory: user|project|local` - 永続メモリ
- `background: true` - バックグラウンドタスク
- `maxTurns` - エージェントのターン数制限
- `initialPrompt` - 最初のターンを自動送信
- `SendMessage` - エージェントの再開（resumeの代替）
- `@エージェント名` - 名前付きサブエージェントへのメンション

---

## 🖥️ CLIコマンド＆フラグ

### 基本コマンド

- `claude` - インタラクティブ起動
- `claude "q"` - プロンプト付き起動
- `claude -p "q"` - ヘッドレス実行
- `claude -c` - 前回の会話を継続
- `claude -r "n"` - 名前で再開
- `claude update` - アップデート

### 主要フラグ

- `--model` - モデルを指定
- `-w` - Gitワークツリーを使用
- `-n` / `--name` - セッション名を設定
- `--add-dir` - ディレクトリを追加
- `--agent` - エージェントを使用
- `--allowedTools` - ツールを事前承認
- `--output-format json/stream` - 出力フォーマット
- `--json-schema` - 構造化出力
- `--max-turns` - ターン数制限
- `--max-budget-usd` - コスト上限
- `--console` - Anthropic Consoleで認証
- `--verbose` - 詳細表示
- `--bare` - 最小限のヘッドレス（フック・LSP無効）
- `--channels` - 権限リレー / MCPプッシュ
- `--remote` - ウェブセッション
- `--effort low/medium/high/max` - エフォートレベル
- `--permission-mode plan/default/…` - 権限モード
- `--dangerously-skip-permissions` - 全プロンプトをスキップ ⚠️
- `--chrome` - Chrome連携
- PowerShellツール - Windowsオプトインプレビュー

---

## 権限モード

| モード | 説明 |
|---|---|
| `default` | 都度確認プロンプトを表示 |
| `acceptEdits` | ファイル編集を自動承認 |
| `plan` | 読み取り専用モード |
| `dontAsk` | 許可されていない場合は拒否 |
| `bypassPermissions` | 全権限チェックをスキップ |
| `--dangerously-skip-permissions` | CLIフラグ：全プロンプトをスキップ |
