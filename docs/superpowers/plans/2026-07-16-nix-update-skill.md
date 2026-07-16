# nix-update skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dotfiles の Nix flake を安全に定期更新する Claude Code skill（単一の SKILL.md）を作成する。

**Architecture:** sync-main と同じドキュメント型 skill。「明確なフロー＋実行制限＋AskUserQuestion」構成。決定的処理（警告 grep 検知）と非決定的処理（未知パターンの相談）を分離。成果物は SKILL.md 1 枚。

**Tech Stack:** Markdown（SKILL.md frontmatter 形式）、bash（nix flake update / home-manager switch）、Home Manager / Nix。

## Global Constraints

- 配置先: `~/.dotfiles/.claude-global/skills/nix-update/SKILL.md`（`~/.claude/skills/` は symlink で自動反映）
- frontmatter: `name: nix-update` / `allowed-tools: Read, Edit, Bash, AskUserQuestion` / `version: 1.0.0`
- 更新粒度: 全 input 一括（`nix flake update` 引数なし）
- 対象は `/home/aya/.dotfiles` のみ。範囲外: 個別ツール更新・Windows(chezmoi)・overlay
- 前進解決の修正は必ずユーザー承認後に実行。`--force` 等の強制 git 操作は禁止
- 手本: `.claude-global/skills/sync-main/SKILL.md`
- ドキュメント型 skill のため自動テストは無い。検証は frontmatter 妥当性・bash コマンド構文・既知パターン辞書の網羅で行う

---

### Task 1: SKILL.md 本体の作成

**Files:**
- Create: `~/.dotfiles/.claude-global/skills/nix-update/SKILL.md`
- Reference: `~/.dotfiles/.claude-global/skills/sync-main/SKILL.md`（構成の手本）
- Reference: `~/.dotfiles/docs/superpowers/specs/2026-07-16-nix-update-skill-design.md`（設計）

**Interfaces:**
- Consumes: なし（新規 skill）
- Produces: `/nix-update` で起動可能な skill。フロー①〜⑤・既知パターン辞書・実行制限・出力形式を含む

- [ ] **Step 1: 手本と設計を読む**

Read `~/.dotfiles/.claude-global/skills/sync-main/SKILL.md`（frontmatter・実行制限・実行フロー・出力形式・エラー処理の構成パターンを把握）。
Read 設計 doc 全文で最新のフロー・辞書内容を確認。

- [ ] **Step 2: frontmatter を書く**

```yaml
---
name: nix-update
description: dotfilesのNix flake（nixpkgs/home-manager等）を安全に定期更新する。「nixpkgs更新」「flake update」「/nix-update」で起動。
allowed-tools: Read, Edit, Bash, AskUserQuestion
version: 1.0.0
---
```

- [ ] **Step 3: 「作業指示」「実行制限」節を書く**

sync-main に倣う。要点:
- このスキルは全ツールのバージョンを一斉に動かす操作。影響範囲が大きいため各ステップで状態確認しユーザーに選択肢を提供する。
- 実行すること: git状態確認 / `nix flake update` / `home-manager switch` / 警告検知 / 前進解決の修正（承認後）/ コミット・push
- 禁止事項: ユーザー承認なしのファイル修正・強制 git 操作(`--force`)・対象 dotfiles 外のファイル操作

- [ ] **Step 4: 「実行フロー」節を書く（①〜⑤）**

各ステップに実行する bash を明記する。

```bash
# ① 事前確認: 戻り先rev記録・git状態
cd /home/aya/.dotfiles
rm -f .git/index.lock
git status
git remote -v            # CLAUDE.mdルール: ツール選択のため確認
nix flake metadata 2>/dev/null | grep -iE "nixpkgs|Last modified"   # 現rev=戻り先を記録・表示
```

dirty の場合は AskUserQuestion で「stash / 続行 / 中止」を確認。

```bash
# ② 全input一括update → 差分表示（前rev→新rev）
rm -f .git/index.lock
nix flake update 2>&1    # 出力に "Updated input 'X': 旧rev(日付) → 新rev(日付)" が出る。これを差分として提示
```

```bash
# ③ ビルド反映
home-manager switch --flake . 2>&1 | tee /tmp/nix-update-switch.log
```

④ 検証は次 Step で詳述。⑤ コミットは:

