# Thunderbird メールのフォルダ分け設計

Inbox に全部流れ込んでいる状態を、通知系をフォルダへ自動退避して
**Inbox に人間が自分宛に書いたメールだけを残す**構成に変える。

作成日: 2026-08-21 / 対象アカウント: `mori.a@ebase.co.jp`（メイン、ローカル保存）

## 調査で分かった現状

**フォルダは実質未整備。** 振り分け先が存在せず、全て `Inbox` 直行。
`Archives/2026` は1件しか入っておらずアーカイブ運用が機能していない。

**既存フィルタは1本だけ**（`Mail/mss787.kagoya.net/msgFilterRules.dat`）:

```
name="ブロックリスト"  action="Delete"  condition="AND (from,is,support@codezine.jp)"
```

これは維持する。

### 受信しているメールの分布

GitHub 通知の実測（`notifications@github.com`、取得上限100件）:

| 項目 | 値 |
|---|---|
| 100件が占める期間 | 2026-08-17 〜 08-21（**約4日**） |
| ペース | 約 25件/日 |
| repo | `ebase-dev/ebase-portal-chat` 76 / `ebase-dev/ebase-middleware-mcp` 24 |
| 種別 | PR 97 / Issue 3 |
| bot 比率 | **35%**（`claude[bot]` 23 + `github-actions[bot]` 12） |
| セキュリティ/Dependabot/請求 | 0件 |

100件が4日分で埋まっている＝**取得上限に張り付いている**ため、実数はこれより多い。
件数は目安として扱い、設計判断は「機械判定できる属性」で行う。

## 設計方針

### 通知系はフォルダへ、案件はフォルダにしない

| 分類 | 扱い | 理由 |
|---|---|---|
| 通知系（From/To が固定） | **フォルダへ自動退避** | フィルタで決定的に振れる |
| 案件メール（人間同士） | **Inbox に残して検索で拾う** | From/To/件名が案件ごとに定まらず、フィルタが書けない |

案件軸（「ちらし企画」「阪急キッチンエール」等）でフォルダを作ると、中身が人間同士の
メールのため判定条件を書けず、恒久的に手動でドラッグする運用になる。だから作らない。

これは「決定的な処理と非決定的な処理を分離する」の適用。機械判定できるものだけを
フィルタに任せ、できないものは検索に委ねる。

### 作るフォルダとフィルタ条件

すべて `Inbox` 直下のサブフォルダとして作る。

| フォルダ | 判定キー | 条件 |
|---|---|---|
フォルダ名は **ASCII で作る**（理由は下記「フォルダURI」参照）。

| フォルダ | 判定キー | 条件 |
|---|---|---|
| `Kintai`（勤怠） | To | `to,contains,member-repo@ebase.co.jp` |
| `GitHub` | From | `from,contains,notifications@github.com` |
| `GitHub/bot` | From + 表示名 | 下記参照 |
| `GitBucket` | From | `from,contains,no-reply@ebase.co.jp` |
| `PDMeBASE` | From | `from,contains,notice-pdmebase@ebase.co.jp` |
| `eB-schedule` | From | `from,contains,schedule@ebase.co.jp` |
| `Shuho`（週報） | To | `OR (to,contains,weekly_report@ebase.co.jp) (to,contains,ml-dev@ebase.co.jp)` |
| `Souji`（掃除当番） | From | `from,contains,osaka-dev-2f@ebase.co.jp` |

**勤怠は From ではなく To で判定する。** 送信者が社員数十人にばらけるため、
From で書くと必ず取りこぼす。宛先 ML が唯一の安定した判定キー。

**eB-schedule は From で判定し、件名では判定しない。** 件名
`[eB-schedule：予定調整確定]eB-DBPちらし新機能企画レビュー...` のスレッドは、
中身が岩田・大西・松本さんの人間同士のやり取り（＝最も残すべき案件メール）。
件名条件に変えると、この重要スレッドが通知フォルダに吸い込まれる。

**自分が送ったメールも ML 経由で戻り Inbox に入る**（早退連絡等）。これも
`Kintai` に振られるが意図通り。

### GitHub の bot 分離

bot が 35% を占めるため、人間のレビュー依頼と分ける。
**送信元アドレスは全て `notifications@github.com` で共通なので、アドレスでは
人間と bot を区別できない。** 表示名で判定する。

```
condition="AND (from,contains,notifications@github.com) (from,contains,claude[bot])"
```

`github-actions[bot]` も同様に1本足す。**bot 用フィルタを GitHub 全体のフィルタより
先に置く**（Thunderbird はフィルタを上から順に適用するため、先に `GitHub` へ移動されると
bot 判定に到達しない）。

### GitBucket も自分宛を分離する

