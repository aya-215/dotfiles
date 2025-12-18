# nb関連設定の分析とリファクタリング

> 最終更新: 2024-12-18

## 設定ファイル一覧

| ファイル | 内容 |
|----------|------|
| `.zshrc` (229-658行) | nb関連の13個のシェル関数 |
| `~/.config/zeno/config.yml` | nbスニペット5個 + 補完4個 |
| `~/.local/bin/nbtdone-completion` | nbtdone用の補完スクリプト |
| `~/.nb/daily/.templates/daily.md` | 日報テンプレート |
| `~/.nb/tasks/.templates/task.md` | タスクテンプレート |

---

## シェル関数一覧 (.zshrc)

### 日報管理

| 関数 | 機能 | 行数 |
|------|------|------|
| `nbd` | 今日の日報を作成（タスク自動連携） | 86行 |
| `nbdo` | 今日の日報を表示 | 4行 |
| `nbde` | 今日の日報を編集 | 4行 |
| `nbdy` | 昨日の日報を表示 | 4行 |
| `nbdl` | 日報一覧をfzfで選択して表示 | 9行 |
| `nbi` | inbox（タスク受信箱）を編集 | 3行 |

### タスク管理

| 関数 | 機能 | 行数 |
|------|------|------|
| `nbt` | タスク追加（対話形式） | 88行 |
| `nbtl` | タスク一覧表示（期限順） | 65行 |
| `nbtsync` | inbox.mdを自動生成 | 78行 |
| `nbtdone` | タスクを完了にする | 33行 |
| `nbtf` | タスクフォルダ作成 | 13行 |
| `nbtfl` | タスクフォルダ一覧 | 16行 |

---

## zeno設定 (config.yml)

### スニペット

| キーワード | 展開後 |
|-----------|--------|
| `nbd` | `nbd` |
| `nbds` | `nbdo` |
| `nbde` | `nbde` |
| `nbs` | `nb search "{{keyword}}"` |
| `nba` | `nb add "{{title}}"` |

### 補完パターン

| パターン | 補完内容 |
|----------|----------|
| `^nb (.*)$` | ノートブック一覧 |
| `^nb ([^:]+):(.*)$` | ノート一覧 |
| `^nb daily:(.*)$` | 日報一覧 |
| `^nbtdone (.*)$` | 未完了タスク一覧 |
| `^nbt "..." (.*)$` | タスクフォルダ一覧 |

---

## 問題点

### 1. zenoスニペットの冗長性
```yaml
- keyword: nbd
  snippet: nbd    # <- 同じ文字列に展開（意味がない）
- keyword: nbde
  snippet: nbde   # <- 同じ
```
**Ctrl+Spaceで展開しても変化なし**

### 2. コードの重複（findコマンド）
`nbtsync`内で**同一のfindコマンドが3回**実行されている:
```bash
find "$tasks_dir" -name "*.md" -not -path "*/.templates/*" ...  # 1回目
find "$tasks_dir" -name "*.md" -not -path "*/.templates/*" ...  # 2回目
find "$tasks_dir" -name "*.md" -not -path "*/.templates/*" ...  # 3回目
```

### 3. 日付計算の重複
`days_diff`計算が`nbtl`と`nbtsync`の両方で重複:
```bash
local days_diff=$(( ($(date -d "$due" +%s) - $(date -d "$today" +%s)) / 86400 ))
```

### 4. 命名の一貫性
| 現在 | 問題 |
|------|------|
| `nbd` | 日報作成 |
| `nbdo` | 日報表示 (do = show?) |
| `nbde` | 日報編集 |
| `nbds` (zeno) | `nbdo`に展開 (紛らわしい) |

### 5. nbtdone-completionの二重管理
- `.zshrc`内の`nbtdone`関数
- `~/.local/bin/nbtdone-completion`スクリプト
**ほぼ同じfind処理を別々に実装**

### 6. 未使用の除外パターン
```bash
-not -name "2025-*.md"
```
タスクフォルダに日報形式のファイルがある前提だが、本来は分離されているはず

---

## 改善案

### A. zenoスニペットの整理
**削除候補:**
- `nbd → nbd` (同じ)
- `nbde → nbde` (同じ)
- `nbds → nbdo` (1文字の省略のみ)

**残すべき:**
- `nbs → nb search "{{keyword}}"` (プレースホルダあり)
- `nba → nb add "{{title}}"` (プレースホルダあり)

