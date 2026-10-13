# Claude Code mods

Claude Code の画面や挙動を変える自作 mod（function hooks plugin）の置き場。
各 mod の使い方・カスタマイズ箇所は、それぞれのフォルダの README を見ること。

| mod | 何をするか | README |
|---|---|---|
| `session-autoname` | 対話セッションに色と、会話内容から作った名前を自動で付ける | [session-autoname/README.md](session-autoname/README.md) |
| `session-memo` | 会話ごとの作業メモを、プロンプト上の帯と `/note` のパネルで扱う | [session-memo/README.md](session-memo/README.md) |

## 読み込みの仕組み

- `.claude-global/settings.json`（= `~/.claude/settings.json`）の `env.CLAUDE_CODE_PLUGIN_DIRS` に、mod フォルダの絶対パスを `:` 区切りで並べている
- 新しく起動した対話セッションから読み込まれる。`claude -p` にも読み込まれるので、mod 側で `isInteractive` を見て除外している
- 対話セッションは mod フォルダを監視している。ファイルを保存すると、開いているセッションにも自動で読み込み直される（`register` が再実行され、`$.state` は残る）
- `settings.json` にはユーザーの未コミット変更が混ざりやすい。コミットするときは自分の変更だけを index に載せる（丸ごと `git add` しない）

## mod を直す・足すとき

1. 変えたい mod の README の「カスタマイズ」表で場所を探す
2. テストを先に直してから実装を直す
3. 次の3つが通ることを確かめる

```bash
claude plugin test <mod フォルダ>
claude plugin validate <mod フォルダ>
nix shell nixpkgs#typescript -c tsc -p <mod フォルダ>
```

新しい mod を足すときは、既存の mod と同じ構成にする。

```
<mod>/
├── .claude-plugin/plugin.json   # name, version, description, "types": "./types/index.d.ts"
├── hooks/hooks.json             # { "modules": ["./register.ts(x)"] }
├── hooks/register.ts(x)         # hook の登録・描画（薄いつなぎ）
├── hooks/<logic>.ts             # 判断は純粋関数に寄せてテストする
├── tests/*.test.ts(x)
├── types/index.d.ts             # $.state の型（PluginState）
├── tsconfig.json
└── .gitignore                   # .claude-plugin/types/（本体が書き出す型）を除外
```

追加したら `CLAUDE_CODE_PLUGIN_DIRS` にパスを足し、この README の一覧にも載せる。

## API の資料

- 型宣言（API の正本）: mod を読み込んだセッションが `<mod>/.claude-plugin/types/claude-code/index.d.ts` に書き出す。約16,000行あるので、`'turn.complete'` や `Pane: {` のような名前で grep して読む
- 長い説明（reference.md）と plugin-authoring スキル本体は、本体バイナリに zstd 圧縮で同梱されている。取り出し方は agent-memory の `claude-code/mod-function-hooks-pitfalls.md` にある
- API は EARLY ACCESS で、本体の更新で変わることがある。壊れたら `claude --debug` で起動し、`<mod名>:` で始まる行を見る

## ハマりどころ（2つの mod で踏んだもの）

- `$.command.run` は「ターンが待っている hook」の中では拒否される。`session.start` や `turn.complete` から実行するときは `$.clock.after(0, ...)` で hook の外に出す
- テストで `$` 呼び出しを受ける hook（`model.complete`・`ui.status`・`ui.open` など）は `{ value: ... }` で包んで返す
- テストの `$.command.run` には `origin` と `presentation` も渡す
- ボタンの `hotkey` は同じパネルの中で同じ文字を2つ置けない（後の方が勝つ）
- ボタンは描いた時点の位置を覚えている。押すまでに行がずれることがあるので、押したときに中身を照合する
- パネル（Pane）の地の色は本体が塗っている。半透明の WezTerm では黒い板に見えるが、mod からは消せない
