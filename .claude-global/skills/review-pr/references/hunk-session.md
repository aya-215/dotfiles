# hunk session 連携リファレンス

hunk（review-first diff TUI）の生きたセッションに `hunk session *` CLIで接続し、
ナビゲート・コメントする手順。`/hunk-review` と `review-pr` の両skillが参照する実体。

## 最重要ガード: TUIはユーザーが開く

**Claudeは絶対に `hunk diff` / `hunk show` を自分で実行しない。**
実行してもClaudeのbashプロセス内で起動し、ユーザーの端末に映らず、
non-TTYで無意味になる。Claudeの役割は既存セッションへの接続と先導のみ。

## 接続フロー

1. `hunk session list --json` でセッション確認
2. セッションが無ければ、ユーザーに開き方を**案内して待つ**（コマンド文字列は提示、
   Enterを押すのはユーザー）:
   - PRブランチ: 「`hunk diff <base>...HEAD` を自分の端末で開いてな」
   - dotfiles等の環境: `! hunk diff ...`（`!`プレフィックスでこのセッション内実行）も選択肢
   - リモートPRのみ閲覧: `gh pr diff | hunk pager`
3. 「開いた」と言われたら `hunk session list` で再確認して接続
4. 複数セッションがマッチ → `<session-id>` を明示。単一なら自動解決

## セッション選択

多くのコマンドが受け付ける:
- `--repo <path>` — ロード中のrepo rootで一致（最も一般的）
- `<session-id>` — 正確なIDで一致（同一repoに複数セッションがある時）

## 構造把握

```bash
hunk session list [--json]
hunk session get (--repo . | <id>) [--json]      # Path/Repo/Source を表示
hunk session context (--repo . | <id>) [--json]  # 現在のフォーカス位置
hunk session review (--repo . | <id>) --json [--include-patch]
```

- `review --json` の戻りは **`review` キー配下にネスト**。ファイルは `review.files[]`、
  各ファイルの構造は `files[].hunks[]`（`index`, `header`, `oldRange`, `newRange`）
- patchは `--include-patch` を付けた時のみ、**`files[].patch`**（ファイル単位）に入る。
  トップレベルの `patch` フィールドではない
- context中は情報を膨らませないため、まず `review --json`（patchなし）で構造把握し、
  本当に生diffが要るファイルだけ `--include-patch` を使う

## ナビゲート

絶対ナビは `--file` と、以下のうち**ちょうど1つ**が必要:

```bash
hunk session navigate --repo . --file src/App.tsx --hunk 2       # 1始まりのhunk番号
hunk session navigate --repo . --file src/App.tsx --new-line 372 # 新側の行番号
hunk session navigate --repo . --file src/App.tsx --old-line 355 # 旧側の行番号
```

コメント間ナビは `--file` 不要:

```bash
hunk session navigate --repo . --next-comment
hunk session navigate --repo . --prev-comment
```

- `--hunk` / `--new-line` / `--old-line` は同時指定不可（エラー「Specify exactly one navigation target」）
- `--next-comment` / `--prev-comment` も両方同時は不可
- **navigate は確認不要で自由に実行してよい**（レビュー先導の一部）

## コメント

### 読取（source別にスキーマが異なる — 重要な罠）

```bash
hunk session comment list --repo . --type user|ai|agent|all [--file X]
```

- **userコメント**: `body` キー（他に `newRange`, `source:"user"`, `noteId`, `editable`）
- **agentコメント**: `summary` + `rationale` キー（他に `line`, `side`, `commentId`, `author`）
- 種別を取り違えると `summary` が None になる。ユーザーの発言を読むなら
  `--type user` して `body` を見る

### 追加

```bash
# 単発
hunk session comment add --repo . --file README.md --new-line 103 \
  --summary "要約" [--rationale "理由"] [--author "claude"] [--focus]

# 一括（stdin JSON batch）
printf '%s\n' '{"comments":[{"filePath":"README.md","newLine":103,"summary":"要約"}]}' \
  | hunk session comment apply --repo . --stdin [--focus]
```

- `comment add` は `--file` + `--summary` + (`--old-line` か `--new-line` のどちらか1つ) が必須
- `comment apply` の各itemは `filePath` + `summary` + ターゲット1つ（`hunk`/`hunkNumber`/`oldLine`/`newLine`）
- `--focus` で追加箇所へ画面も移動
- **コメントを付けたら、付けた内容を必ずユーザーに報告する**

### 破壊的操作（承認必須）

```bash
hunk session comment rm --repo . <comment-id>
hunk session comment clear --repo . --yes [--file X]
```

- `rm` / `clear` は実行前に必ずAskUserQuestionでユーザー承認を取る

## reload（レビュー対象の差し替え）

```bash
hunk session reload --repo . -- diff              # 常に -- の後にhunkコマンド
hunk session reload --repo . -- diff main...HEAD
hunk session reload --repo . -- show HEAD~1
```

- ネストするhunkコマンドの前に必ず `--` を置く

## ブランチ間差分の開き方（ユーザーに案内する内容）

`hunk diff` は `git diff` と同じ構文でtargetを取る:

| 目的 | コマンド |
|---|---|
| mainとの差分（2点） | `hunk diff main` |
| ブランチの変更だけ（3点、PR相当） | `hunk diff main...HEAD` |
| 2ブランチ比較 | `hunk diff main feature` |
| ステージ済み | `hunk diff --staged` |
| ファイル絞り込み | `hunk diff main -- src/` |

PR相当の「自分が足した変更だけ」は3点ドット `main...HEAD`。

## 既知エラー

- **No active Hunk sessions**: hunkが見えてるのに出るならサンドボックスのlocalhost
  ブロック疑い（この環境では未発生を実地確認済み）。でなければユーザーに開いてもらう
- **Multiple active sessions match**: `<session-id>` を明示
- **No visible diff file matches**: 対象ファイルが未ロード。`context` 確認 → 必要なら `reload`
- **Pass the replacement Hunk command after `--`**: reload時に `--` を忘れている
- **Specify exactly one navigation target**: `--hunk`/`--old-line`/`--new-line` を1つに絞る
- 古いゾンビセッション: `session list` のpidで生存確認して見分ける