### B. 共通関数の抽出
```bash
# 提案: 共通ヘルパー関数
_nb_tasks_dir="$HOME/.nb/tasks"

_nb_find_tasks() {
  find "$_nb_tasks_dir" -name "*.md" \
    -not -path "*/.templates/*" \
    -not -path "*/.git/*" \
    -not -name "inbox.md"
}

_nb_days_until() {
  local due="$1"
  local today=$(date +%Y-%m-%d)
  echo $(( ($(date -d "$due" +%s) - $(date -d "$today" +%s)) / 86400 ))
}
```

### C. nbtsyncの効率化
**現状**: 3回のfind + 3回のファイルループ
**改善**: 1回のfindで全タスク情報を取得し、分類

### D. 命名の統一案
| 現在 | 提案 | 理由 |
|------|------|------|
| `nbd` | `nbd` | 日報(daily)の頭文字 |
| `nbdo` | `nbds` | show の s |
| `nbde` | `nbde` | edit の e |
| `nbdy` | `nbdsy` | show yesterday |
| `nbdl` | `nbdl` | list の l |

### E. 設定ファイルの分離
`.zshrc`が肥大化しているため、nb関連を別ファイルに分離:
```bash
# .zshrc
source ~/.config/nb/functions.zsh
```

---

## 優先度順の推奨アクション

| 優先度 | アクション | 効果 |
|--------|-----------|------|
| 高 | zenoの無意味なスニペット削除 | 設定のシンプル化 |
| 高 | nbtsyncの効率化（find 1回化） | パフォーマンス改善 |
| 中 | 共通関数の抽出 | 保守性向上 |
| 中 | nbtdone-completionの統合 | 二重管理の解消 |
| 低 | 命名の統一 | 一貫性（破壊的変更あり） |
| 低 | 設定ファイルの分離 | 可読性向上 |

---

## 実施済みの変更

### 1. zenoスニペット整理
**削除:**
- `nbd → nbd` (無意味)
- `nbds → nbdo` (無意味)
- `nbde → nbde` (無意味)

**追加:**
- `nbta → nbt "{{task name}}"` (プレースホルダ付き)

### 2. .zshrc リファクタリング

#### 共通関数の抽出
```bash
_NB_TASKS_DIR="$HOME/.nb/tasks"
_NB_DAILY_DIR="$HOME/.nb/daily"
_nb_find_tasks()   # タスクファイル一覧
_nb_days_until()   # 期限計算
_nb_parse_task()   # frontmatter解析
```

#### コード量の削減
| 項目 | Before | After | 削減率 |
|------|--------|-------|--------|
| 総行数 | 430行 | 255行 | **41%減** |
| findコマンド数 | 8回 | 1回(共通関数) | **87%減** |
| 日付計算重複 | 6箇所 | 1箇所(共通関数) | **83%減** |

#### 命名変更
| 旧名 | 新名 | 理由 |
|------|------|------|
| `nbdo` | `nbds` | show の s で統一 |

#### nbtsync効率化
- Before: 3回のfindループ
- After: 1回のループで分類→集約

---

## 残りの改善案（未実施）

### 高優先度
1. **nbtdone-completionスクリプトの統合**
   - `~/.local/bin/nbtdone-completion` と `_nb_find_tasks` が重複
   - 共通関数を呼び出すように変更可能

### 中優先度
2. **設定ファイルの分離**
   ```bash
   # .zshrc
   [[ -f ~/.config/nb/functions.zsh ]] && source ~/.config/nb/functions.zsh
   ```

3. **zeno補完の拡充**
   - `nbtl` にfzf補完を追加
   - タスク編集 `nbte` 関数の追加

### 低優先度
4. **エラーハンドリング強化**
   - nbコマンドの存在確認
   - テンプレートの自動生成

---

## 現在のコマンド一覧

### 日報
| コマンド | 機能 |
|----------|------|
| `nbd` | 今日の日報作成/編集 |
| `nbds` | 今日の日報表示 |
| `nbde` | 今日の日報編集 |
| `nbdy` | 昨日の日報表示 |
| `nbdl` | 日報一覧(fzf) |
| `nbi` | inbox編集 |

### タスク
| コマンド | 機能 |
|----------|------|
| `nbt` | タスク追加 |
| `nbtl` | タスク一覧 |
| `nbtdone` | タスク完了 |
| `nbtsync` | inbox.md再生成 |
| `nbtf` | フォルダ作成 |
| `nbtfl` | フォルダ一覧 |
