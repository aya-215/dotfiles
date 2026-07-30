# README 全面書き換え（ハブ型への再構成） — 設計

作成日: 2026-07-30

## 背景

README.md の最終更新は 2026-03-30（`bfd1301`）。以降4ヶ月分の変更が反映されておらず、
実態とのズレが多数ある。

主なズレ:

| 箇所 | 内容 |
|---|---|
| `modules/` 一覧（L23-31） | 8個の記載に対し実際は14個。`tmux/gh-dash/glauncher/yazi/hunk` が欠落 |
| パッケージ表（L104, L342-378） | 廃止済みの `wslu`・`pipx` を記載。`yazi/poppler-utils/sshfs/cmake/curl` が欠落 |
| `scripts/`（L50） | 「各種スクリプト」の1行のみ。実際は8サブシステム36ファイル |
| `docs/`（L47-49） | 2ディレクトリのみ記載。実際は20md + 4ディレクトリ |
| `windows/`（L42-45） | `dot_config/`・`run_onchange_install-autohotkey.ps1.tmpl` が欠落 |
| PowerShell章（L419） | `PowerShell/README.md` へのリンクが切れている（実体は空ディレクトリ） |

## 問題の本質

ズレの原因は個々の記載漏れではなく、**README が実態の写し（コピー）を持っている構造**にある。
エイリアス一覧・キーバインド表・パッケージ表を本文に抱えているため、ソースを変更するたび
README を手で追随させる必要があり、追随漏れが構造的に発生する。

記載漏れだけを埋めても半年後に同じ状態へ戻る。

## 方針: ハブ型への再構成

README は実態の写しを持たない。「何があるか」と「どこを見ればよいか」に徹し、
変わりやすい一覧はソースまたは `docs/` への誘導に置き換える。

目標規模: 150〜180行（現 472行）。

### 章構成

| 章 | 内容 | 現READMEからの変化 |
|---|---|---|
| 1. 概要 | Nix/HM による宣言的管理、WSL/Windows の二層構成 | 維持 |
| 2.（欠番） | 当初は clone 2つ構成の章を置く設計だったが取り下げた（→「clone 2つ構成の扱い」） | — |
| 3. 構成 | ディレクトリツリー + 各1行説明 | 実態同期・縮約 |
| 4. セットアップ | WSL（Nix）/ Windows（依存導入 → bootstrap の2段） | 実態同期 |
| 5. 日常運用 | 編集 → `home-manager switch` → commit → push | 維持 |
| 6. サブシステム | `scripts/` 配下8つを表で。役割 + 詳細リンク | **新規** |
| 7. ツール構成 | 散文で数行。`modules/packages.nix` へ誘導 | **表を全削除** |
| 8. ドキュメント | 恒久ドキュメントのみリンク | 実態同期 |
| 9. トラブルシューティング | HM更新・初期化・GC + hunk SIGSEGV の注記 | 追記 |
| 10. 注意事項 | 維持・更新 | 実態同期 |

### 本文から削除する一覧

いずれもソースが唯一の真実であり、README に写しを置くとズレる。

- エイリアス一覧（L209-228）→ `modules/zsh.nix` 参照
- fzf関数表 WSL版・PowerShell版（L232-245, L400-418）
- パッケージ表3つ（L342-378）→ `modules/packages.nix` 参照
- lazygit キーバインド表（L317-328）→ `config/lazygit/` 参照
- nb コマンド一覧（L271-287）→ `docs/nb-commands.md` へリンク
- PowerShell章（L381-419）→ 概要数行に縮約（リンク切れも解消）

### §3 構成の書き方

`modules/` を個別列挙せず「機能別 Nix モジュール」に集約する。
個別列挙をやめることで、モジュール追加時の追随漏れが構造的に起きなくなる。

### §6 サブシステム表

`scripts/` 配下の8サブシステム。`pr-diffview/` と `gitbucket-mcp/` は設計書を持たないため、
表の役割欄を2〜3文にして表内で完結させる（新規ドキュメントは作らない）。
`cleanup-wsl.sh`・`nb-sync.sh` は「単発スクリプト」の1行にまとめ、表から漏れないようにする。

| サブシステム | リンク先 |
|---|---|
| `claude-summarize/` | `docs/superpowers/specs/2026-06-09-claude-session-summary-design.md` ほか |
| `claude-pane-session/` | `docs/tmux-claude-session-restore.md` |
| `daily-review/` | `docs/superpowers/specs/2026-06-10-claude-p-migration-design.md` |
| `lib/` | `docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md` ほか |
| `backup/` | `scripts/backup/README.md` |
| `pr-diffview/` | なし（表内で完結） |
| `gitbucket-mcp/` | なし（表内で完結） |
| `setup/` | なし（Windows依存導入。§4から参照） |

