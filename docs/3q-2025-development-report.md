  3Q（2025年10月〜12月）開発状況 調査報告書

> この文書は3Qの開発状況報告を作成するための参考資料（調査結果まとめ）です。

## 1. 全体サマリー

### 対象リポジトリ

| リポジトリ | 概要 | 技術スタック |
|-----------|------|------------|
| **ebase-middleware-mcp** | MCPサーバー基盤（ebase Web API連携） | Node.js, TypeScript, FastAPI, Python, Docker, Kubernetes |
| **ebase-portal-chat** | ポータルチャットアプリ | Next.js, React, TypeScript, LangChain, Tailwind CSS, Storybook |

### eBASE-Moriの担当割合

| 指標 | ebase-middleware-mcp | ebase-portal-chat | 合計 |
|------|---------------------|-------------------|------|
| コミット数 | 51 / 99 (**51.5%**) | 147 / 435 (**33.8%**) | 198 / 534 (37.1%) |
| マージ済みPR | 6件 | 9件 | **15件** |
| 追加行数 | 4,598 | 9,853 | **14,451** |
| 削除行数 | 1,218 | 7,812 | **9,030** |

### チームメンバー別コミット数

**ebase-middleware-mcp:**

| メンバー | コミット数 | 主な担当 |
|---------|----------|---------|
| eBASE-Mori | 51 | リモートMCP移行、K8s/Docker基盤、リファクタリング |
| Hisakata Matsumoto | 25 | document-mcp初回実装、LangSmith統合 |
| ebase-tsujimoto | 16 | PDF解析LangSmith統合・評価フレームワーク |
| ebase-sato | 7 | レビュー・マージ |

**ebase-portal-chat:**

| メンバー | コミット数 | 主な担当 |
|---------|----------|---------|
| Hisakata Matsumoto | 160 | インフラ、セットアップ、セキュリティ更新 |
| eBASE-Mori | 147 | チャットUIコンポーネント、デザインシステム |
| ebase-iyanaga | 99 | チャットコンポーネント、リファクタリング |
| murashige.k | 16 | LLMエージェント＆MCP統合 |
| sasaki-ebase | 11 | レビュー参加 |
| ebase-yaoyama | 2 | - |

---

## 2. ebase-middleware-mcp — eBASE-Moriの成果

### PR一覧（時系列）

| PR | タイトル | マージ日 | 追加 | 削除 |
|----|---------|---------|------|------|
| #39 | feat: eb-api-mcpをリモートMCP（Streamable HTTP）に移行 | 2025-10-08 | +3,142 | -819 |
| #41 | Docker, K8sへの移行 | 2025-10-20 | +457 | -0 |
| #43 | feat(eb-api-mcp): 動的接続先設定機能の実装 | 2025-10-23 | +237 | -141 |
| #48 | chore(eb-api-mcp): bump version to 1.1.0 for production deployment | 2025-10-23 | +2 | -2 |
| #49 | MCPのリファクタリング | 2025-10-24 | +47 | -17 |
| #51 | docs: readmeとmcpの共有設定の作成 | 2025-11-06 | +713 | -239 |

### テーマ別詳細

#### テーマA: リモートMCP移行（stdio → Streamable HTTP）
**関連PR**: #39, #43, #48

- **アーキテクチャ変更**: stdioトランスポートからStreamable HTTPトランスポートへ移行
- **目的**: 複数同時セッション対応、リモートクライアント接続の実現
- **PR #39 の主な実装内容**:
  - HTTPトランスポートの実装
  - 環境変数サポート（デフォルト値付き）
  - 開発フラグ（IS_DEV_FLAG）導入
  - InMemoryEventStoreのドキュメント改善
  - コードのモジュール分割
- **PR #43 の主な実装内容**:
  - HTTPヘッダーによる動的接続先設定
  - ConnectionConfigインターフェース（型安全な設定管理）
  - セッション固有の接続設定管理
  - 環境変数デフォルトとの後方互換性維持
  - 異なるサーバーへの複数同時接続対応
  - キャッシュキーにエンドポイント情報を含める
  - executeToolWithErrorHandlingの可変引数対応
- **PR #48**: バージョン1.0.0→1.1.0として本番デプロイ準備完了

#### テーマB: K8s/Docker基盤構築
**関連PR**: #41

- eb-api-mcpサービスのDocker化
- Kubernetesマニフェスト整備（Kustomize構成）
  - `base/` — 共通リソース定義
  - `overlays/kind/` — ローカル開発環境
  - `overlays/production/` — 本番環境
- ヘルスチェックエンドポイント（`/health`, `/healthz`）
- nginx リバースプロキシ構成
- Kind クラスタ設定（ローカルテスト用）
- GHCR イメージプルシークレット設定

#### テーマC: コード品質・ドキュメント
**関連PR**: #49, #51

- ツール名のeb_api_プレフィクス統一
- サーバー名変更: "ebase server api search" → "eb-api-mcp-server"
- 共通ツールアノテーションの定数化
- README改善、MCP共有設定作成
- システムプロンプト説明追加
- クライアント設定ガイダンス整理

