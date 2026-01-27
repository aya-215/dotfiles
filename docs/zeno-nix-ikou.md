# Nix移行計画

## 完了済み Phase 1-6（2025-01-27）

| Phase | 内容 | 状態 |
|-------|------|------|
| 1 | 重複ツール削除（delta, lazygit, starship を `/usr/local/bin/` から削除） | ✅ 完了 |
| 2 | CLIツール追加（ghq, gh, gcalcli を `packages.nix` に追加） | ✅ 完了 |
| 3 | Zshプラグイン移行（fast-syntax-highlighting を Nix パッケージパスに変更） | ✅ 完了 |
| 4 | ランタイム移行（fnm, deno, bun を Nix に移行、`~/.deno` `~/.bun` 削除） | ✅ 完了 |
| 5 | Homebrew完全削除（pipx, python3 を Nix に移行、brew shellenv 削除、`/home/linuxbrew` 削除） | ✅ 完了 |
| 6 | 最終クリーンアップ（fast-syntax-highlighting の ghq ディレクトリ削除） | ✅ 完了 |

---

## 未移行: zeno.zsh（現状維持）

### 現在の管理方法
- ghqでクローン: `~/src/github.com/yuki-yano/zeno.zsh`
- `modules/zsh.nix` の `initExtra` 内で手動 source

### nixpkgsにパッケージが存在しないため、将来移行する場合の選択肢

#### 方法1: flake inputs（推奨 ★★★★★）

```nix
# flake.nix
inputs.zeno-zsh = {
  url = "github:yuki-yano/zeno.zsh";
  flake = false;
};

# home.nix で inputs を specialArgs 経由で渡す
# modules/zsh.nix
plugins = [
  {
    name = "zeno";
    src = inputs.zeno-zsh;
    file = "zeno.zsh";
  }
];
```

- flake.lockでバージョン完全固定
- `nix flake update` で一括更新可能
- 実装には flake.nix → home.nix → zsh.nix への inputs 受け渡しが必要
- initExtra内のZENO環境変数設定とbindkeyは維持（pluginsより後に評価される）

#### 方法2: fetchFromGitHub（★★★☆☆）

```nix
# modules/zsh.nix
plugins = [
  {
    name = "zeno";
    src = pkgs.fetchFromGitHub {
      owner = "yuki-yano";
      repo = "zeno.zsh";
      rev = "<commit-hash>";
      sha256 = "<hash>";
    };
    file = "zeno.zsh";
  }
];
```

- zsh.nix内で完結
- 更新時にハッシュの手動変更が必要

#### 方法3: ghq維持（現在採用中 ★★★★☆）

- 変更不要
- 新環境では `ghq get yuki-yano/zeno.zsh` が別途必要

---

## 未移行: rustup/cargo（現状維持）

- `~/.cargo/` はrustupでのバージョン管理を維持
- Rustのバージョン切替が必要な場合、rustupの方が柔軟
