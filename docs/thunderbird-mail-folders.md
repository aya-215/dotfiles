# Thunderbird メールのフォルダ分け

Inbox に全部流れ込んでいた状態を、通知系をフォルダへ自動退避して
**Inbox に人間が自分宛に書いたメールだけを残す**構成にした。

適用日: 2026-08-21 / 対象アカウント: `mori.a@ebase.co.jp`（メイン、ローカル保存）

## 構成

```
受信トレイ
├── 開発
│   ├── GitHub
│   │   ├── 自分宛      @eBASE-Mori メンション
│   │   └── bot         claude[bot] / github-actions[bot]
│   ├── GitBucket
│   │   └── 自分宛      森彪人(@mori.a) アサイン
│   └── 課題DB          PDMeBASE
└── 連絡
    ├── 勤怠            member-repo@ 宛
    ├── スケジュール    schedule@
    ├── 週報            weekly_report@ / ml-dev@
    └── 掃除            osaka-dev-2f@
```

`GitHub` と `GitBucket` の両方に `自分宛` を置いて**運用を揃えている**。
片方だけサブフォルダを見る形にすると、同じ「開発通知」なのに見る場所が変わって混乱する。

## 設計方針

### 通知系はフォルダへ、案件はフォルダにしない

| 分類 | 扱い | 理由 |
|---|---|---|
| 通知系（From/To/本文が固定） | **フォルダへ自動退避** | フィルタで決定的に振れる |
| 案件メール（人間同士） | **Inbox に残して検索で拾う** | From/To/件名が案件ごとに定まらず、フィルタが書けない |

案件軸（「ちらし企画」「阪急キッチンエール」等）でフォルダを作ると、中身が人間同士の
メールのため判定条件を書けず、恒久的に手動でドラッグする運用になる。だから作らない。

機械判定できるものだけをフィルタに任せ、できないものは検索に委ねる。

### 大量通知の中から自分宛を救い出す

GitHub / GitBucket はどちらも「通知の大半が自分に無関係」という同じ構造を持つ。
親フォルダへ一括退避すると、自分が対応すべきものが埋もれる。

| 系統 | ノイズの正体 | 自分宛の判定キー |
|---|---|---|
| GitHub | bot が 35%（`claude[bot]` / `github-actions[bot]`） | 本文の `@eBASE-Mori` |
| GitBucket | 他人宛の一斉assign（研修issue等） | 本文の `森彪人(@mori.a)` |

**送信元アドレスでは人間と bot を区別できない。** GitHub 通知は全て
`notifications@github.com` から来るため、表示名か本文で判定する。

## フィルタ（12本）

`Mail/mss787.kagoya.net/msgFilterRules.dat`。**上から順に適用される。**

| # | 名前 | 条件 | 移動先 |
|---|---|---|---|
| 1 | ブロックリスト | `from,is,support@codezine.jp` | 削除（既存） |
| 2 | GitHub bot (claude) | `AND` from:`notifications@github.com` + from:`claude[bot]` | 開発/GitHub/bot |
| 3 | GitHub bot (actions) | `AND` from:`notifications@github.com` + from:`github-actions[bot]` | 開発/GitHub/bot |
| 4 | GitHub 自分宛 | `AND` from:`notifications@github.com` + body:`@eBASE-Mori` | 開発/GitHub/自分宛 |
| 5 | GitHub | from:`notifications@github.com` | 開発/GitHub |
| 6 | GitBucket 自分宛 | `AND` from:`no-reply@ebase.co.jp` + body:`森彪人(@mori.a)` | 開発/GitBucket/自分宛 |
| 7 | GitBucket | from:`no-reply@ebase.co.jp` | 開発/GitBucket |
| 8 | 課題DB | from:`notice-pdmebase@ebase.co.jp` | 開発/課題DB |
| 9 | スケジュール | from:`schedule@ebase.co.jp` | 連絡/スケジュール |
| 10 | 勤怠 | to:`member-repo@ebase.co.jp` | 連絡/勤怠 |
| 11 | 週報 | `OR` to:`weekly_report@` + to:`ml-dev@` | 連絡/週報 |
| 12 | 掃除 | from:`osaka-dev-2f@ebase.co.jp` | 連絡/掃除 |

