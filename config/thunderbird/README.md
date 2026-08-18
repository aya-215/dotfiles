# Thunderbird 設定

メール本文とUIの配色を Catppuccin Mocha に揃える。

## 構成

配色は **UI と本文で担当が分かれる**。テーマは chrome（UI）のみを対象とし、
メール本文は `type="content"` の別文書として描画されるため Theme API が届かない。

| 範囲 | 担当 | 実体 |
|---|---|---|
| UI（メール一覧・フォルダペイン・ツールバー・設定画面） | Catppuccin テーマ | `.xpi` アドオン |
| メール本文 | `chrome/userContent.css` | このリポジトリ |
| 有効化に必要な pref | `user.js` | このリポジトリ |

## ファイル

| ファイル | 配置先 | 役割 |
|---|---|---|
| `user.js` | プロファイル直下 | 起動時に読まれる pref |
| `chrome/userContent.css` | プロファイル `chrome/` | メール本文のスタイル（コンテンツ文書） |
| `chrome/userChrome.css` | プロファイル `chrome/` | UI の補正（chrome:// 文書） |

`userContent.css` はコンテンツ文書（`type="content"`）専用。作成ウィンドウのように
`chrome://` で読み込まれるウィンドウは `userChrome.css` の管轄。

## 配置方法（暫定: シンボリックリンク）

調整中はシンボリックリンクで繋ぐ。編集が即反映され、Thunderbird の再起動だけで
確認できる（`chezmoi apply` が不要）。

```powershell
cd D:\git\dotfiles
powershell -ExecutionPolicy Bypass -File .\scripts\link-thunderbird.ps1
```

**リンク元は `D:\git\dotfiles`（Windows側clone）である必要がある。**
`\\wsl$\...` 配下を指すと Thunderbird から読めない。

**編集も Windows側 clone で行い、そこでコミットして WSL 側で pull する。**
逆方向にコピーすると改行コードの差分が出る（`.gitattributes` で LF に固定済み）。

固まったら chezmoi の `run_onchange_` でのコピー配布に移行する。

### Catppuccin テーマ（UI側）

`.xpi` は https://github.com/catppuccin/thunderbird で配布されている。
Mocha × アクセント14色。**mocha-blue** を使用中。

```
設定 → アドオンとテーマ → 歯車アイコン → 「ファイルからアドオンをインストール」
→ themes/mocha/mocha-blue.xpi
```

プロファイルの `extensions/` に直接置く方法は避ける。`extensions.json` への登録と
`activeThemeID` の書き換えが必要で、GUI からの方が確実（実際に試したが
`theme_experiment` の扱いで見た目が反映されなかった）。

## 反映

Thunderbird を**完全終了してから再起動**する（`user.js` と CSS は起動時のみ読まれる）。

## user.js の各 pref

### `toolkit.legacyUserProfileCustomizations.stylesheets = true`

TB115+ では `userChrome.css` / `userContent.css` がデフォルト無効。有効化に必須。

### `mail.dark-reader.enabled = true`

本文をダークモード化する。`DarkReader.mjs` の実装は**色の変換ではなく削除**:

```js
const LUMINANCE_THRESHOLD = 200;
if (luminance(style.color) <= LUMINANCE_THRESHOLD) {
  style.removeProperty("color");
}
```

対象はノードのインライン `style` 属性と、メール内 `<style>` タグの CSS ルール。
これによりライト前提の HTML メール（GitHub 通知等）の黒文字が消える。
`userContent.css` はユーザーオリジンなのでこの削除処理の対象外。

### `layout.css.prefers-color-scheme.content-override = 1`

**最も重要な設定。** 内蔵 `messageBody.css` のダークモードブロックは

```css
@media (prefers-color-scheme: dark) and -moz-pref("mail.dark-reader.enabled") {
  html { background-color: var(--color-gray-90); color: var(--color-text-base-dark); }
}
```

の2条件 AND。未設定（システム追従）だとメッセージペインではライトに解決され、
**本文だけ白背景・黒文字・暗い引用色**になる。`1` で dark を強制して成立させる。

この1点で「背景が白い」「文字が黒い」「引用が暗い青」の全症状が説明できる。
これを知る前は個別の症状に対症療法（`transparent` の総当たり、色の全要素上書き、
`opacity` 打ち消し）を重ねてしまったが、いずれも不要だった。

