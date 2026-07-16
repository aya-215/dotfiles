# nix-update skill 設計

作成日: 2026-07-16

## 目的

dotfiles（Nix / Home Manager）の flake input（nixpkgs / home-manager / glauncher 等）を
**安全に定期更新する**ための Claude Code skill。

2026-07-16 の hunk 導入作業で手作業で行った
「`nix flake update` → `home-manager switch` → 動作検証」の流れを型化する。

## 背景と設計上の前提

Nix のバージョン固定は 2 層構造:

| 層 | 固定対象 |
|---|---|
| flake.lock | nixpkgs 全体を特定 rev に釘付け |
| 各パッケージ | その rev 内で決まったバージョン |

`nix flake update` するまで**全ツールが同じバージョンのまま**動かない。
逆に更新すると **nixpkgs rev 配下の全ツールが一斉にバージョン変動する**（個別更新は不可）。
そのため:

- 一度の更新の影響範囲が大きい → **検証が重要**
- 固定されているからこそ「定期的に意図的に動かす」価値がある → skill 化の意義
- flake.lock を戻せば全ツールが揃って元に戻る → **rollback が効く前提**

個別ツールだけ上げたいニーズ（input 分離 / overlay）は本 skill の範囲外。

## スコープ

- **対象**: `/home/aya/.dotfiles` の flake（Nix / Home Manager 環境）
- **範囲外**: 個別ツールのみの更新、Windows(chezmoi)側、overlay 追加

## フロー

```
① 事前確認   : git状態・カレントブランチ確認。現flake.lockのrev（＝戻り先）を記録・表示。
               dirtyなら退避 or 続行を確認。
② 更新       : nix flake update（全input一括）→ lock差分を表示（前rev→新rev、日付付き）。
③ ビルド反映 : home-manager switch --flake .
④ 検証       : switch成否 + 警告grep検知。
      ├─ OK  → ⑤へ
      └─ NG  → 【前進解決モード】原因診断 → 修正案を提示して停止
                                        → 承認後に修正を実行 → ④へ戻る
               （前進で解決不能なら最終手段として rollback を提案）
⑤ コミット   : 修正内容に合わせて適切にコミット（更新のみなら chore(flake):）→ push。
```

更新の粒度は **全 input 一括**（`nix flake update` 引数なし）。
home-manager は nixpkgs.follows なので一括更新で整合が取れ、バージョン不一致を予防できる。
glauncher は自作 input のため一括更新に含めて問題ない。

## ④ 検証と前進解決モード（skill の心臓部）

### 検証で見るもの（決定的処理）

1. `home-manager switch` の exit code（ビルド失敗＝即 NG）
2. switch 出力の警告 grep:
   - `mismatched versions`（HM/nixpkgs 不一致）
   - `undefined variable`（bump で消えた/未到達のパッケージ）
   - `has been renamed`（オプションのリネーム）
   - `error:` 全般

### 前進解決の診断→修正案（承認後に実行）

**既知パターン辞書:**

| 検知パターン | 診断 | 提示する修正案 |
|---|---|---|
| HM/nixpkgs 不一致 | HM input が古い | `nix flake update home-manager` → re-switch |
| `undefined variable 'X'` | pkg 名変更/削除 or pin 未到達 | 該当 pkg を nixpkgs 検索して改名 or 一時除外を提案 |
| `option renamed A→B` | HM/nixpkgs のオプション改名 | 該当 nix ファイルの修正 diff を提示 |
| その他 `error:` | 個別 | `nix log` 等で深掘り → 原因と対処を提示 |

**未知フォールバック（LLM 補助層）:**
辞書に無い警告は「診断情報（警告全文＋関連ログ）を集めて提示、対処はユーザーと相談」。

**ループ防止:**
「修正 → re-switch → ④再検証」のループは同一警告が 2 回続けて解消しない場合は停止し、
前進解決を諦めて rollback 提案へ移る（無限ループを避ける）。

> 決定的処理（警告 grep 検知）と非決定的処理（未知パターンの相談）を分離する設計。
> 既知は速く、未知も安全にカバーする。

### rollback（最終手段）

前進で解決できないときのみ選択肢として提示:
- 未 commit 時: `git checkout flake.lock`（更新自体を破棄。全ツールが元 rev に揃って戻る）
- switch 済み: `home-manager generations` から前世代へ戻す

## skill メタ情報・配置

**配置**: `~/.dotfiles/.claude-global/skills/nix-update/SKILL.md`
（`~/.claude/skills/` は symlink で自動的に見える）

**frontmatter**:
```yaml
---
name: nix-update
description: dotfilesのNix flake（nixpkgs/home-manager等）を安全に定期更新する。「nixpkgs更新」「flake update」「/nix-update」で起動。
allowed-tools: Read, Edit, Bash, AskUserQuestion
version: 1.0.0
---
```

**起動トリガー**: `/nix-update`、「nixpkgs更新して」「flake更新」「定期更新」等

## 実行制限（禁止事項）

sync-main スタイルで明記:
- ユーザー承認なしのファイル修正（前進解決の修正は必ず承認後）
- `--force` 等の強制 git 操作
- 対象 dotfiles 外のファイル操作

## 出力形式

更新結果サマリを markdown で:
- 更新された input 一覧（前 rev/日付 → 新 rev/日付）
- 検証結果（switch 成否・警告有無）
- 前進解決を行った場合はその内容
- コミット情報（ハッシュ・メッセージ）

## テスト方針

skill はドキュメント（手順書）のため自動テストは無い。検証は:
- frontmatter の妥当性（name/description/allowed-tools）
- 実際に `/nix-update` を起動し、flake が既に最新な状態でフローが破綻しないこと
- 既知パターン辞書の各コマンドが構文的に正しいこと（実行はuser環境依存）