### 他メンバーの主な成果

| PR | 担当者 | タイトル | マージ日 |
|----|-------|---------|---------|
| #52 | Hisakata Matsumoto | document-mcp (PDF/Office解析MCP)の初回実装とクラウドネイティブ対応 | 2025-11-10 |
| #54 | Hisakata Matsumoto | LangSmith integration with MCP server | 2025-11-14 |
| #55 | ebase-tsujimoto | PDF解析エージェントのLangSmith統合と評価フレームワーク実装 | 2025-12-03 |

---

## 3. ebase-portal-chat — eBASE-Moriの成果

### PR一覧（時系列）

| PR | タイトル | マージ日 | 追加 | 削除 |
|----|---------|---------|------|------|
| #15 | fix: Tailwind CSS 4.x とのpadding競合を解消 | 2025-11-04 | +0 | -6 |
| #19 | feat: メッセージコンポーネント群を実装（ChatAnswerButton, ChatThinkingButton, Button） | 2025-11-13 | +469 | -31 |
| #22 | feat: Figma準拠のGreeting/ToastSuccess/PresetButtonコンポーネント実装 | 2025-11-19 | +977 | -94 |
| #23 | feat: Tailwind CSS 4.x移行とFigmaのデザインカラーの追加 | 2025-11-17 | +57 | -74 |
| #32 | feat: AttachmentListのコンポーネント群を追加 | 2025-12-12 | +5,970 | -2,852 |
| #35 | fix: セキュリティ脆弱性対応とNext.js/Reactバージョン更新 | 2025-12-08 | +897 | -4,589 |
| #55 | feat: チャットUIコンポーネント追加（ChatAgentIcon, ChatLoadingIcon, ScrollToBottomButton） | 2025-12-17 | +716 | -9 |
| #57 | refactor: chat コンポーネントの各フォルダに index.ts を追加してエクスポート統一 | 2025-12-17 | +48 | -31 |
| #61 | feat: ChatComposer desktop版の作成 | 2025-12-26 | +719 | -126 |

### テーマ別詳細

#### テーマA: チャットUIコンポーネントライブラリ構築
**関連PR**: #19, #22, #32, #55, #61

- **PR #19**: ChatAnswerButton, ChatThinkingButton, Buttonコンポーネント
- **PR #22**: Figma準拠コンポーネント（Greeting, ToastSuccess, PresetButton）
- **PR #32**: AttachmentListコンポーネント群（最大規模のPR、+5,970行）
  - 添付ファイル表示、画像プレビュー機能
  - ファイルバリデーション（MIME type + 拡張子フォールバック）
- **PR #55**: ChatAgentIcon, ChatLoadingIcon, ScrollToBottomButton
- **PR #61**: ChatComposerデスクトップ版

#### テーマB: デザインシステム・Tailwind整備
**関連PR**: #15, #23

- Tailwind CSS 4.x移行に伴うpadding競合解消
- Figmaデザインカラーの追加
- デザイントークンの統一

#### テーマC: セキュリティ脆弱性対応
**関連PR**: #35

- React/Next.js RSC脆弱性（CVE-2025-55182等）への対応
- Next.js/Reactバージョン更新
- 依存パッケージの脆弱性パッチ適用

#### テーマD: リファクタリング
**関連PR**: #57

- chatコンポーネント各フォルダにindex.ts追加
- エクスポート構造の統一化

### 他メンバーの主な成果

| PR | 担当者 | タイトル | マージ日 |
|----|-------|---------|---------|
| #72 | murashige.k | eb-api-mcp MCPサーバー統合とLangChain移行 | 2025-12-26 |
| #30 | Hisakata Matsumoto | LLMエージェント基盤とMCPクライアント機能追加 | 2025-12-04 |
| #64 | ebase-iyanaga | AIチャット返答のMarkdown表示対応 | 2025-12-23 |
| #21 | ebase-iyanaga | Chat Sidebar UIコンポーネント実装 | 2025-12-02 |
| #12 | Hisakata Matsumoto | Storybook v10.0.2導入と自動Story生成ツール整備 | 2025-10-31 |
| #13 | Hisakata Matsumoto | Storybook addon-design と Figma連携対応 | 2025-10-31 |
| #14 | Hisakata Matsumoto | Figma → shadcn/ui 自動変換コマンド追加 | 2025-10-31 |
| #59 | Hisakata Matsumoto | React/Next.js RSC脆弱性（CVE-2025-55182等）対応 | 2025-12-16 |
| #60 | Hisakata Matsumoto | Claude Code GitHub Workflow追加 | 2025-12-17 |

---

## 4. 未解決課題・次Q引き継ぎ

### ebase-middleware-mcp

| Issue | タイトル | 作成日 | 状態 |
|-------|---------|-------|------|
| #50 | 脆弱性対応: eb-api-mcpにセキュリティ対策を実装 | 2025-10-24 | Open |
| #42 | eB-APIの処理をcommonへ切り出し | 2025-10-21 | Open |

