# 検証指示: `paths:` frontmatter の条件ロードが効いているか

> **【2026-07-27 追記・重要】STEP 0〜2 は実施済み。結果は ✅ `paths:` は正しく機能している。**
> 記録: `docs/claude-config-audit-2026-07-27.md` §9「実発火検証の実施記録」
>
> **⚠️ 下記「判定表」の計測方法は誤りだった。** 条件ロードされたルールは
> `/context` の **Memory files には現れない**（4件・5.3k のまま不変）。
> 実際には Read 直後に **system-reminder として Messages 側にインライン注入**される。
> → 発火の判定は **Memory files ではなく system-reminder の有無**で行うこと。
> ただし STEP 0 の「載っていないこと」の確認には Memory files が使える（起動時ロードは計上されるため）。
>
> **残作業は STEP 3（symlink 経由）のみ。** 新しいセッションで STEP 0 → STEP 3 の順に実施すること。

**この内容を新しい Claude Code セッションに貼って実行してもらうこと。**
現行セッションでは原理的に検証できない（理由は末尾「なぜ別セッションが必要か」参照）。

- 対象コミット: `b8ff164`（`refactor: Claude設定の重複解消と条件ロード化`）
- 作成日: 2026-07-27
- 関連: `docs/claude-config-audit-2026-07-27.md`

---

## 前提: 期待される状態

`~/.claude/rules/` の4ファイルは、こう分かれているはず。

| ファイル | frontmatter | 期待されるロード挙動 |
|---|---|---|
| `external-actions.md` | なし | **常時ロード** |
| `learned-rules.md` | なし | **常時ロード** |
| `neovim-style.md` | `paths: config/nvim/**/*`, `**/*.lua` | **該当ファイルを読んだときだけ** |
| `shell-conventions.md` | `paths: **/*.sh`, `**/*.bash`, `scripts/**/*` | **該当ファイルを読んだときだけ** |

---

## 検証手順

### STEP 0: セッション起動直後、何もツールを使う前に

`/context` を実行して **Memory files** の一覧を確認する。

**記録すること**: 一覧に載っているファイル名を全部書き出す。特に以下の有無:

- [ ] `external-actions.md` → **載っているべき**
- [ ] `learned-rules.md` → **載っているべき**
- [ ] `neovim-style.md` → **載っていないべき**（これが本命）
- [ ] `shell-conventions.md` → **載っていないべき**（これが本命）
- [ ] `git-workflow.md` → **存在しないので載らないべき**（削除済みファイル。もし載っていたらキャッシュ等の別問題）

### STEP 1: 非該当ファイルを読む（コントロール条件）

```
/home/aya/.dotfiles/README.md
```

を Read する。これは `**/*.lua` にも `**/*.sh` にも `config/nvim/**/*` にも `scripts/**/*` にもマッチしない。

そのあと `/context` を再確認。

**期待**: `neovim-style.md` / `shell-conventions.md` は**まだ載らない**。

### STEP 2: 該当ファイルを読む（本命）

```
/home/aya/.dotfiles/config/nvim/lua/plugins/colorscheme.lua
```

を Read する。これは `config/nvim/**/*` と `**/*.lua` の両方にマッチする。

そのあと `/context` を再確認。

**期待**: `neovim-style.md` が**新しく載る**。

### STEP 3: symlink 経由でも効くか（追加検証）

```
/home/aya/.config/nvim/lua/plugins/yazi.lua
```

を Read する。`~/.config/nvim` → `/home/aya/.dotfiles/config/nvim` の symlink 経由。

公式は v2.1.198 以降 symlink 経由のマッチをサポートと明記しているが、この構成（プロジェクト外からプロジェクト内へ入るリンク）が該当するかは未確認。

**期待**: STEP 2 で既に載っているので差分は出ない。**STEP 2 をスキップして STEP 3 だけ単独で試すほうが綺麗**（新しいセッションで STEP 0 → STEP 3 の順でやる）。

---

## 判定表

> **⚠️ この表の「載る／載らない」は当初 `/context` の Memory files を想定していたが、それは誤り（冒頭の追記参照）。**
> 「STEP 2 で新しく載る」は **「Read 直後に当該ルール本文が system-reminder として注入されるか」** と読み替えること。
> STEP 0 の列（Memory files に載っていないこと）はそのままで正しい。

| STEP 0 で neovim-style.md | STEP 2 で新しく載る | 判定 |
|---|---|---|
| 載っていない | 載る | ✅ **`paths:` が正しく機能している**（期待どおり） |
| 載っていない | 載らない | ⚠️ ロードはされるが**トリガーが効いていない**。`paths:` のパターンがマッチしていない可能性 → パターンを見直す |
| **載っている** | （判定不要） | ❌ **frontmatter が無視されている**。全ファイル無条件ロードのまま → 下の「失敗時」へ |

---

## 失敗時の切り分け

### ケースA: STEP 0 で既に載っている（frontmatter 無視）

考えられる原因と確認方法:

1. **Claude Code のバージョンが古い** — `paths:` は比較的新しい機能
   ```bash
   claude --version
   ```
   `paths:` frontmatter のサポート、および symlink マッチ（v2.1.198+）を満たしているか確認。

2. **YAML の書式ミス** — 実際のファイルを確認
   ```bash
   head -8 ~/.claude/rules/neovim-style.md
   ```
   期待される内容:
   ```
   ---
   paths:
     - "config/nvim/**/*"
     - "**/*.lua"
   ---

   # Neovim設定スタイルガイド
   ```
   `---` が1行目にあること、インデントが半角スペース2つであること、閉じの `---` があることを確認。

3. **ユーザーレベル（`~/.claude/rules/`）では `paths:` が効かない可能性**
   公式ドキュメントは `paths:` をプロジェクトの `.claude/rules/` の文脈で説明しており、user-level で効く保証は明示されていない。
   → もしこれが原因なら、**この監査の提案Bは前提が崩れる**。`docs/claude-config-audit-2026-07-27.md` の §6 提案B に「user-level では無効」と追記し、代替案（プロジェクト側 `.claude/rules/` へ移す、または元の無条件ロードに戻す）を検討すること。

### ケースB: STEP 2 でも載らない（トリガー不発）

パターンのマッチ範囲の問題。試す順序:

1. `**/*.lua` だけで効くか（拡張子ベース）
2. `config/nvim/**/*` のパスがプロジェクトルート相対で正しいか（cwd が `/home/aya/.dotfiles` である前提）
3. `**/nvim/**/*` のような緩いパターンに変えて再試行

---

## 結果の記録先

判定が出たら:

1. `docs/claude-config-audit-2026-07-27.md` の **§9 実施記録 → 検証状況** の表を更新する
   （現在「⏳ 未検証」になっている行）
2. 失敗していた場合は **§6 提案B** に判明した制約を追記する
3. このファイル（`docs/verify-paths-frontmatter.md`）は検証完了後に削除してよい

---

## なぜ別セッションが必要か

ロード判定は**セッション起動時に一度だけ**行われる。したがって:

- **現行セッションでは不可能** — 起動時（frontmatter 追加前）に全ファイルが無条件ロード済み。既に持っているものが再注入されないのは当然で、`paths:` が効いた証拠にならない。
- **サブエージェントでも不可能** — 実測で確認済み。サブエージェントは**親セッション起動時の設定スナップショットを継承する**。証拠: 削除・コミット済みの `git-workflow.md`（ディスク上に存在しないことを実ファイル・symlink・git HEAD の3経路で確認）が、サブエージェント2体のコンテキストには載っていた。
  → **設定変更の検証にサブエージェントを使ってはいけない**という一般則。