## CSS 実装のポイント

### 背景は `body` のみに当てる

`html` に `background-color` を当てると**白背景が再発する**（実測 `#e4e3ea` 25.3%）。
内蔵 `messageBody.css` がダークモード時に `html` へ背景を敷いているため、
そこを奪うと描画と dark-reader の処理が競合して送信元の白背景が露出する。
`html` は内蔵に任せ、`body` だけを指定する。

`color` は無関係（`background-color` 単独でも再現する）。

### `html body *` は `body` 自身に当たらない

背景や色を全体に当てるなら `html, body` を**単独で列挙**する。
`html body *` は body の子孫のみが対象。

### 引用色は詳細度で内蔵CSSを越える

内蔵 `chrome/classic/skin/classic/messenger/messageQuotes.css` が

```css
body blockquote[type="cite"] {
  color: var(--color-text-highlight) !important;
}
```

を当てている。`!important` 同士では詳細度勝負になる:

| | セレクタ | 詳細度 |
|---|---|---|
| 内蔵 | `body blockquote[type="cite"]` | (0,1,2) |
| Conversations | `blockquote[type="cite"]` | (0,1,1) |
| このCSS | `html body blockquote[type="cite"]` | **(0,1,3)** |

`blockquote[type=cite]` だけでは (0,1,1) で負ける。**セレクタが当たらないのではなく
負けている**ため、色を変えても何も起きない（この切り分けに時間を要した）。

### ネストした引用にも `type="cite"` が付く

GitHub の先例（`dllud/Dorian-3.14` 等）は2段目以降を `blockquote`（type 指定なし）で
書いているが、TB153 では**ネストにも `type="cite"` が付く**。先例は古いバージョン向け。

## Thunderbird Conversations アドオンへの対処

**これが最大の落とし穴。** アドオンが本文の描画に介入するため、
`userContent.css` だけでは制御できない。

Conversations（v4.3.10）は本文を **iframe に描画**し、`injectCss()` で以下を
iframe 内に注入する（`content/stub.bundle.js:6120`）:

```js
'blockquote[type="cite"] {',
"  border-left: 1px #ccc solid;",
"  color: #666 !important;",          // 引用色をハードコード
"}",
...
`@media screen and (prefers-color-scheme: dark) {
    html.darkReaderEnabled > body {
      filter: invert(100%) hue-rotate(180deg) !important;   // 本文全体を色反転
      background: rgb(28, 27, 34) !important;
    }
    html.darkReaderEnabled > body :is(img, ...) {
      filter: invert(100%) hue-rotate(180deg) !important;   // 画像は二重反転で戻す
    }
}`
```

### `invert` により明るい色を指定するほど暗く表示される

`mail.dark-reader.enabled = true` にしていると `html.darkReaderEnabled` が付き、
**本文全体が色反転される**。実測と計算が一致した:

| 指定色 | invert+hue-rotate 後の計算値 | 実測値 |
|---|---|---|
| `#bac2de` (L=194.3) | L=56.3 | **L=60.3** |
| `#a6adc8` (L=173.5) | L=77.6 | **L=77.8** |

このため「暗いので明るくする」を繰り返すと逆に暗くなる。
対処は `filter: none !important` で打ち消す（`userContent.css` はユーザーオリジンの
ため author origin の注入 `<style>` に勝てる）。

**画像側の invert も併せて打ち消す**必要がある。本体の invert を消したまま
画像の二重反転を残すと、画像だけ反転して表示される。

### `tweak_bodies` 設定では解決しない

設定画面の「メッセージフォントを調節」（`tweak_bodies`）は `tweakFonts()` を
無効化するが、`injectCss()` は**それとは独立に常に実行される**。
オフにしても invert は残る（実際に試して変化なしを確認）。

ただし `tweak_bodies` をオフにすると `tweakFonts()` 内の

```js
"body:has(> .moz-text-html) { color: " + fg + "; }"
```

が出なくなり、**地の文が黒くなる**。このため `userContent.css` 側で
`body`, `div`, `p`, `span`, `td`, `pre` に色を明示している。

### 折りたたみ（`hide_quote_length`）は無関係

