# Thunderbird 設定

メール本文の表示（ダークモード・配色・文字の太さ）をカスタマイズする。

## ファイル

| ファイル | 配置先 | 役割 |
|---|---|---|
| `user.js` | プロファイル直下 | 起動時に読まれる pref。ダークモードの有効化 |
| `chrome/userContent.css` | プロファイル `chrome/` | メール本文のスタイル |

## 配置方法（暫定: シンボリックリンク）

配色の調整中はシンボリックリンクで繋ぐ。編集が即反映され、
Thunderbird の再起動だけで確認できる（`chezmoi apply` が不要）。

プロファイルディレクトリ名はランダムIDのため、`installs.ini` の `Default` から解決する。
Windows の管理者 PowerShell で以下を実行する（`scripts/link-thunderbird.ps1`）:

```powershell
cd D:\git\dotfiles
powershell -ExecutionPolicy Bypass -File .\scripts\link-thunderbird.ps1
```

**リンク元は `D:\git\dotfiles`（Windows側clone）である必要がある。**
`\\wsl$\...` 配下を指すとThunderbirdから読めない。
WSL側で編集したら `cd /mnt/d/git/dotfiles && git pull` で同期する。

調整が固まったら chezmoi の `run_onchange_` スクリプトでのコピー配布に移行する。

## 反映

Thunderbird を**完全終了してから再起動**する（`user.js` と CSS は起動時にのみ読まれる）。

## pref の意味

- `toolkit.legacyUserProfileCustomizations.stylesheets`
  TB115+ では userChrome.css / userContent.css がデフォルト無効。有効化に必須。

- `mail.dark-reader.enabled`
  本文をダークモード化する。`DarkReader.mjs` が輝度200以下の `color` 指定を
  **削除**する（変換ではない）。対象はインライン `style` 属性とメール内 `<style>`
  タグのCSSルール。ライト前提のHTMLメールの黒文字がこれで消える。
  `userContent.css` はユーザーオリジンなので削除対象外。

- `layout.css.prefers-color-scheme.content-override = 1`
  **これが本質的な設定。** TB内蔵 `messageBody.css` のダークモードブロックは

      @media (prefers-color-scheme: dark) and -moz-pref("mail.dark-reader.enabled")

  の2条件AND。未設定（システム追従）だとメッセージペインではライトに解決され、
  本文だけ白背景・黒文字・暗い引用色になる。`1` で dark を強制して成立させる。

## 調査で判明した事実（再調査不要）

- 引用色の pref は `mail.citation_color`（`mailnews.` ではない）。
  ただしこの値はインライン style で焼き込まれるため dark-reader に削除される。
- 内蔵 `messageQuotes.css` が
  `body blockquote[type="cite"] { color: var(--color-text-highlight) !important }`
  を当てる。引用色を変えるには詳細度で上回る必要がある（`html` を足す等）。
- `html body *` は `body` 自身に当たらない。背景を潰すなら `html, body` を単独列挙する。
- フォント `HackGen Console NF` は Regular(400)/Bold(700) の2ウェイトのみ。
  `font-weight` の中間値は丸められるため、無段階に太らせるには
  `-webkit-text-stroke` を使う。
- 検証は必ず受信トレイの3ペイン表示で行う。`.eml` を直接開いた専用ウィンドウは
  表示条件が異なり、本文の白背景問題が再現しない。
