---
name: thunderbird-config
description: Use when working on Thunderbird — mail folders, message filters, colors/theme, prefs, or locating the profile. Answers "where does Thunderbird actually live", "where are the filters stored", "how do I restart and verify". Triggers include "Thunderbirdの設定", "メールフィルタを追加", "メールのフォルダ分け", "サンダーバードの配色", "プロファイルどこ".
version: 1.0.0
---

# thunderbird-config

## Overview

Thunderbird の設定をどこで触るかの道案内。**本体は Windows 側で動いており、WSL に `~/.thunderbird` は存在しない。** 触る対象ごとに実体の置き場所が違うので、まずここで担当を確認する。

## 実体の場所

**プロファイル（Windows 側）:**

```
/mnt/c/Users/368/AppData/Roaming/Thunderbird/Profiles/afhbv27s.default-release
```

Windows から見ると `C:\Users\368\AppData\Roaming\Thunderbird\Profiles\afhbv27s.default-release`。
同ディレクトリに `qe8uw2tf.default` もあるが、使用中は `default-release` の方。
（確定したいときは `profiles.ini` の `Default=` を見る）

## 担当の切り分け

| 触りたいもの | 実体 | dotfiles 管理 |
|---|---|---|
| 配色・本文スタイル | `config/thunderbird/chrome/userContent.css` | ○ |
| 配色・UI 補正 | `config/thunderbird/chrome/userChrome.css` | ○ |
| pref（起動時に読む設定） | `config/thunderbird/user.js` | ○ |
| **メッセージフィルタ** | プロファイル内 `msgFilterRules.dat` | **×（管理外）** |
| **フォルダ構成** | プロファイル内 `Mail/` 配下の実ファイル | **×（管理外）** |
| **フォルダの色** | プロファイル直下 `folderTree.json` の `colors` | **×（管理外）** |
| アカウント設定 | プロファイル内 `prefs.js` | ×（管理外） |

配色系を触るなら **`config/thunderbird/README.md` を読む**。ハマりどころ（白背景の再発、
Conversations アドオンの invert、引用色の詳細度勝負）と検証ツールの使い方が全部書いてある。

## メッセージフィルタの置き場所

アカウントごとに別ファイル。**メインアカウント（mori.a、ローカル保存）はここ:**

```
<プロファイル>/Mail/mss787.kagoya.net/msgFilterRules.dat
```

他にも同名ファイルがあるが担当が違う:

| パス | 担当 |
|---|---|
| `Mail/mss787.kagoya.net/` | mori.a@ebase.co.jp（メイン、`mailbox://`） |
| `ImapMail/mss787.kagoya.net/` | claude-code@ebase.co.jp（IMAP） |
| `Mail/Local Folders/` | ローカルフォルダ |
| `Mail/mss787.kagoya-1.net/` | 旧・未使用 |

### 書式

```
version="9"
logging="no"
name="フィルタ名"
enabled="yes"
type="1"
action="Move to folder"
actionValue="mailbox://mori.a%40ebase.co.jp@mss787.kagoya.net/Inbox/フォルダ名"
condition="AND (from,contains,notifications@github.com)"
```

- 1フィルタ = `name` から `condition` までのブロック。追記は末尾に足す
- `type` はビットマスク。既存の値をそのまま真似るのが安全（GUI で1本作って確認する）
- `actionValue` のフォルダURIは**メールアドレスの `@` を `%40`** にする
- **複数条件は演算子を全項に反復する**: `AND (a) AND (b)` / `OR (a) OR (b)`。
  非反復形 `OR (a) (b)` はエラーを出さず **AND として解釈される**（2026-08-25 実測）。
  GUI で開いたとき「すべての条件に一致」になっていたら非反復形を疑う
- **From はアドレス完全一致の `is` ではなく `contains`。** 実ヘッダは
  `CodeZine編集部 <support@codezine.jp> CodeZine編集部` のように表示名が付くため
  `is` では当たらない
