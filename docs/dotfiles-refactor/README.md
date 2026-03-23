# dotfiles 改善ロードマップ

## 概要

2026年3月の調査で判明した改善点を5フェーズに分けて順次実施する計画。
各フェーズは独立して実施し、完了後にコミット・プッシュする。

## フェーズ一覧

| # | ファイル | 領域 | 優先度 | 状態 |
|---|---|---|---|---|
| 1 | [phase1-cleanup.md](./phase1-cleanup.md) | 不要ファイル削除 | 高 | 未着手 |
| 2 | [phase2-shell-quality.md](./phase2-shell-quality.md) | Shell/スクリプト品質 | 高 | 未着手 |
| 3 | [phase3-neovim.md](./phase3-neovim.md) | Neovim設定改善 | 中 | 未着手 |
| 4 | [phase4-nix.md](./phase4-nix.md) | Nix/Home Manager最適化 | 中 | 未着手 |
| 5 | [phase5-refactor.md](./phase5-refactor.md) | 総合リファクタリング | 低 | 未着手 |

## 実施方針

- 各フェーズは順番に実施（Phase 1 → 2 → 3 → 4 → 5）
- 各フェーズ完了後にコミット・プッシュ
- Phase 4, 5 は影響範囲が大きいため慎重に実施

## 前提条件

Phase 1 実施前に、以下の未コミット変更を先にコミット・プッシュすること：
- `.claude-global/CLAUDE.md`
- `.claude-global/settings.json`

## 調査時の判断メモ

- `vim-auto-save` の snacks.nvim 移行は複雑なため、今回スコープ外。
  → GitHub Issue に上げて別タスクで検討する
- `markdown.lua` と `render-markdown.nvim` の重複は存在しなかった（ファイル名が紛らわしいだけ）
