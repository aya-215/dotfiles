# 学習済みルール（retrospective昇格）

retrospective学習機構（`/retrospective` スキル）で pain_count / success_count が閾値（3）に達し、ユーザー承認を経て昇格したルール。`rules/` 配下のため全セッションに自動で読み込まれる。

- 由来: `.claude-global/skills/agent-memory/memories/feedback/` の各feedbackメモリ（`promoted_to: rules`）
- 形式: 1ルール = `##` 見出し + 本文数行 + 由来feedbackファイル名
- 手動編集可。ルールを削除する場合は由来feedbackの `promoted_to` を `null` に戻すこと

<!-- ルールはこの下に追記される -->
