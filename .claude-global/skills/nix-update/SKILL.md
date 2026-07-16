---
name: nix-update
description: dotfilesのNix flake（nixpkgs/home-manager等）を安全に定期更新する。「nixpkgs更新」「flake update」「/nix-update」で起動。
allowed-tools: Read, Edit, Bash, AskUserQuestion
version: 1.0.0
---

## 作業指示

このスキルは dotfiles（`/home/aya/.dotfiles`）の Nix flake input（nixpkgs / home-manager / glauncher 等）を安全に定期更新する操作です。

**重要な前提**: Nix は flake.lock が指す nixpkgs rev で全ツールのバージョンを固定します。`nix flake update` は **nixpkgs rev 配下の全ツールを一斉にバージョン変動させる**操作であり、影響範囲が大きい。そのため各ステップで状態を確認し、問題を検知したら「まず前進解決」を試み、ユーザーに明確な選択肢を提供すること。

**遠慮せずに、全力を尽くしてください**: 更新前に戻り先を必ず記録し、switch 後は警告を機械的に検知し、問題があれば診断して修正案を提示すること。データ損失（未コミット変更の破棄等）は絶対に避ける。

## 実行制限

**以下の作業のみを実行し、これ以外は絶対に行わない：**
- git 状態の確認（git status, nix flake metadata 等）
- `nix flake update`（全 input 一括）とビルド反映（`home-manager switch`）
- switch 出力の警告検知
- 前進解決の修正（**必ずユーザー承認後**）
- flake.lock 等のコミット・push
- ユーザーへの質問（AskUserQuestion）

**禁止事項：**
- ユーザーの承認なしでのファイル修正（前進解決の修正含む）
- 強制的な git 操作（`--force` 等）
- 対象 dotfiles（`/home/aya/.dotfiles`）**以外**のファイル操作
- 個別ツールのみの更新・overlay 追加（本スキルの範囲外）

## 実行フロー

### ① 事前確認（戻り先 rev の記録）

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git remote -v            # CLAUDE.mdルール: git操作前にリモートURL確認
git status
nix flake metadata 2>/dev/null | grep -iE "nixpkgs|Last modified"   # 現rev=戻り先。ユーザーに提示
```

- ローカルに未コミットの変更がある場合、**AskUserQuestion** で処理を確認:
  - 質問: "ローカルに未コミットの変更があります。どう処理しますか？"
  - 選択肢: **stash（一時退避）** / **続行（変更を残したまま更新）** / **中止**
- 戻り先 rev（現在の flake.lock の nixpkgs rev・日付）を必ず記録・表示する。

### ② 全 input 一括更新 → 差分表示

```bash
rm -f .git/index.lock
nix flake update 2>&1
```

出力の `Updated input 'X': 旧rev(日付) → 新rev(日付)` 行を差分としてユーザーに提示する。更新が無ければ「既に最新」と報告してフロー終了。

### ③ ビルド反映

```bash
home-manager switch --flake . 2>&1 | tee /tmp/nix-update-switch.log
```

### ④ 検証と前進解決モード

**検証（決定的処理）** — switch 出力から警告を機械的に検知:

```bash
grep -iE "mismatched versions|undefined variable|has been renamed|^error:" /tmp/nix-update-switch.log
```

- switch の exit code が非 0 → ビルド失敗（即 NG）
- 上記 grep がヒット → 警告あり

**問題なし** → ⑤ へ。

**問題あり** → 前進解決モードへ:

#### 前進解決 — 既知パターン辞書

| 検知パターン | 診断 | 修正案（承認後実行） |
|---|---|---|
| `mismatched versions` | HM input が古く nixpkgs と不整合 | `nix flake update home-manager` → ③ 再実行 |
| `undefined variable 'X'` | pkg 名変更/削除、または pin が該当バージョンに未到達 | `nix eval --raw nixpkgs#X.pname` 等で存在確認 → 改名 or 一時除外を提案 |
| `has been renamed`（option A→B） | HM/nixpkgs のオプション改名 | 該当 nix ファイルの修正 diff を提示 |
| その他 `error:` | 個別のビルドエラー | `nix log <失敗した.drv>` で深掘り → 原因と対処を提示 |