`createToggleForNode()` は `display: none` / `display: ""` の切り替えのみで、
色や opacity を触らない（実装で確認）。デフォルト値は `hide_quote_length: 5`。

## 配色の設計

Catppuccin 公式スタイルガイドの役割定義に従う。

| 色 | 役割 |
|---|---|
| `text` | 本文（Body Copy） |
| `subtext0/1` | ラベル・小見出し |
| `overlay2` | コメント |
| `overlay1` | 控えめな文字 |
| `surface0/1/2` | 面・境界 |

### 実際の値

| 用途 | 色 | 背景比 |
|---|---|---|
| 背景 | `base #1e1e2e` | — |
| 地の文 | `text #cdd6f4` | 11.34:1 |
| リンク | `blue #89b4fa` | 7.79:1 |
| 訪問済みリンク | `lavender #b4befe` | 9.17:1 |
| mailto / 引用内リンク | `sky #89dceb` | 10.54:1 |
| 引用 1段目 | `#aab4ee` | 8.18:1 |
| 引用 2段目 | `#9aa3d9` | 6.73:1 |
| 引用 3段目 | `#7f88b0` | 4.73:1 |
| 引用の枠線 | `surface2 #585b70` | 2.46:1 |

背景 `base #1e1e2e` は**テーマのメール一覧背景と同値**にして境目を消している。

### 引用は lavender 帯で色味を持たせ、深くなるほど彩度を落とす

彩度 67% → 45% → 24% と推移させ、グレーへ寄せる。テーマのアクセントが blue のため
同じ色相帯の lavender を使い UI と調和させる。1段目の彩度は本文（64%）と同程度に
抑え、引用が本文より鮮やかにならないようにする。

色相はリンク（blue 217°）と引用（lavender 232°）で15°離れており区別できる。

### 枠線に複数のアクセント色を並べない

当初 1段目=green / 2段目=peach / 3段目=teal としたが、**線が文字より目立って**
バランスが崩れた（測定時に引用の文字ではなく枠線の色を拾ってしまうほど）。

Catppuccin 公式テーマも境界には彩度を使わず surface 帯を当てている
（`sidebar_border` / `toolbar_top_separator` はいずれも `surface0`。
アクセント色は `toolbar_field_border_focus` のようなフォーカス時のみ）。
公式の「Rainbow Highlights」は括弧の対応やパラメータ専用で、引用のネストには適用しない。

### 訪問済みリンクに mauve は使えない

`a:visited` に `mauve #cba6f7` を指定すると `#633e8f`（L=75.7）まで暗く潰れる。
ブラウザは `:visited` に適用できるスタイルを制限するため。`lavender` を使う。

## 文字の太さ

`HackGen Console NF` は Regular(400)/Bold(700) の2ウェイトのみで、
`font-weight` の中間値は丸められる。無段階に太らせるには `-webkit-text-stroke` を使う。

```css
html, body { -webkit-text-stroke: 0.2px currentColor; }
```

`0.15px` / `0.2px` / `0.3px` を実機で比較して `0.2px` を採用。
`gfx.font_rendering.cleartype_params.gamma`（デフォルト2200、下げると太く見える）も
同種の調整手段だが、今回は CSS 側で足りている。

## 検証方法

**必ず受信トレイの3ペイン表示で確認する。** `.eml` を直接開いた専用ウィンドウは
表示条件が異なり、本文の白背景問題が再現しない（この差に気づかず誤判定した）。

TB再起動でメールの選択が外れると、ウェルカム画面（背景 `#000000` が約48%）が
表示される。この状態の数値は本文の評価に使えない。

`mail.citation_color` は正しい pref 名だが（`mailnews.` ではない）、
この値はインライン style で焼き込まれるため dark-reader に削除される。使用しない。

## テーマだけでは補えない箇所（userChrome.css）

Catppuccin テーマは chrome の変数を書き換えるが、**システム色キーワード
（`Canvas` / `-moz-Dialog` 等）や、TB が別用途の変数を流用している箇所**は
テーマだけでは変わらない。それらを `chrome/userChrome.css` で補正する。

### メッセージ作成ウィンドウのヘッダーラベル

「差出人」「宛先」「件名」のラベルが `overlay1 #7f849c`（背景比 **4.44:1**、
AA 基準 4.5:1 を割る）で描かれ読みにくかった。

