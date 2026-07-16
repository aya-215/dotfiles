# hunk連携レビュー skill 設計書

作成日: 2026-07-16

## 背景・目的

[hunk](https://github.com/modem-dev/hunk)（review-first ターミナルdiffビューア）を
dotfiles環境に導入済み（`modules/hunk.nix`、bun wrapper版）。hunkは
`hunk session *` CLIを通じて、ユーザーが開いた生きたTUIセッションに
Claude Codeが接続し、ナビゲート・コメント追加できる「エージェント連携」機能を持つ。

この連携を日常的に使うため、以下2つのskillを整備する:

1. **`/hunk-review`（新規）** — 任意のdiff（作業ツリー・commit・ブランチ間）を
   hunk連携でレビューする汎用入口
2. **`review-pr`（改訂 v1.3.0→v1.4.0）** — 既存のPR対話レビューフローに、
   hunkでの視覚レビューをオプションレイヤーとして追加

## 設計思想（hunk公式に忠実）

hunkバンドルskill（`hunk-review/SKILL.md`）が定める大原則を厳守する:

> The TUI is for the user — do NOT run `hunk diff`, `hunk show` directly.
> If no session exists, ask the user to launch Hunk first.

**TUIを開くのは常にユーザー。** Claudeは絶対に `hunk diff` / `hunk show` を
自分で実行しない（実行してもClaudeのbashプロセス内で起動し、ユーザーの端末に
映らず、non-TTYで無意味になる）。Claudeの役割は `hunk session *` で
既存セッションに接続し、レビューを先導すること。

## 全体構成

```
.claude-global/skills/
├── review-pr/
│   ├── SKILL.md              # 既存 → hunk連携をオプション追加してv1.4.0へ
│   └── references/
│       └── hunk-session.md   # 【新規・共通】hunk session連携の手順リファレンス
└── hunk-review/              # 【新規】汎用ラッパーskill
    └── SKILL.md
```

共通の連携ロジックは `references/hunk-session.md` に一元化し、両skillから参照する
（二重管理を避ける — learned-rule「決定的処理の分離」「二重管理回避」に準拠）。

## コンポーネント①: references/hunk-session.md（共通リファレンス）

両skillの「実装層」。実地検証で確認した内容を収録する。

### A. 接続フロー（最重要ガード）

- **Claudeは絶対に `hunk diff` / `hunk show` を自分で実行しない**
- `hunk session list --json` でセッション確認
- 無ければ **ユーザーに開き方を案内して待つ**（コマンド文字列は提示、Enterはユーザー）:
  - PRブランチ: 「`hunk diff <base>...HEAD` を自分の端末で開いてな」
  - dotfiles環境では `! hunk diff ...`（`!`プレフィックスでこのセッション内実行）も選択肢
  - リモートPRのみ閲覧: `gh pr diff | hunk pager`
- 「開いたで」と言われたら `session list` で接続
- 複数セッション → `<session-id>` 明示。単一 → 自動解決

### B. 構造把握

- `hunk session review --repo . --json` → **`review` キー配下にネスト**、
  `files[].hunks[]` で構造（`hunkCount`, `additions`, `deletions`）
- patchは `--include-patch` で必要時のみ（`files[].patch` に入る。トップの
  `patch` フィールドではなくファイル単位）

### C. ナビゲート（実演で確認した4パターン）

- `--hunk N`（1始まり）/ `--new-line N` / `--old-line N` は **どれか1つだけ**
  （同時指定はエラー「Specify exactly one navigation target」）
- `--file` は絶対ナビ時に必須
- `--next-comment` / `--prev-comment` は `--file` 不要、注釈付きhunkを渡り歩く
  （レビュー先導に有効。両方同時指定は不可）

### D. コメント

- **読取スキーマがsource別に異なる（実地の罠）**:
  - userコメント: `body` キー（`newRange`, `source: "user"`, `noteId`, `editable`）
  - agentコメント: `summary` + `rationale` キー（`line`, `side`, `commentId`, `author`）
- `comment list --type user|ai|agent|all|live`
- 追加: `comment add`（単発、`--file` + `--summary` + `--old-line`/`--new-line`のどれか1つ必須）
- 一括: `comment apply --stdin`（JSON batch。payload各itemに `filePath` + `summary` +
  ターゲット1つ `hunk`/`hunkNumber`/`oldLine`/`newLine`）
- `--focus` で追加箇所へ画面も飛ばす
- **コメントを付けたら必ずユーザーに報告する**

### E. 承認ガード

| 操作 | 扱い |
|---|---|
| `navigate`（画面移動） | 自由に実行（確認不要） |
| `comment add` / `comment apply` | 実行してよいが、付けた内容を必ず報告 |
| `comment clear` / `comment rm`（破壊的） | 実行前にAskUserQuestionで承認必須 |

### F. ブランチ間差分の開き方（ユーザーに案内する内容）

`hunk diff` は `git diff` と同じ構文でtargetを取る:

| 目的 | コマンド |
|---|---|
| mainとの差分（2点） | `hunk diff main` |
| ブランチの変更だけ（3点、PR相当）🌟 | `hunk diff main...HEAD` |
| 2ブランチ比較 | `hunk diff main feature` |
| ステージ済み | `hunk diff --staged` |
| ファイル絞り込み | `hunk diff main -- src/` |

PR相当の「自分が足した変更だけ」を見たいなら3点ドット `main...HEAD`。

### G. 既知エラー（hunk公式Common errors準拠）

- 「No active Hunk sessions」→ hunkが見えてるのに出るならサンドボックスのlocalhost
  ブロック疑い（ただしこの環境では未発生を実地確認済み）。でなければユーザーに開いてもらう
- 「Multiple active sessions match」→ `<session-id>` 明示
- 「No visible diff file matches」→ 対象ファイルが未ロード。`context` 確認 → `reload`
- 古いゾンビセッションが残る場合: `session list` のpidで生存確認して見分ける

## コンポーネント②: hunk-review/SKILL.md（新規・汎用ラッパー）

```yaml
---
name: hunk-review
description: Use when the user wants to review any diff (working tree, commit, branch) interactively via a live Hunk TUI session. Triggers on "/hunk-review", "hunkでレビュー", "hunkで見て", "この差分をhunkで".
allowed-tools: Bash, Read, Grep, AskUserQuestion
version: 1.0.0
---
```

**フロー（軽量。review-prのような厳格なフェーズ制は持たない）**:

1. `references/hunk-session.md` を読む（連携手順の実体）
2. `hunk session list` で接続 → 無ければ開き方を案内して待つ
3. `session review` で構造把握
4. ユーザーの関心に沿って `navigate` + `comment` でレビュー先導
5. 破壊的操作は承認ガード

**位置づけ**: 「hunkが開いてる → 一緒に見る」の軽い汎用ツール。PR文脈に限定しない。

## コンポーネント③: review-pr/SKILL.md（改訂 v1.3.0→v1.4.0）

**方針: 既存の6ステップ対話フローを一切壊さない。** hunk連携を
オプションの視覚レイヤーとして足すだけ。

**追加箇所**:

- **Step 1（PR情報取得）の直後**に「hunk連携するか？」の分岐を1つ追加:
  - する → ユーザーに `hunk diff <base>...HEAD` を開いてもらい（案内のみ、実行はユーザー）、
    以降のStep 2〜5で設計判断を説明するたびに該当hunkへ `navigate` + 所見を `comment`
  - しない → 従来通りテキストベースで進行（**デフォルト**）
- 連携手順は `references/hunk-session.md` を参照

**維持するもの（壊さない保証）**:

- Iron Law（理解確認なしに次フェーズへ進まない）
- 検証ガード（CONFIRMED / PLAUSIBLE / REFUTED分類）
- AskUserQuestionルール（1メッセージ1質問、フェーズ確認）
- hunkはあくまで「所見を視覚的に添える」補助。所見の中身・検証は従来通り

**allowed-tools**: 変更不要（hunk連携は全て `Bash` の `hunk session *` で完結）。

## 非対象（YAGNI）

- tmuxペイン自動分割（副作用が大きい）
- ClaudeによるTUI自動起動（公式設計に反する）
- カスタムテーマ連携（configは `modules/hunk.nix` で管理済み）

## 検証で得た実地知見（設計の根拠）

- hunk session連携はlocalhostデーモン経由。この環境（WSL+tmux+Claude Code）で
  サンドボックスのlocalhostブロックは発生しなかった（実地確認済み）
- ナビゲートは即座に反映（`navigate` → ユーザー画面がスクロール）
- `comment add --focus` で画面移動＋コメント表示が同時に起こる
- userコメントとagentコメントでJSONスキーマが異なる（`body` vs `summary`+`rationale`）