**手順**: 原因を診断 → 具体的な修正案を提示して**停止** → ユーザー承認後に修正を実行 → ③ に戻って再検証。

#### 未知フォールバック（LLM 補助層）

辞書に無い警告は、診断情報（警告全文＋関連する `nix log` 等）を集めて提示し、対処はユーザーと相談する。決めつけで自動修正しない。

#### ループ防止

「修正 → 再 switch → 再検証」で**同一警告が 2 回続けて解消しない**場合は、前進解決を諦めて rollback 提案へ移る。

#### rollback（最終手段）

前進で解決できない時のみ、**AskUserQuestion** で提示:
- **未コミット時**: `git checkout flake.lock`（更新を破棄。全ツールが元 rev に揃って戻る）
- **switch 済み**: `home-manager generations` で世代一覧を表示 → 前世代の `activate` を実行して戻す

### ⑤ コミット・push

修正内容に合わせて適切にコミットする。

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add flake.lock       # 前進解決で他ファイルも触った場合は内容ごとに適切に分割してadd
rm -f .git/index.lock
git commit -m "chore(flake): nixpkgs等を定期更新（<主要input>を<旧日付>→<新日付>）"
rm -f .git/index.lock
git push
```

- 更新のみ → `chore(flake):` 単独コミット。
- 前進解決で nix ソースを修正した場合 → その修正は内容に応じた別コミット（`fix:` 等）に分け、flake.lock 更新と分離する。

---

## 出力形式

### 成功時（更新あり）

```markdown
✅ Nix flake 定期更新 完了

**更新された input**:
- nixpkgs: <旧日付> → <新日付>
- home-manager: <旧日付> → <新日付>
- （他 input）

**検証**: home-manager switch 成功・警告なし
**戻り先（記録）**: nixpkgs <旧rev> (<旧日付>)
**コミット**: <ハッシュ> chore(flake): ...
```

### 成功時（前進解決あり）

```markdown
✅ Nix flake 定期更新 完了（前進解決を実施）

**更新された input**: （上記同様）
**検知した警告**: <警告の要約>
**前進解決**: <実施した修正の内容>（例: home-manager も update して不一致を解消）
**検証**: 再 switch 成功・警告なし
**コミット**: <ハッシュ×N>（更新と修正を分離）
```

### 更新なし

```markdown
ℹ️ flake は既に最新です。更新はありませんでした。
```

### rollback 実施時

```markdown
⚠️ 前進解決で解消できなかったため rollback しました

**検知した警告**: <警告>
**試みた前進解決**: <内容>
**rollback 方法**: <git checkout flake.lock / 世代戻し>
**現在の状態**: 更新前の rev に復帰済み（<旧rev>）

未解決の警告について、次の手を一緒に検討しましょう。
```

---

## エラー処理

### switch がビルド失敗

`nix log <失敗した.drv パス>` で詳細を取得し、既知パターン辞書に照合。該当すれば修正案を提示、無ければ未知フォールバックへ。

### flake が git-tracked でないファイルを参照して失敗

新規 nix ファイルは `git add -N` で intent-to-add してから再実行（flake は tracked file のみ可視）。

### index.lock エラー

各 git 呼び出しの前に `rm -f .git/index.lock` を挟む（CLAUDE.md「index.lock 対処」に従う）。

---

## 重要な制約

- **戻り先を必ず記録**: 更新前に現 rev を記録・表示してから update する
- **前進解決を優先**: 問題検知時はまず診断＋修正案。rollback は最終手段
- **修正は承認後**: 前進解決の修正・rollback は必ずユーザー選択を経る
- **影響範囲を明示**: 全ツールが一斉に動くことを踏まえ、更新内容を明確に報告する

これ以外は実行しない。