出どころは Catppuccin テーマの

```json
"tab_text":            "#cdd6f4",   // アクティブなタブの文字
"tab_background_text": "#7f849c",   // 非アクティブなタブの文字 ← これ
```

`tab_background_text` は本来「非アクティブなタブの文字色」で、
Catppuccin が控えめな `overlay1` を割り当てるのは設計として妥当。
問題は **Thunderbird がこの値を作成ウィンドウのラベルにも流用している**こと。
テーマ側の意図とラベルに必要な可読性がずれている。

対処: ラベルを `subtext0 #a6adc8`（7.37:1）に、プレースホルダを
`overlay2 #9399b2`（5.81:1）に上げる。**タブの文字色は触らない**ため、
非アクティブタブの見た目は保たれる。

公式スタイルガイドでもラベル・小見出しは subtext0/1 の担当。

## Conversations の Quick Reply（返信 / 全員に返信 ボタン）

`userContent.css` 側で対処している。本文 iframe の**外側**にあり、
`chrome://conversations/content/stub.html` という別文書。
`messagepane` が `type="content"` のため `@-moz-document url-prefix(...)` で
URL を指定すれば `userContent.css` が届く。

`quickreply.css` が当てているのは:

```css
:root { --border-color: light-dark(#d4d4d8, #3f3f46); }
.replyBox {
  background-color: Canvas;              /* システム色 = TB既定の #1c1b22 */
  color: -moz-nativehyperlinktext;
  border: 1px solid var(--border-color);
}
```

`Canvas` はシステム色キーワードのため、テーマの変数書き換えでは変わらない。

### 背景を mantle にすると浮く

当初 Quick Reply の背景を `mantle #181825` にして「一段暗くして区切る」
意図だったが、上下の領域が `base #1e1e2e` のため以下の順序になり違和感が出た:

| 位置 | 明度 |
|---|---|
| 上部の帯 | L=31.2 (base) |
| Quick Reply 背景 | **L=24.9 (mantle)** |
| ボタン | L=51.1 (surface0) |
| 最下部 | L=31.2 (base) |

**暗い帯の中に明るいボタンが浮く**形になり、上下との段差が目立つ。
Catppuccin の `mantle` は二次的なペイン用で、同一階層内の帯には使わない。
背景は `base` のままにし、**ボタンだけを `surface0` で持ち上げる**のが正しい。

あわせて TB 内蔵の `#3f3f46`（gray70）が区切り線に残るため `surface0` に寄せる。

## 残っている改善余地（未着手）

現状は動作しているため保留。問題が再発した際の検討材料として記録する。

### 1. `filter: none` による invert 打ち消しは対症療法

Conversations が `invert` を掛ける前提を打ち消しているだけで、
**アドオンが更新されると壊れる可能性がある**。`injectCss()` は設定と独立に
常に実行されるため、アドオン側でオフにする手段がない。
上流に issue を立てるのが本来の筋。

壊れた場合の切り分け手順:
1. `content/stub.bundle.js` の `injectCss()` を再確認（注入内容が変わった可能性）
2. Conversations を一旦無効化して指定色が出るか確認（出れば原因はアドオン側で確定）

### 2. 地の文の要素列挙に漏れの可能性

```css
body, body div, body p, body span, body td, body pre { color: ... }
```

`li` / `th` など列挙外の要素で送信元の色が残る可能性がある。

これは `tweak_bodies` をオフにしていることの副作用。`tweak_bodies` は当初
invert の原因と疑ってオフにしたが、**実際には無関係と判明した**（invert は
`injectCss()` 側）。オンに戻せば Conversations 側が

```js
"body:has(> .moz-text-html) { color: " + fg + "; }"
```

を出すため、この列挙が不要になる可能性がある。ただし `fg` の値が
テーマ由来のため Mocha と合うかは未検証。

### 3. 色のハードコード

アクセント色を変える際に5箇所の編集が必要。`:root` にカスタムプロパティとして
切り出せば1箇所で済む。

過去に `:root` を追加した際に白背景が再発したが、あれは同時に
`html { background-color }` を入れたことが原因だった可能性が高く、
`:root` 自体は無害と考えられる。試す場合は `:root` の追加のみを単独で行い、
背景指定は `body` のままにすること。