**bot 分離と同じ構造の問題が GitBucket にもある。** 通知の大半が他人宛
（玉木さんの研修issue一斉assign等）で、その中に自分へのアサインが少数混ざる。

実測（2026-06-21 以降、本文に `森彪人(@mori.a)` を含むもの）:

| 期間 | 自分宛アサイン |
|---|---|
| 約2ヶ月 | **8件**（すべて `hankyu_kitchenyell/ebase-web`） |

同期間の GitBucket 通知総数はこれより桁違いに多い。`GitBucket` へ一括退避すると、
この8件が研修issueの山に埋もれる。

判別キーは本文:

```
condition="AND (from,contains,no-reply@ebase.co.jp) (body,contains,森彪人(@mori.a))"
```

これを `GitBucket` 本体より**上**に置き、`GitBucket/mine` へ振る。

### フォルダURI の形式

```
mailbox://mori.a%40ebase.co.jp@mss787.kagoya.net/Inbox/GitHub
mailbox://mori.a%40ebase.co.jp@mss787.kagoya.net/Inbox/GitHub/bot
```

メールアドレスの `@` は `%40`。

**フォルダ名は ASCII にする。** 表示名と URI セグメントは一致しない例が既にある
（表示名 `ごみ箱` の URI は `.../Trash`）。日本語名は URI がパーセントエンコードされる
可能性があり、mbox のファイル名も化けうる。日本語名を使いたい場合は、作成後に
`mcp__thunderbird__list_folders` で**実際の URI を取得してから** `actionValue` に
書く（推測で書かない）。

## 決定事項

| 論点 | 決定 |
|---|---|
| 案件軸フォルダ | **作らない**（検索で拾う） |
| GitHub の分割 | **bot を分離する**（一度試す。不便なら戻す） |
| GitBucket の分割 | **自分宛を分離する**（`GitBucket/mine`。一度試す） |
| 勤怠ML | **フォルダ退避のみ。購読は止めない** |
| 既存 Inbox の遡り適用 | **やらない**（新着からのみ） |
| Archives | **触らない** |

`Archives/YYYY` は Thunderbird のアーカイブボタンの出力先。ここに案件別サブフォルダを
作るとアーカイブ機能の挙動と衝突するため、今回は対象外とする。

## 適用手順

フィルタはクライアント側（ローカル保存アカウント）で動くため、**既存メールには
遡って適用されない**。新着から効く。

1. Thunderbird で `Inbox` 配下に上記フォルダを作成
2. `mcp__thunderbird__list_folders` で正確な URI を取得
3. ツール → メッセージフィルタ で1本ずつ追加（**bot 用を GitHub より上に配置**）
4. 既存フィルタ「ブロックリスト」は消さない

ファイル直編集より GUI を推奨。フォルダURI のタイプミスは黙って無効化される。

## ロールバック手順

**不便だった場合に戻せるようにしておく。**

### バックアップ（適用前に必ず取る）

Thunderbird を完全終了してから:

```bash
P="/mnt/c/Users/368/AppData/Roaming/Thunderbird/Profiles/afhbv27s.default-release"
cp "$P/Mail/mss787.kagoya.net/msgFilterRules.dat" \
   "$P/Mail/mss787.kagoya.net/msgFilterRules.dat.bak-20260821"
```

### 部分的に戻す（bot 分離だけやめる等）

ツール → メッセージフィルタ で該当フィルタの**チェックを外す**（削除しない）。
`enabled="no"` になるだけで条件は残るので、また試したくなったら戻せる。

フォルダに溜まったメールを Inbox に戻すには、フォルダ内で全選択して Inbox へ移動。

### 全部戻す

1. Thunderbird を完全終了
2. バックアップを復元:
   ```bash
   cp "$P/Mail/mss787.kagoya.net/msgFilterRules.dat.bak-20260821" \
      "$P/Mail/mss787.kagoya.net/msgFilterRules.dat"
   ```
3. 各フォルダのメールを全選択して `Inbox` へ移動
4. 空になったフォルダを削除

**起動中にファイルを書き換えると終了時に上書きされて消える。** 必ず完全終了してから。

## 補足: この設計で拾えないもの

案件メールは Inbox に残るため、探すときは検索を使う。`mcp__thunderbird__search_messages`
を使う場合の注意:

- `query` は**本文も検索する**。`query: "eB-schedule"` は署名の
  「eB-scheduleに記載の通り」に大量ヒットして役に立たない
- 送信元で絞るなら `from` パラメータを使う
- `limit` の上限は 100。分布を数える用途では天井に張り付く

## 関連

- `.claude-global/skills/thunderbird-config/SKILL.md` — プロファイル場所・フィルタ書式
- `config/thunderbird/README.md` — 配色の設計とハマりどころ
