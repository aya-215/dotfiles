# Phase 5: 総合リファクタリング

## 目的

`docs/` ディレクトリの構造を整理し、`.claude-global/skills/` のメンテナンス状況を確認する。
**今回は構造整理のみ。ドキュメント内容の更新は別タスクで実施する。**

## 対象

| 領域 | 作業内容 |
|---|---|
| `docs/` 構造 | カテゴリ整理・古いファイルの移動/削除 |
| `.claude-global/skills/` | 未使用・古いスキルの確認 |
| `README.md` | 現状と大きく乖離している箇所のみ修正 |

---

## 変更内容

### 1. `docs/` ディレクトリ構造整理

**現状の構造（51ファイル）:**

```
docs/
├── Nix学習ガイド（13ファイル）
├── nvim-plugins/（30ファイル + INDEX.md）
├── 生産性管理系（3ファイル）
├── nb関連（3ファイル）
├── その他（ガイド類）
└── dotfiles-refactor/（本計画）
```

**確認・整理する項目:**

- 明らかに古い/不要なファイルがないか確認（削除候補があれば列挙）
- カテゴリ分けが現状に合っているか確認
- `nvim-plugins/INDEX.md` が実際のプラグイン一覧と一致しているか確認

> **注意:** ドキュメントの内容（古い情報の更新）は今回のスコープ外。構造（ファイルの配置・存在）のみ整理する。

### 2. `.claude-global/skills/` の確認

**現状:** 14+個のカスタムスキルが存在する。

**確認項目:**
- 実際に使用されているスキルか
- 重複している機能がないか
- スキルファイル自体に問題がないか（構文エラー等）

### 3. `README.md` の確認

ルートの `README.md`（464行）を確認し、明らかに現状と乖離している箇所のみ修正する。
（内容の全面更新は別タスク）

---

## 作業手順

```bash
# 1. docs/の現状確認
ls -la ~/.dotfiles/docs/
find ~/.dotfiles/docs -name "*.md" | head -60

# 2. nvim-plugins/INDEX.md と実際のプラグイン設定の差異確認
ls ~/.dotfiles/.config/nvim/lua/plugins/
cat ~/.dotfiles/docs/nvim-plugins/INDEX.md

# 3. スキル一覧確認
ls ~/.dotfiles/.claude-global/skills/

# 4. 不要ファイルがあれば削除・移動
# （Phase 5実施時に具体的に判断）

# 5. README.md の大きな乖離を確認
nvim ~/.dotfiles/README.md
```

## 検証

- `docs/` の構造が整理されていること
- 削除したファイルが他から参照されていないこと（grep確認）
- Neovimの `docs/nvim-plugins/INDEX.md` が現在のプラグイン一覧と一致していること

```bash
# 削除ファイルへの参照がないか確認
grep -r "削除したファイル名" ~/.dotfiles/
```

## 完了後

```bash
git add docs/ .claude-global/ README.md
git commit -m "chore: docsディレクトリ構造整理・スキル棚卸し"
git push
```

## 次のステップ（別タスク）

Phase 5 完了後、以下を別タスクとして実施する：
- `docs/` 内の古い情報を最新化
- Nix学習ガイドの内容確認・更新
- nvim-plugins/ の各プラグイン解説を現在の設定と照合
