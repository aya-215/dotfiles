# Phase 4: Nix/Home Manager 最適化

## 目的

Nixモジュール群を見直し、未使用パッケージの整理と設定の堅牢化を行う。

## 対象ファイル一覧

| ファイル | 問題点 | 対応 |
|---|---|---|
| `modules/packages.nix` | 未使用パッケージが混入している可能性 | 棚卸し・整理 |
| `modules/zsh.nix` | pr-diffview自動起動条件の確認 | 必要であれば堅牢化 |
| `flake.nix` / `home.nix` | 構成の最適化確認 | 必要であれば整理 |

---

## 変更内容

### 1. `modules/packages.nix` のパッケージ棚卸し

現在43個のパッケージが登録されている。実際に使用しているか一つずつ確認する。

**確認方法:**

```bash
# インストール済みパッケージ一覧
home-manager packages

# 各パッケージが実際に使われているか確認
which <パッケージ名>
```

**削除候補（要確認）:**

実際に使っていないパッケージが見つかった場合は削除する。
→ 調査時点では具体的な不要パッケージは未特定。Phase 4 実施時に手動確認する。

### 2. `modules/zsh.nix` の pr-diffview 自動起動確認

**現状:** tmuxのペイン0でのみ pr-diffview サーバー（ポート8765）を自動起動している。

**確認項目:**
- サーバーが既に起動している場合の重複起動対策があるか
- プロセス終了時のクリーンアップ処理があるか

**改善案（必要な場合）:**

```bash
# 起動前にポートが使用されていないか確認する処理を追加
if ! lsof -i :8765 > /dev/null 2>&1; then
  # サーバー起動
fi
```

### 3. `flake.nix` / `home.nix` の確認

- 不要なinputs（依存）がないか確認
- `home.nix` のimports一覧と実際のモジュールが対応しているか確認

---

## 作業手順

```bash
# 1. 現在のパッケージ一覧を確認
cat ~/.dotfiles/modules/packages.nix

# 2. 各パッケージが実際に使われているか確認
# （手動確認が必要）

# 3. 不要パッケージを削除後、ビルド確認
home-manager switch --flake ~/.dotfiles

# 4. zsh.nixのpr-diffview起動ロジック確認
grep -n "pr-diffview\|8765" ~/.dotfiles/modules/zsh.nix

# 5. 問題があれば修正してビルド
home-manager switch --flake ~/.dotfiles
```

## 検証

```bash
# Home Manager ビルドが成功すること
home-manager switch --flake ~/.dotfiles

# 各ツールが正常に起動すること
nvim --version
tmux -V
zsh --version

# pr-diffview が起動することを確認（tmux内）
curl http://localhost:8765/health  # または該当エンドポイント
```

## 完了後

```bash
git add modules/
git commit -m "chore: Nixパッケージ棚卸し・zsh設定の堅牢化"
git push
```

## 注意事項

- `home-manager switch` は既存の設定を置き換えるため、ビルドエラーになった場合は前のコミットに戻せるようにしておく
- パッケージ削除後は必ずビルドして動作確認してから次に進む