### 順序が重要な箇所

**bot（2・3）は自分宛（4）より上。** claude[bot] のメール本文には
`Claude finished @eBASE-Mori's task` が含まれるため、順序を逆にすると bot 通知が
`自分宛` に混ざる。

**自分宛（4・6）は親（5・7）より上。** 先に親へ移動されると自分宛の判定に到達しない。

### 判定キーの選択理由

**勤怠は From ではなく To。** 送信者が社員数十人にばらけるため、From では必ず取りこぼす。
宛先 ML が唯一の安定した判定キー。自分が送った早退連絡も ML 経由で戻り `勤怠` に入るが、
これは意図通り。

**スケジュールは From で判定し、件名では判定しない。** 件名
`[eB-schedule：予定調整確定]eB-DBPちらし新機能企画レビュー...` のスレッドは、中身が
岩田・大西・松本さんの人間同士のやり取り（＝最も残すべき案件メール）。件名条件にすると
この重要スレッドが通知フォルダに吸い込まれる。

## フォルダの色

`folderTree.json` の `colors` セクション（プロファイル直下）。**フォルダURI → HEX の
単純なマップ**で、GUI の色設定はここに保存される。`userChrome.css` は不要。

配色は Catppuccin Mocha。軸は「対応が必要か」の4階調。比は背景 `base #1e1e2e` に対する
コントラスト比。

| 階調 | 色 | 比 | 対象 |
|---|---|---|---|
| 要対応 | `#f38ba8` red | 7.08:1 | GitHub/自分宛、GitBucket/自分宛 |
| 要対応 | `#fab387` peach | 9.27:1 | 課題DB |
| 見る | `#89b4fa` blue | 7.79:1 | 開発、GitHub、GitBucket |
| 見る | `#a6e3a1` green | 11.03:1 | 連絡、スケジュール |
| 沈める | `#9399b2` overlay2 | 5.81:1 | 勤怠、週報、掃除 |
| 最も沈める | `#7f849c` overlay1 | 4.44:1 | GitHub/bot |

`自分宛` を両方とも同じ赤にして、「GitHub でも GitBucket でも自分宛は赤」で
覚えられるようにしている。

### グレーに surface 帯を使わない

当初 `surface2 #585b70`（勤怠・週報・掃除）と `overlay0 #6c7086`（bot）を当てたが、
**それぞれ 2.46:1 / 3.36:1 で AA 基準 4.5:1 を大きく割り、読めなかった。**

Catppuccin の `surface` 帯は面・境界用で、文字色に使う色ではない。「沈める」意図でも
文字として置くなら `overlay1` 以上を使う。同じ問題は
`config/thunderbird/README.md`「テーマだけでは補えない箇所」にも記録がある
（作成ウィンドウのラベルが `overlay1` で 4.44:1 だったため `subtext0` に上げた）。

色を決めるときは実測する:

```bash
python3 -c "
def lum(h):
    h=h.lstrip('#'); c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    c=[x/12.92 if x<=0.03928 else ((x+0.055)/1.055)**2.4 for x in c]
    return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]
def r(a,b):
    la,lb=lum(a),lum(b); return (max(la,lb)+0.05)/(min(la,lb)+0.05)
print(f'{r(\"#9399b2\", \"#1e1e2e\"):.2f}:1')
"
```

書式:

```json
"colors": {
  "mailbox://mori.a%40ebase.co.jp@mss787.kagoya.net/Inbox/%E9%96%8B%E7%99%BA": "#89b4fa"
}
```

