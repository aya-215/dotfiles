# 学習済みルール（retrospective昇格）

retrospective学習機構（`/retrospective` スキル）で pain_count / success_count が閾値（3）に達し、ユーザー承認を経て昇格したルール。`rules/` 配下のため全セッションに自動で読み込まれる。

- 由来: `.claude-global/skills/agent-memory/memories/feedback/` の各feedbackメモリ（`promoted_to: rules`）
- 形式: 1ルール = `##` 見出し + 本文数行 + 由来feedbackファイル名
- 手動編集可。ルールを削除する場合は由来feedbackの `promoted_to` を `null` に戻すこと

<!-- ルールはこの下に追記される -->

## 説明は論点を一覧にしてから1件ずつ出す

説明が長い・一度に論点を詰め込むと読み手は判断できない。先に論点の一覧だけを短く提示し、
どれから見るかを決めてもらってから1件ずつ掘ること。前置き・言い換え・段階的な補足を重ねない。

由来: `feedback/explanation-too-long-and-crammed.md`（pain_count: 7 / 昇格日: 2026-08-21）

## 「意図的な判断」は尊重の理由にならない

「作者が意図的にそう書いた」「レビュアーがそう指摘した」を、それ自体で正当性の根拠として扱わないこと。意図の存在と根拠の妥当性は別問題であり、その理由づけが対象の実際の用途・実データに照らして成立するかを一次情報で検証すること。PRのコメント履歴は時系列で追い、理由づけが途中で修正・撤回されていないか確認すること。

由来: `feedback/question-stated-intent-not-just-respect-it.md`（pain_count: 3 / 昇格日: 2026-07-27）

## 前提は実データで検証してから判断する

設計書・引き継ぎメモ・レビュー所見の前提を鵜呑みにせず、実機・実データ・一次情報（本体コード・DB・実API挙動）で検証してから判断すること。レビュー指摘やバグ疑いは、修正前に CONFIRMED / PLAUSIBLE / REFUTED に分類すること。引き継ぎメモからの再開時は、中断地点をそのまま信じず現状を再確認すること。

由来: `feedback/verify-assumptions-with-real-data.md`（success_count: 8 / 昇格日: 2026-07-02）

## 決定的な処理と非決定的な処理を分離する

機械的に判定・保証できる処理（バリデーション・採番・パス判定・ガード）は決定的なコードとして実装し、LLM・プロンプト指示は確率的な補助層として分離すること。LLMへの指示だけを障害対策・安全対策としないこと。モジュールやスキルの責務は軸が直交するように分け、二重管理を避けること。

由来: `feedback/separate-deterministic-from-nondeterministic.md`（success_count: 4 / 昇格日: 2026-07-02）