- 条件値に `(` を含む場合は閉じ括弧を明示する（`森彪人(@mori.a)` → 括弧数を数えて検証）
- **フォルダURIは推測で書かない。** 表示名と URI セグメントは一致しない例がある
  （表示名 `ごみ箱` → `.../Trash`）。`list_folders` で実際の値を取得する
- フィルタは**上から順に適用される**。絞り込みの細かいものを先に置く
  （例: bot 用を GitHub 全体より上に）

### 編集時の必須手順

**Thunderbird を完全終了してから編集する。** 起動中に書き換えると終了時に
メモリ上の内容で上書きされて消える。

フィルタ追加はできれば GUI（ツール → メッセージフィルタ）を使う。ファイル直編集は
フォルダURIのタイプミスが黙って無効化されるので、GUI で1本作って書式を確認してから
真似るのが安全。

## フォルダの色

`folderTree.json`（プロファイル直下）の `colors` セクション。GUI の色設定はここに
保存される。**`userChrome.css` で書く必要はない。**

```json
{
  "open": { "all": [ "..." ] },
  "colors": {
    "mailbox://mori.a%40ebase.co.jp@mss787.kagoya.net/Inbox/%E9%96%8B%E7%99%BA": "#89b4fa"
  }
}
```

フォルダURI → HEX の単純なマップ。日本語名はパーセントエンコードされる
（`開発` = `%E9%96%8B%E7%99%BA`）。**URI は推測せず `list_folders` で実値を取る。**

このファイルも終了時に書き戻されるため、**編集は完全終了後**に行う。

> GUI で設定できる項目は、たいていプロファイル内のどこかのファイルに落ちている。
> CSS で無理に再現する前に、`/usr/bin/ls -lat <プロファイル>` で更新日時順に並べて
> 「その操作で何が書き換わったか」を探すのが速い。

## 反映と再起動

`user.js` と CSS は**起動時のみ**読まれる。完全終了してから再起動する。

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File 'D:\git\dotfiles\scripts\thunderbird-dev\tb-restart.ps1'
```

## メールの読み取り・調査

メールの中身を調べるなら `mcp__thunderbird__*` ツールを使う（読み取り専用）。

| ツール | 用途 |
|---|---|
| `list_folders` | フォルダ一覧＋URI（`actionValue` に使う正確なURIが取れる） |
| `list_recent` | 直近のメールを日付降順で |
| `search_messages` | 本文・件名の部分一致（`from` / `folder` / `after` で絞れる） |

**注意点:**

- `limit` は最大 100。分布を数えると天井に張り付くので、件数を実数として扱わない
- `search_messages` の `query` は**本文も見る**。`query: "eB-schedule"` は署名の
  「eB-scheduleに記載の通り」に大量ヒットする。送信元で分類したいなら `from` を使う
- 結果が大きいとファイルに退避される。その場合はサブエージェントに読ませる

## 関連ドキュメント

| ドキュメント | 内容 |
|---|---|
| `config/thunderbird/README.md` | 配色の設計・ハマりどころ・検証ツール |
| `docs/thunderbird-mail-folders.md` | フォルダ分けとフィルタの設計、ロールバック手順 |

## 落とし穴

- **WSL に `~/.thunderbird` は無い。** Windows 側のプロファイルを見る
- **リンク元は `D:\git\dotfiles`。** `\\wsl$\...` を指すと Thunderbird から読めない
- **配色を触る前に README を読む。** 白背景・invert・詳細度の3つは既に原因が特定
  されており、知らずに触ると対症療法を重ねることになる
- **メインアカウントはローカル保存（`mailbox://`）。** フィルタはクライアント側で
  動くので、既存メールには遡って適用されない（手動実行が必要）
- **`ls -lat` は eza エイリアスで失敗する。** 更新日時順に見るときは `/usr/bin/ls -lat`
- **スクショはウィンドウハンドルを指定しても前面のウィンドウが写ることがある。**
  設定ファイル側で検証できるならそちらで確認するほうが速い
