# WSL Guard - 設計書

## プロジェクト概要

**目的：** WSL環境でのClaude Codeセッションを監視・管理するCLIツール

**ターゲットユーザー：** WSLでClaude Codeを頻繁に使う開発者（自分自身）

**主な課題解決：**
- Claude Codeを複数起動してWSLが重くなる問題
- どのディレクトリでどのセッションが動いているか分からない
- メモリ使用量の把握が面倒

---

## 機能要件（v1.0）

### 必須機能

1. **Claude Codeプロセス監視**
   - PID検出
   - メモリ使用量（GB表示）
   - CPU使用率
   - 作業ディレクトリ（`/proc/[pid]/cwd`から取得）

2. **TUIリアルタイム表示**
   - 1秒ごとに自動更新
   - メモリ使用量降順でソート
   - 全体のメモリ使用状況表示

3. **メモリ警告**
   - 5GB超過時に色変更（赤色表示）
   - TUI上での視覚的な警告のみ

4. **WezTerm連携**
   - セッション選択（↑↓キー）
   - Enterキーで選択したディレクトリを新しいWezTermタブで開く
   - `wezterm cli spawn --cwd <directory>` を使用

5. **セッション履歴管理**
   - SQLiteで永続化
   - セッションの開始/終了時刻記録
   - メモリ/CPU使用量の履歴

6. **設定ファイル**
   - TOML形式
   - 更新間隔、メモリ閾値、表示項目などを設定可能
   - パス：`~/.config/wsl-guard/config.toml`

7. **kill機能**
   - 選択したセッションの終了
   - 確認ダイアログ付き
   - SIGTERM → 3秒待機 → SIGKILL

---

## 非機能要件

### パフォーマンス
- 起動時間：1秒以内
- メモリ使用量：10MB以下
- CPU使用率：通常時1%以下

### 信頼性
- プロセス情報取得の失敗時も続行
- 権限不足時の適切なエラーメッセージ

### 保守性
- 開発時は詳細なログ出力
- モジュール分割で拡張しやすい設計

---

## 技術スタック

### 言語・フレームワーク
- **Rust** - システムプログラミング、高速、安全性

### 主要ライブラリ
- **ratatui** - TUI（Terminal User Interface）
- **crossterm** - クロスプラットフォームのターミナル操作
- **rusqlite** - SQLite データベース
- **serde / toml** - 設定ファイル読み込み
- **anyhow / thiserror** - エラーハンドリング
- **log / env_logger** - ロギング
- **sysinfo** - システム情報取得（プロセス、メモリ）

---

## データ設計

### SQLiteスキーマ

```sql
-- セッションテーブル
CREATE TABLE sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pid INTEGER NOT NULL,
    cwd TEXT NOT NULL,
    start_time INTEGER NOT NULL,  -- Unix timestamp
    end_time INTEGER,              -- NULL = 実行中
    peak_memory INTEGER,           -- bytes
    avg_cpu REAL
);

-- メトリクステーブル（詳細な履歴）
CREATE TABLE metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    timestamp INTEGER NOT NULL,
    memory INTEGER NOT NULL,       -- bytes
    cpu REAL NOT NULL,
    FOREIGN KEY(session_id) REFERENCES sessions(id)
);

-- インデックス
CREATE INDEX idx_sessions_pid ON sessions(pid);
CREATE INDEX idx_metrics_session_time ON metrics(session_id, timestamp);
```

**保存場所：** `~/.local/share/wsl-guard/sessions.db`

### 設定ファイル（TOML）

```toml
# ~/.config/wsl-guard/config.toml

[general]
update_interval = 1  # 更新間隔（秒）
database_path = "~/.local/share/wsl-guard/sessions.db"

[thresholds]
memory_warning_gb = 5.0  # メモリ警告閾値（GB）

[display]
show_cpu = true          # CPU使用率表示
show_start_time = true   # 起動時刻表示
show_pid = true          # PID表示
memory_unit = "auto"     # メモリ単位: "GB", "MB", "auto"

[logging]
level = "debug"  # ログレベル: "debug", "info", "warn", "error"
```

---

## UI設計

### TUI画面レイアウト

```
┌─────────────────────────────────────────────────────────────────┐
│ WSL Guard - Claude Code Monitor                                │
├─────────────────────────────────────────────────────────────────┤
│ System Memory: 8.2GB / 16GB [████████░░░░░░░░] 51%            │
│ CPU Usage: 45%                                                  │
├─────────────────────────────────────────────────────────────────┤
│ Claude Code Sessions (3 active)                                │
├─────────────────────────────────────────────────────────────────┤
│ > PID     Memory    CPU    Uptime   Working Directory          │
│   12345   1.2GB     12%    2h 15m   ~/projects/ebase-catalog   │
│   12389   890MB      3%    45m      ~/projects/ai-portal       │
│   12401   2.1GB     25%    1h 30m   ~/dotfiles                 │
├─────────────────────────────────────────────────────────────────┤
│ [↑↓] Select  [Enter] Open tab  [k] Kill  [r] Refresh  [q] Quit│
└─────────────────────────────────────────────────────────────────┘
```

### キーバインド

| キー | 機能 |
|------|------|
| `↑` / `k` | 上のセッションを選択 |
| `↓` / `j` | 下のセッションを選択 |
| `Enter` | 選択したディレクトリをWezTermタブで開く |
| `k` | 選択したセッションをkill（確認あり） |
| `r` | 手動更新 |
| `q` / `Esc` | 終了 |

