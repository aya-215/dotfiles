# Dドライブ依存の棚卸しと改善方針（2026-07-30）

## 背景

自宅PCには D ドライブが存在しない。会社PC前提で書かれた設定が dotfiles 全体に散っており、
自宅PCでは機能しない・エラーになる・無言で壊れる箇所がある。

本ドキュメントは**調査結果と改善方針のみ**。実装は未着手。

## 調査環境

| 項目 | 値 |
|---|---|
| 調査実施マシン | 会社PC（`test -d /mnt/d` → 存在する） |
| Nix構成 | `flake.nix` は `homeConfigurations."aya"` 単一。**ホスト別プロファイルは無い** |
| wezterm `.env` | **存在しない**（`.env.template` のみ）。WSL側 clone と、WezTerm が実際に読む Windows側 clone `D:\git\dotfiles\config\wezterm\` の**両方**で確認済み |

自宅PC実機での再現確認は未実施（会社PCで調査したため）。

wezterm の実行形態: **Windows版 wezterm-gui.exe + WSLドメイン**（自宅・会社とも同じ）。
つまり自宅PCも「Windows上の wezterm が WSL シェルを開く」構成であり、
`config/wezterm/*.lua` の `D:\` 判定コードは自宅PCでも**評価される**（Linux版ではない）。
設定の実体は Windows側 clone `D:\git\dotfiles` ……だが**自宅PCにはDが無い**ため、
自宅PCでは wezterm がどこの clone を読んでいるのか自体が未確認（下記【G】）。

## 根本原因: D検出メカニズムが4系統バラバラに存在する

「Dが無い」こと自体が問題ではなく、**Dの有無を判定する仕組みが4つ並立し、互いに無関係**なのが原因。

| # | メカニズム | 判定タイミング | 実装箇所 |
|---|---|---|---|
| 1 | chezmoi `stat "D:\\"` → `.hasDriveD` | `chezmoi apply` 時に**焼き込み** | `windows/.chezmoi.toml.tmpl:8` |
| 2 | Lua `io.open('D:\\', 'r')` | wezterm 起動時（ランタイム） | `wezterm.lua:82`, `keys.lua:11`（**同じ関数を2重定義**） |
| 3 | `.env` の `WORKSPACE_TYPE=work` | wezterm 起動時（**手動設定**） | `wezterm.lua:107,113` |
| 4 | ガード無しのハードコード | 判定しない（常にDを前提） | zsh.nix, yazi, skills, docs |

制約: `.claude/CLAUDE.md` の方針どおり **wezterm は意図的に chezmoi テンプレートを使わない**
（`git pull` だけで反映させるため）。よって解決策は apply 時ではなく**ランタイム判定**である必要がある。

---

## 発見した不具合

### 【A】AHK Alt+V が自宅PCで確実に壊れる（最優先・コード上確定）

`windows/AutoHotkey/AutoHotkey.ahk.tmpl`

保存先はDの有無で分岐するが、**ペーストするWSLパスは分岐していない**。

```
80: {{- if .hasDriveD }}
81: global gTempDir := "D:\wsl_clipboard_temp"
82: {{- else }}
83: global gTempDir := "C:\wsl_clipboard_temp"     ← 保存先は C: に切り替わる
84: {{- end }}
...
105: wslPath := "/mnt/d/wsl_clipboard_temp/" . filename   ← 常に /mnt/d（ガード無し）
```

自宅PCでの挙動: PNG は `C:\wsl_clipboard_temp\` に保存され、
ペーストされるのは存在しない `/mnt/d/wsl_clipboard_temp/...`。
`FileExist(winPath)` は真になるためエラーも出ず、**無言で壊れたパスが貼られる**。

修正方針: `gTempDir` から WSL パスを導出する（`C:\foo` → `/mnt/c/foo`）。
分岐を2箇所に持たせず、1箇所（ドライブ文字）だけを変数化する。

### 【B】`ki` / `ko`（勤怠スクリプト）はガードが一切ない

`modules/zsh.nix:53-54` — `D:\個人用\script\kintai\*.py` を直叩き。条件分岐なし。
`windows/Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl:36-40` は
`{{- if .hasDriveD }}` でガード済み（自宅PCでは関数が定義されない）。

つまり**同じ機能で zsh 側だけ無防備**。自宅PCで `ki` を叩くと Python の
「ファイルが見つかりません」が出るだけで、原因が勤怠スクリプト不在だと分かりにくい。

### 【C】バックアップは廃止方針に決定（2026-07-30 ユーザー判断）

当初「自宅PCでバックアップが走っていない = 機能欠落」と評価したが、
**ユーザー判断によりバックアップ自体が不要**と決定。よって【C】は「直す」対象ではなく
**「会社PCの定期実行を止める」対象**に変わる。

導入時の動機は「WSL に不慣れだった頃、GUI（エクスプローラ）から
WSL 内のファイルが見られて便利だった」というもの。
現在は WSL 内へ `\\wsl$\Ubuntu-22.04\` で直接アクセスできるため、この動機は解消済み。

会社PCでの現状（実測）:

| 項目 | 実測値 |
|---|---|
| 実行状況 | **毎日 09:30 に稼働中**（`~/.backup-logs/backup-20260730-093001.log` まで連続） |
| タスク実体 | `WSL-Daily-Backup`、`TaskPath = '\'`、State `Ready`、次回 2026/07/31 9:30 |
| タスクの action | `wsl.exe -d Ubuntu-22.04 -u aya --exec <script>`（wrapper経由ではない） |
| **`LastTaskResult`** | **`1` = 失敗**。7/30 9:30 の実行はエラー終了している |
| ログサイズ | 1回あたり 3〜12MB。30日で自動削除される（スクリプト内 `find -mtime +30`） |
| バックアップ先 | `/mnt/d/WSL/backup/`（**実測 13GB**） |
| ログ保持 | `~/.backup-logs/` に 7/23〜7/30 分が残存（30日で自動削除） |

つまり毎朝 `/home/aya` 全体の rsync が走り、Dドライブを消費し続けている。
**不要なら止めるのが正しい**（自宅PC対応より優先度が高い作業ですらある）。

廃止手順（案）:

1. Windows側でタスク削除（**実測で確定した値**）:
   `Unregister-ScheduledTask -TaskName 'WSL-Daily-Backup' -TaskPath '\' -Confirm:$false`

   注意: `Setup-BackupScheduler.ps1:239` は `$taskPath = "\CustomBackups\"` と定義しているが、
   **実際に登録されているタスクは `TaskPath = '\'`（ルート直下）**。
   スクリプトのソースを信じて `\CustomBackups\` を指定すると
   「No matching MSFT_ScheduledTask objects found」で失敗する。
   登録が別経路（手動 or 旧バージョン）で行われたと推測される。
2. `scripts/backup/` 一式と `~/.backup-logs/` の削除可否を判断
3. `D:\WSL\backup\` の実データ削除（**13GB 解放**）
4. 既存バックアップから救出したいものが無いか事前確認（下記の注意点あり）

#### 削除前の注意: シンボリックリンクが混在している

バックアップ先の実測で、`/home/aya` 内のシンボリックリンクが
**リンクのまま**コピーされていることを確認した:

```
.aws   -> /mnt/c/Users/368/.aws
.azure -> /mnt/c/Users/368/.azure
```

`rsync -a`（`-l` を含む）の挙動として正しいが、意味するところは:

- **このバックアップは復元用として不完全**。`.aws` / `.azure` の実体は
  `C:\Users\368\` 側にあり、バックアップには含まれていない
- 逆に言えば、削除しても失われるのは「リンクという情報」だけで実データは無傷

つまり廃止判断を後押しする材料。「13GB あるから安心」ではなく、
**13GB 使って一部は中身が入っていない**状態だった。

#### 削除してはいけないもの（実測で確認済み）

`D:\WSL\` 直下の実際の構成:

```
backup/                    ← 13GB。削除対象
wsl-notify-send.exe  3.5M  ← 削除してはいけない
```

- `wsl-notify-send.exe` は WSL からWindowsトースト通知を出すツール。
  **バックアップとは無関係で、他の仕組みが依存している可能性がある**。
  削除するのは `D:\WSL\backup\` **のみ**とし、`D:\WSL\` ごと消さないこと。
- `README.md:185,188` が言及する `wsl --export` の tar（`ubuntu-backup.tar`）や
  `D:\WSL\Ubuntu\`（ディストリ実体）は**存在しない**。
  つまり README に書かれた手順は実行されておらず、
  **丸ごと復元可能な真のバックアップは元から存在しない**。

### 【D】`.claude-global/CLAUDE.md:11` が毎セッションの地雷

> Windows側で見たいファイルは `D:\temp_wsl`（WSLからは `/mnt/d/temp_wsl`）に置くこと

これは全プロジェクトのグローバル指示なので、**自宅PCの全会話で
存在しないパスへの書き込みを指示され続ける**。エージェント側から見て最も踏みやすい。

### 【E】yazi の `gd`

`config/yazi/keymap.toml:5` — `cd /mnt/d`。自宅PCでは移動失敗。軽微だが日常操作。

### 【F】wezterm `has_drive_d()` は会社PCでも false の可能性

`io.open('D:\\', 'r')` は**ディレクトリ**に対して Windows の Lua では nil を返すのが通例。
もし false なら、会社PCで `D:\` 起動が効いているのは #3（`WORKSPACE_TYPE=work`）の方であり、
`has_drive_d()` は**そもそも常に死んでいる**ことになる。

そして `.env` は WSL側・Windows側（`D:\git\dotfiles`）**両方の clone に存在しない**ため、
`WORKSPACE_TYPE` は既定の `'home'` に落ちる。つまり #3 も効いていない。

→ 結論として、会社PCでも `config.default_cwd` は**ホームディレクトリ**になっている計算。
`D:\` 起動を担っている仕組みは現状どこにも無く、`has_drive_d()`（#2）と
`WORKSPACE_TYPE`（#3）の**2系統がどちらも死んでいる**可能性が高い。

未検証部分: `io.open('D:\\', 'r')` がディレクトリに対して実際に何を返すかは
Windows上の wezterm でしか確認できない。実機で起動時 cwd を見るのが最短。

### 【C-2】ヘッドレス実行の可否（回答: バックアップ本体は既にヘッドレス、登録スクリプトが対話式）

「このスクリプトをヘッドレス実行にできるか」への回答。2つを分けて考える必要がある。

| ファイル | 対話要素 | ヘッドレス可否 |
|---|---|---|
| `backup-wsl-to-windows.sh` | `read` / 確認プロンプト **一切なし** | **既にヘッドレス**。`--progress` で出力が冗長なだけ |
| `Setup-BackupScheduler.ps1` | `Read-Host` が **20箇所以上** | 対話専用。ヘッドレス不可 |

つまり**バックアップ本体は既にヘッドレスで動いている**（だから毎朝タスクスケジューラから
無人で実行できている）。実際の登録方式も無人前提:

- `Setup-BackupScheduler.ps1:274` — `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <wrapper>`
- `:276` — もしくは `wsl.exe` を直接 action に指定

ヘッドレス度をさらに上げるなら `rsync` の `--progress` を外して
`--quiet`／`--stats` のみにすればログが3〜12MB→数KBに縮む。
ただし**廃止方針（【C】）なら作業不要**。

`Setup-BackupScheduler.ps1` を非対話化したい場合はパラメータ化（`param()` + デフォルト値）が必要だが、
一度登録すれば再実行しないスクリプトなので投資に見合わない。

### 【G】自宅PCの「Windows側 clone」の置き場所が未定義

`.claude/CLAUDE.md:39,43` は Windows側 clone を `D:\git\dotfiles` と**断定**している。
wezterm / AHK はこの clone を読む前提。だが自宅PCにはDが無い。

**判明（ユーザー確認済み）: 自宅PCにも clone 自体は存在する。ただし置き場所は失念中。**

よって「反映経路が無い」わけではなく、問題は
**ドキュメントに書かれた場所（`D:\git\dotfiles`）と実際の場所が自宅PCで食い違っている**こと。
影響:

- 自宅PCで作業するとき、CLAUDE.md を読んだエージェントは存在しないパスに `cd` しようとする
- ユーザー自身も場所を思い出せない = ドキュメントが役に立っていない

対処: 自宅PCで実パスを特定し、`.claude/CLAUDE.md` の clone 表をマシン別に書き分ける
（あるいは「Windows側 clone のパスは環境依存」と明記して探し方を書く）。

自宅PCでの特定コマンド（PowerShell）:

```powershell
Get-ChildItem -Path C:\ -Filter dotfiles -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { Test-Path "$($_.FullName)\.git" } | Select-Object FullName
```

もしくは WezTerm の設定探索順から逆算する（`wezterm.lua` を読めている場所が答え）。

---

## 分類: 1つの抽象で全部は直せない

| バケット | 対象 | 直し方 |
|---|---|---|
| **①ポータブルパス化できる** | AHK クリップボード temp、`temp_wsl` 受け渡し、バックアップ先、yazi `gd` | 「利用可能な作業ドライブ」を1箇所で解決し、全員がそれを参照 |
| **②Dにデータがある前提で、パス抽象化では直せない** | `ki`/`ko`（zsh.nix:53-54, ps1:38-40）、`/mnt/d/tomcat/webapps/*`（`work-report/SKILL.md:61-62,125,137` / `effort-estimate/SKILL.md:109` / `jar-class-inspect/SKILL.md:27,65` / `fire-daily-review.sh:59,69`） | 直すのではなく**明示的に落とす/スキップする**。自宅PCでは対象外と分かるように |
| **③ドキュメントがDを断定している** | `.claude/CLAUDE.md:39,43,67`、`README.md:92`、`scripts/backup/README.md:5,52,53,87,154,157,158,185,188`、`Setup-BackupScheduler.ps1:322`、`wsl-unc-access/SKILL.md:24,83,86`（`/mnt/d` を例示）、`config/wezterm/.env.template:5` | 「会社PCの場合」と条件を明記 |

③の対象外（意図的に除外）: `docs/superpowers/plans/2026-07-01-work-report.md`、
`docs/superpowers/plans/2026-07-09-effort-estimate.md`、
`docs/superpowers/specs/2026-07-01-work-report-design.md`、
`docs/claude-config-audit-2026-07-27.md` にも `/mnt/d` の記述が多数あるが、
これらは**当時の設計記録・調査記録**なので書き換えない。

### CLAUDE.md 系の全D参照（網羅確認済み）

| ファイル | 行 | 内容 | バケット |
|---|---|---|---|
| `.claude-global/CLAUDE.md` | 11 | `D:\temp_wsl` 受け渡しフォルダ（**全会話に効くグローバル指示**） | ① |
| `.claude/CLAUDE.md` | 39, 43 | Windows側 clone = `D:\git\dotfiles` と断定 | ③（+【G】） |
| `.claude/CLAUDE.md` | 67 | `{{ .hasDriveD }}` を含むので `chezmoi apply` 必須 | ③（記述は正しい） |

`.claude-global/rules/*.md`（external-actions / learned-rules / neovim-style / shell-conventions）に
D参照は**無い**ことを確認済み。

②について: `fire-daily-review.sh:69` の `/mnt/d/tomcat/webapps/*/` は
グロブ非マッチ時にリテラル文字列へ展開されるが、直後の
`[ -e "$repo/.git" ] || continue` で弾かれるため**安全に無視される**。ここは実害なし。

---

## 改善方針（推奨）

### 方針: 「作業ドライブ」を単一の真実の源にする

D固定をやめ、**`WORK_DRIVE`（WSL側 `/mnt/d` or `/mnt/c`、Windows側 `D:\` or `C:\`）を
1箇所で解決し、各設定はそれを参照する**形に寄せる。

段階的に、効果の大きい順で:

| 優先 | 内容 | 対象 |
|---|---|---|
| **0** | 自宅PCの Windows側 clone の実パスを特定し、CLAUDE.md の断定を修正 | 【G】 |
| **1** | AHK の `wslPath` を `gTempDir` から導出（分岐の二重管理をやめる） | 【A】 |
| **2** | `.claude-global/CLAUDE.md` の受け渡しフォルダをドライブ非依存の記述に | 【D】 |
| **3** | **バックアップの廃止**（タスク削除 → スクリプト削除 → `D:\WSL\backup` 削除） | 【C】 |
| **4** | zsh の `ki`/`ko` に存在チェック＋明示的エラーメッセージ | 【B】 |
| **5** | wezterm の `has_drive_d()` を実機検証し、2重定義を1モジュールへ集約 | 【F】 |
| **6** | yazi `gd` を作業ドライブ参照に | 【E】 |
| **7** | skills / docs のD断定箇所に「会社PC限定」注記 | ③ |

【C】は「Dが無ければCへフォールバック」から**廃止**に方針変更（ユーザー判断）。
削除対象が増えるため③の `scripts/backup/README.md` 9箇所も自動的に不要になる。

### 検討したが推奨しない案

- **Nix にホスト別プロファイルを導入**: `flake.nix` は現状単一構成。
  ホスト分岐の導入はDドライブ問題に対して過剰で、`home-manager switch` の運用も複雑化する。
  ランタイム判定（`test -d /mnt/d`）で足りる。
- **wezterm を chezmoi テンプレート化**: `.claude/CLAUDE.md` の明示的な設計方針
  （`git pull` だけで反映）に反する。

---

## 次のアクション

実装は未着手。着手前に確認したいこと:

1. **自宅PCの Windows側 clone の実パス**（【G】。存在は確認済み、場所が不明）
2. 自宅PCで wezterm がどのディレクトリで起動しているか（【F】の検証）
3. バックアップ廃止時、`D:\WSL\backup\` の既存データを削除してよいか（救出対象の有無）

### 決定済み事項（2026-07-30）

| 論点 | 決定 |
|---|---|
| 自宅PCのバックアップ | **不要**。会社PCの定期実行も**廃止**する |
| 廃止理由 | 導入動機（GUIからWSL内を見たい）は `\\wsl$\` で解消済み |
| ヘッドレス化 | バックアップ本体は**既にヘッドレス**。廃止するので対応不要 |
| 自宅PCの Windows clone | **存在する**（パスは要特定） |