日本語フォルダ名はパーセントエンコードされる（`開発` = `%E9%96%8B%E7%99%BA`）。
**URI は推測せず** `mcp__thunderbird__list_folders` で実値を取得する。

## 決定事項

| 論点 | 決定 |
|---|---|
| 案件軸フォルダ | 作らない（検索で拾う） |
| GitHub / GitBucket の分割 | 両方に `自分宛` を置いて運用を揃える |
| bot の扱い | `GitHub/bot` に隔離（GitBucket に bot 通知は無い） |
| 課題DB の位置 | `開発` 配下（作業依頼なので開発寄り） |
| 勤怠ML | フォルダ退避のみ。購読は止めない |
| 既存 Inbox の遡り適用 | やらない（新着からのみ） |
| Archives | 触らない |

`Archives/YYYY` は Thunderbird のアーカイブボタンの出力先。ここに案件別サブフォルダを
作るとアーカイブ機能の挙動と衝突するため対象外。

## 編集時の注意

**Thunderbird を完全終了してから編集する。** `msgFilterRules.dat` と
`folderTree.json` はどちらも終了時にメモリ上の内容で書き戻されるため、起動中に
書き換えると消える。

フィルタの移動先URIが誤っていると**黙って無効化される**（エラーは出ない）。
書き換えたら実体と照合する:

```bash
P="/mnt/c/Users/368/AppData/Roaming/Thunderbird/Profiles/afhbv27s.default-release/Mail/mss787.kagoya.net"
grep 'actionValue' "$P/msgFilterRules.dat" \
  | sed 's|.*/Inbox/||; s|"$||' \
  | python3 -c "
import sys, urllib.parse, os
base='$P/Inbox.sbd'
for line in sys.stdin:
    p = urllib.parse.unquote(line.strip())
    parts = p.split('/')
    fs = os.path.join(base, *[x+'.sbd' for x in parts[:-1]], parts[-1])
    print(('OK  ' if os.path.exists(fs) else 'NG  ') + p)
"
```

## バックアップ

| ファイル | 中身 |
|---|---|
| `msgFilterRules.dat.bak-20260821` | **適用前**（ブロックリスト1本のみ） |
| `msgFilterRules.dat.bak-20260821-12rules` | 中間（フォルダ名が英語 `mine` の時点） |
| `folderTree.json.bak-20260821` | 色設定の適用前 |

## ロールバック

### 一部だけ戻す

ツール → メッセージフィルタ で該当フィルタの**チェックを外す**（削除しない）。
`enabled="no"` になるだけで条件は残るので、また試せる。

フォルダに溜まったメールは、フォルダ内で全選択して `受信トレイ` へ移動。

### 全部戻す

1. Thunderbird を**完全終了**
2. バックアップを復元:
   ```bash
   PR="/mnt/c/Users/368/AppData/Roaming/Thunderbird/Profiles/afhbv27s.default-release"
   cp "$PR/Mail/mss787.kagoya.net/msgFilterRules.dat.bak-20260821" \
      "$PR/Mail/mss787.kagoya.net/msgFilterRules.dat"
   cp "$PR/folderTree.json.bak-20260821" "$PR/folderTree.json"
   ```
3. 各フォルダのメールを全選択して `受信トレイ` へ移動
4. 空になったフォルダを削除

## 補足: 案件メールの探し方

案件メールは Inbox に残るため、探すときは検索を使う。
`mcp__thunderbird__search_messages` の注意点:

- `query` は**本文も検索する**。`query: "eB-schedule"` は署名の
  「eB-scheduleに記載の通り」に大量ヒットして役に立たない
- 送信元で絞るなら `from` パラメータを使う
- `limit` の上限は 100。分布を数える用途では天井に張り付く

## 関連

- `.claude-global/skills/thunderbird-config/SKILL.md` — プロファイル場所・フィルタ書式
- `config/thunderbird/README.md` — 配色の設計とハマりどころ