## 付随して行う修正

README 最新化の過程で判明した実態側の問題。README が正しい手順を書けるようにするため、
同時に修正する。

### `scripts/setup/install.ps1` の削除

Windows のセットアップ経路が2つ存在し、`scripts/setup/install.ps1` は機能しない。

| 機能 | `bootstrap/install.ps1` | `scripts/setup/install.ps1` |
|---|---|---|
| chezmoi 導入 | あり | なし |
| XDG_CONFIG_HOME 設定 | あり | あり（重複） |
| Abbr モジュール | あり | なし |
| 設定ファイル配置 | chezmoi | 自前 symlink |
| OneDrive 警告 | あり | なし |

削除理由:

1. `scripts/setup/install.ps1:72` が `$DOTFILES_DIR\PowerShell` を symlink 元に指定しているが、
   このディレクトリは 2026-03-24 の chezmoi 移行（`0bc7b17`）で空になっている。
   実行すると PowerShell profile のリンクが空を指す。
2. 設定ファイル配置は chezmoi に置き換わっており、機能が重複している。

`install-fonts.ps1`（HackGen Nerd Font）と `install-dependencies.ps1`（winget一括導入）は
`bootstrap/` 経路に代替がないため**残す**。`common.ps1` はこの2つが依存するため残す。

削除に伴い `common.ps1` の `Set-EnvironmentVariableIfNeeded` と `New-SymbolicLinkSafe` が
未使用になる。両関数も削除する。

### `install-dependencies.ps1:154` の案内パス修正

`.\scripts\install.ps1` を案内しているが、2025-12-10 の `scripts/setup/` への移動
（`076f1f6`）で存在しないパスになっている。`bootstrap\install.ps1` に修正する。

### `bootstrap/install.ps1:8-9` の clone 先修正

`$env:USERPROFILE\.dotfiles` への clone を案内しているが、実機に存在しない（後述）。
具体パスは焼き込まず `<clone先>` に一般化する。

### `PowerShell/`（空ディレクトリ）の削除

git は空ディレクトリを追跡しないため（`git ls-files PowerShell/` は0件）、
削除してもコミットに差分は出ない。ローカルの掃除としてのみ実施する。
L419 のリンク切れは README 編集で解消される。

## clone 2つ構成の扱い（章として設けない）

当初は「clone が2つある構成」を独立章として冒頭に置く設計だったが、これは誤りと判断して取り下げた。

理由:

1. **README の役割から外れる。** clone がどこに置かれているかは特定マシンの環境状態であり、
   リポジトリの性質ではない。具体パスを書くと別マシンでは即座に嘘になる。
2. **読者が違う。** 「push を忘れると Windows アプリに反映されない」という運用知識は
   このマシンで作業する Claude 向けであり、既に CLAUDE.md に記載がある。README に書くと二重管理になる。
3. **本方針と矛盾する。** 「README は実態の写しを持たない」としてパッケージ表を削除しながら、
   マシン固有の状態を新たに書き加えるのは一貫しない。

代わりに、Windows セットアップ手順（§4）の中で「Windows 側は WSL 側とは別に clone する」という
リポジトリの性質としての事実のみ書き、clone 先は `<clone先>` として一般化する。
反映には Windows 側での `git pull` が必要である点も同じ章に置く。

同じ理由から、`bootstrap/install.ps1` のコメントにも具体パスを焼き込まない。
`$env:USERPROFILE\.dotfiles` は実機に存在しなかったため（`/mnt/c/Users` 配下を `find` で確認、0件）、
`<clone先>` に置き換える。

`install-dependencies.ps1:154` の死んだパス修正は当初どおり実施する。

## 検証

ドキュメント変更のため自動テストはない。以下を手で確認する。

1. README 内の全リンク先がリポジトリに存在すること
2. README に記載したディレクトリ・ファイルが実在すること
3. 削除した一覧の代替参照先（`modules/packages.nix` 等）が実在すること
4. `install-dependencies.ps1` / `install-fonts.ps1` が `common.ps1` の削除後関数を
   参照していないこと（grep で確認）
5. リポジトリ内に `%USERPROFILE%\.dotfiles` を案内する記述が残っていないこと（grep で確認）

## コミット分割

作業ツリーに無関係な変更（`config/zsh/functions.zsh`、`modules/tmux.nix`、
`scripts/gitbucket-mcp/server.py`、`docs/speech-nippo-auto-lt.md`）があるため、
`git add .` は使わずパスを明示する。

1. `docs:` 本設計書
2. `docs:` README 全面書き換え
3. `chore:` `scripts/setup/install.ps1` 削除・`common.ps1` 未使用関数削除・
   `install-dependencies.ps1` と `bootstrap/install.ps1` の案内パス修正