### 色分け

- **通常：** 白/グレー
- **選択中：** 青（ハイライト）
- **メモリ警告（5GB超）：** 赤
- **システム情報：** シアン

---

## ディレクトリ構造

```
wsl-guard/
├── Cargo.toml
├── Cargo.lock
├── README.md
├── LICENSE
├── .gitignore
├── src/
│   ├── main.rs           # エントリーポイント
│   ├── config.rs         # 設定ファイル管理
│   ├── session.rs        # セッション情報取得
│   ├── db.rs             # データベース操作
│   ├── ui.rs             # TUI描画
│   └── wezterm.rs        # WezTerm連携
├── tests/
│   └── integration_test.rs
└── docs/
    └── DESIGN.md         # この設計書
```

---

## 実装計画

### フェーズ1：基本機能（1-2週間）
- [ ] プロジェクトセットアップ（Cargo.toml、依存関係）
- [ ] Claude Codeプロセス検出機能
- [ ] メモリ/CPU情報取得
- [ ] 作業ディレクトリ取得（`/proc/[pid]/cwd`）
- [ ] シンプルなコンソール出力（TUIなし）

### フェーズ2：TUI実装（1週間）
- [ ] `ratatui`でTUI画面作成
- [ ] リアルタイム更新（1秒間隔）
- [ ] キーボード操作（↑↓選択、q終了）
- [ ] メモリ警告の色表示

### フェーズ3：WezTerm連携（3-5日）
- [ ] Enterキーで新しいタブを開く機能
- [ ] `wezterm cli spawn`の実行
- [ ] エラーハンドリング（WezTermが起動していない場合など）

### フェーズ4：データ永続化（3-5日）
- [ ] SQLiteデータベース設計
- [ ] セッション開始/終了の記録
- [ ] メトリクス履歴の記録
- [ ] データベースマイグレーション

### フェーズ5：設定ファイル（2-3日）
- [ ] TOML設定ファイルの読み込み
- [ ] デフォルト設定の適用
- [ ] 設定バリデーション

### フェーズ6：kill機能・仕上げ（3-5日）
- [ ] セッションkill機能
- [ ] 確認ダイアログ
- [ ] エラーハンドリングの強化
- [ ] ログ出力の整備
- [ ] README・ドキュメント作成

**合計見積もり：3-4週間**

---

## 将来的な拡張機能（v2.0以降）

### 優先度：高
- WezTerm Pane IDを記録して既存タブにジャンプ
- 段階的なメモリ警告（黄色4GB、赤5GB）
- CPU使用率の警告
- ソート順の切り替え（メモリ/CPU/時間）

### 優先度：中
- セッションのフィルタ機能（ディレクトリ名で絞り込み）
- 応答待ち時間の推定（CPU低 + ネットワーク待ち検出）
- 統計情報の表示（累計稼働時間、平均メモリなど）
- プロジェクト名の短縮表示（`~/ghq/github.com/user/repo` → `user/repo`）

### 優先度：低
- 他の開発ツールの監視（Neovim、LSPなど）
- システム通知（`notify-send`）
- グラフ表示（メモリ推移の可視化）
- Web UIでの統計閲覧

---

## リスクと対策

### 技術的リスク

| リスク | 影響 | 対策 |
|--------|------|------|
| `/proc`へのアクセス権限不足 | 中 | エラーメッセージで案内、sudoの提案 |
| Claude Codeプロセス名の変更 | 高 | プロセス名を設定ファイルで変更可能に |
| WezTermのバージョン互換性 | 中 | 最小バージョンを明記、エラー時に案内 |
| メモリ計算の精度 | 低 | sysinfoライブラリに依存、テストで検証 |

### スケジュールリスク

| リスク | 影響 | 対策 |
|--------|------|------|
| Rust学習コスト | 高 | シンプルな機能から段階的に実装 |
| TUIライブラリの学習 | 中 | ratatuiの公式サンプルを参考に |
| 想定外のバグ | 中 | テストを書きながら開発 |

---

## 開発環境

### 必要なツール
- Rust（最新安定版）
- WezTerm
- WSL2（Ubuntu推奨）
- SQLite3（動作確認用）

### 推奨VSCode拡張
- rust-analyzer
- crates（依存関係管理）
- Even Better TOML

### テスト環境
- 本番：WSL2（自分の環境）
- CI：GitHub Actions（後で追加）

---

## 成功指標

### v1.0リリース時
- [ ] 自分が毎日使っている
- [ ] メモリ5GB超過を確実に検出できる
- [ ] WezTermタブジャンプが機能する
- [ ] 起動時間1秒以内
- [ ] クラッシュせず安定動作

### 長期的な目標
- GitHub Starを獲得（目標：50+）
- 他のWSL + Claude Codeユーザーにも使ってもらう
- 技術ブログ記事を書く
- 転職時のポートフォリオとして活用

---

## 参考資料

### ライブラリドキュメント
- [ratatui](https://ratatui.rs/)
- [sysinfo](https://docs.rs/sysinfo/)
- [rusqlite](https://docs.rs/rusqlite/)

### 参考プロジェクト
- [bottom](https://github.com/ClementTsang/bottom) - システムモニタ
- [htop](https://htop.dev/) - プロセスビューア

---

**最終更新：** 2026-01-28  
**バージョン：** v0.1.0（設計段階）