**Issue #50 の詳細**:
- 認証機能の実装
- ebase Webセッションバリデーション
- CORS制限（現状 `origin: '*'`）
- Originヘッダーバリデーション（MCP仕様のMUST要件）
- セッションタイムアウト

### ebase-portal-chat

| Issue | タイトル | 作成日 | 状態 |
|-------|---------|-------|------|
| #67 | [test] e2eテストケース追加リスト - 担当者追記用 | 2025-12-23 | Open |
| #49 | design: ロゴデザイン調整 | 2025-12-08 | Open |

---

## 5. 3Qの主要テーマ（eBASE-Mori視点）

1. **MCPサーバーのクラウドネイティブ化**
   - stdioからStreamable HTTPへのトランスポート移行
   - Docker/Kubernetes基盤の構築（Kustomize overlays）
   - 動的接続先設定による柔軟なクライアント対応

2. **チャットUIコンポーネントライブラリの構築**
   - Figmaデザイン準拠のコンポーネント群（9PR、計9,853行追加）
   - 添付ファイル、画像プレビュー、メッセージ表示など主要機能

3. **デザインシステム基盤整備**
   - Tailwind CSS 4.x移行
   - Figmaデザインカラーの組み込み

4. **セキュリティ脆弱性への迅速な対応**
   - CVE-2025-55182（React/Next.js RSC）
   - 依存パッケージの定期的な更新

---

## 6. 担当割合

<!-- TODO: 加筆修正してください -->

### リポジトリ別コミット比率

| リポジトリ | eBASE-Mori | 全体 | 担当割合 |
|-----------|-----------|------|---------|
| ebase-middleware-mcp | 51 | 99 | **51.5%** |
| ebase-portal-chat | 147 | 435 | **33.8%** |
| **合計** | **198** | **534** | **37.1%** |

### 案件全体の担当割合

- **ebase-middleware-mcp**: チームの過半数（51.5%）のコミットを担当。特に10月のリモートMCP移行・K8s基盤構築フェーズではほぼ単独で推進。
- **ebase-portal-chat**: 5名体制の中で2番目（33.8%）の貢献度。UIコンポーネント実装の中心的な役割。
- **マージ済みPR数**: 全体15件。middleware-mcpでは全9件中6件（66.7%）が自分のPR。

---

## 7. アピールしたい点

<!-- TODO: 加筆修正してください -->

- **MCPサーバーのアーキテクチャ変革を主導**: stdioからStreamable HTTPへのトランスポート移行を設計・実装し、複数クライアント同時接続を実現。本番デプロイまでを一貫して担当（PR #39, #43, #48）
- **クラウドネイティブ基盤の構築**: Docker化、Kubernetes マニフェスト整備（Kustomize overlays）、nginx リバースプロキシ構成など、インフラ基盤をゼロから構築（PR #41）
- **動的接続先設定の設計**: HTTPヘッダーベースのConnectionConfig方式を設計し、セッション固有の接続管理と環境変数デフォルトの両立を実現。柔軟なマルチテナント対応の基礎を築いた（PR #43）
- **チャットUIコンポーネントの大量実装**: Figmaデザイン準拠のコンポーネントを9PR・計9,853行にわたって実装。AttachmentList（PR #32）では添付ファイルのバリデーション・画像プレビュー・スクロール機能など複雑なUIを構築
- **セキュリティ脆弱性への迅速な対応**: CVE-2025-55182（React/Next.js RSC脆弱性）の発覚後、即座にバージョン更新と依存パッケージの修正を実施（PR #35）
- **コード品質の改善**: ツール命名規則の統一（eb_api_プレフィクス）、エクスポート構造の整理、READMEとドキュメントの体系的な整備

---

## 8. 苦労したこと・難しかったこと・反省点

<!-- TODO: 加筆修正してください -->

- **AttachmentList（PR #32）の複雑さ**: +5,970行/-2,852行と3Q最大規模のPR。ファイルバリデーション（MIME type + 拡張子フォールバック）、画像プレビュー、添付ファイル一覧UIなど、多くの仕様を一つのPRに含めた結果、レビュー負荷が大きくなった可能性がある
- **セキュリティ脆弱性対応（PR #35）**: -4,589行の大規模な削除を伴うバージョン更新。依存パッケージの互換性確認と破壊的変更への対応が必要だった
- **未解決のセキュリティ課題（Issue #50）**: eb-api-mcpの認証機能（CORS制限、セッションバリデーション、Originヘッダーバリデーション）が未実装のまま3Qを終了。本番運用中のサービスに対するセキュリティリスクが残存
- **eB-APIの共通処理切り出し（Issue #42）**: コードの共通化が進まず、技術的負債として次Qに持ち越し
- **portal-chatのe2eテスト不足（Issue #67）**: コンポーネント実装を優先した結果、テストケースの整備が後回しになっている

---

*調査日: 2026-02-27*
*調査対象期間: 2025年10月1日〜2025年12月31日*