```bash
# ⑤ 修正内容に合わせて適切にコミット（更新のみなら chore(flake):）
rm -f .git/index.lock
git add flake.lock       # 前進解決で他ファイルを触った場合はそれも適切に分割して add
rm -f .git/index.lock
git commit -m "chore(flake): nixpkgs等を定期更新（<主要input>を<旧日付>→<新日付>）"
rm -f .git/index.lock
git push
```

- [ ] **Step 5: 「④検証と前進解決モード」節を書く（心臓部）**

検証（決定的処理）:

```bash
# switch出力から警告を検知
grep -iE "mismatched versions|undefined variable|has been renamed|^error:" /tmp/nix-update-switch.log
```

前進解決の既知パターン辞書（表形式）を記載:

| 検知パターン | 診断 | 修正案（承認後実行） |
|---|---|---|
| `mismatched versions` | HM input が古い | `nix flake update home-manager` → re-switch |
| `undefined variable 'X'` | pkg名変更/削除 or pin未到達 | `nix eval --raw nixpkgs#X.pname` 等で確認 → 改名 or 一時除外を提案 |
| `has been renamed` (option A→B) | HM/nixpkgs のオプション改名 | 該当 nix ファイルの修正 diff を提示 |
| その他 `error:` | 個別 | `nix log <drv>` で深掘り → 原因と対処を提示 |

未知フォールバック: 辞書に無い警告は診断情報（警告全文＋関連ログ）を集めて提示し、対処はユーザーと相談。

ループ防止: 「修正→re-switch→再検証」で同一警告が 2 回続けて解消しない場合は前進解決を諦め rollback 提案へ。

rollback（最終手段）を AskUserQuestion で提示:
- 未commit時: `git checkout flake.lock`（全ツールが元revに揃って戻る）
- switch済み: `home-manager generations` から前世代へ戻す

- [ ] **Step 6: 「出力形式」節を書く**

成功時サマリの markdown テンプレートを記載:
- 更新された input 一覧（前rev/日付 → 新rev/日付）
- 検証結果（switch成否・警告有無）
- 前進解決を行った場合その内容
- コミット情報（ハッシュ・メッセージ）

前進解決時・rollback時のテンプレートも用意（sync-main のエラー処理節に倣う）。

- [ ] **Step 7: 検証 — frontmatter とコマンド構文**

Run:
```bash
head -6 ~/.dotfiles/.claude-global/skills/nix-update/SKILL.md   # frontmatterにname/description/allowed-tools/versionが揃う
bash -n <(grep -A20 '```bash' ~/.dotfiles/.claude-global/skills/nix-update/SKILL.md | grep -v '```')  # bashブロックの構文チェック（可能な範囲で）
```
Expected: frontmatter 4 フィールド確認。構文エラーが出ないこと。

- [ ] **Step 8: 検証 — 設計 spec の全要件が SKILL.md に反映されているか**

設計 doc の各節（フロー①〜⑤・検証・既知辞書4パターン・未知フォールバック・ループ防止・rollback・実行制限・出力形式）を SKILL.md と突き合わせ、抜けが無いことを確認。抜けがあれば該当 Step に戻って追記。

- [ ] **Step 9: skill がロードされるか実起動確認**

`/nix-update` を起動し、skill 本体（SKILL.md の内容）がコンテキストに読み込まれることを確認する（flake が既に最新でもフロー説明が破綻しないこと）。
※ 実際の `nix flake update` 実行までは行わず、ロードとフロー提示の確認に留める。

- [ ] **Step 10: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add .claude-global/skills/nix-update/SKILL.md
rm -f .git/index.lock
git commit -m "feat(nix-update): nixpkgs定期更新skillを追加"
rm -f .git/index.lock
git push
```

---

## Self-Review

**1. Spec coverage:**
- フロー①〜⑤ → Step 4 ✅
- ④検証（警告grep） → Step 5 ✅
- 既知パターン辞書4種 → Step 5 ✅
- 未知フォールバック → Step 5 ✅
- ループ防止 → Step 5 ✅
- rollback（2方式） → Step 5 ✅
- frontmatter/配置 → Step 2, Global Constraints ✅
- 実行制限 → Step 3 ✅
- 出力形式 → Step 6 ✅
- テスト方針（frontmatter/構文/網羅） → Step 7, 8 ✅
ギャップ無し。

**2. Placeholder scan:** 各 Step に実コマンド・実 frontmatter を記載済み。`<主要input>` 等はskill出力時に埋める動的値で、プレースホルダではなくテンプレート変数（意図的）。

**3. Type consistency:** 単一ドキュメントのため型整合の懸念なし。ファイルパス・skill名（nix-update）は全 Step で一貫。
