# Claude Code mods

Claude Code の画面や挙動を変える自作 mod（function hooks plugin）の置き場。
各 mod の使い方・カスタマイズ箇所は、それぞれのフォルダの README を見ること。

| mod | 何をするか | README |
|---|---|---|
| `session-autoname` | 対話セッションに色と、会話内容から作った名前を自動で付ける | [session-autoname/README.md](session-autoname/README.md) |
| `session-memo` | （無効化中。`CLAUDE_CODE_PLUGIN_DIRS` から外してある）会話ごとの作業メモを、プロンプト上の帯と `/note` のパネルで扱う | [session-memo/README.md](session-memo/README.md) |
| `prompt-cache-control` | （外部製）プロンプトキャッシュの hit 率と期限切れまでの残り時間を、プロンプト上の帯と `/cache` のパネルに出す。取得元は [davila7/claude-code-templates](https://github.com/davila7/claude-code-templates) の `cli-tool/components/mods/observability/prompt-cache-control`（commit `a6e6f93`、MIT）。`tsconfig.json` と `.gitignore` を足し、帯の `read`/`wrote`/`new` が縦に積まれて3行になるのを `hooks/prompt-cache-control.tsx` の Fragment を横並びの `Box` に替えて直した。更新は取得元から丸ごと差し替え、この修正が取り込まれていなければ当て直す | [prompt-cache-control/README.md](prompt-cache-control/README.md) |
| `cache-keeper` | （外部製）待っているセッションのプロンプトキャッシュを、期限が切れる前のフォーク ping（本体の会話に残らない）で温め続ける。`/keepwarm [status \| on \| off \| auto \| now \| for 3h \| until 18:00]`。記録は `~/.claude/cache-keeper/<セッションID>.jsonl`。取得元は [chrisvaillancourt/claude-cache-keeper](https://github.com/chrisvaillancourt/claude-cache-keeper)（commit `46570fd`、v0.5.0、MIT）。手を入れた箇所: `hooks/policy.ts` の止め方を「最後の作業から8時間」から時刻ルール（月〜木は翌日12時まで、金は17時まで、金17時以降と土日は温めない）と ping 20回の上限（`maxPings`）に変更、そのプロセスでメイン会話のリクエストが2回未満なら ping しない（2.1.322 では1回目の直後のフォークがキャッシュに当たらず、外れると全セッションの自動 ping が止まるため。`requests` / `turnRequests` で数える）、`hooks/register.ts` の設定の読み取りと手動 `/keepwarm now` を回数に数えない変更、テストの追従、`tsconfig.json`/`.gitignore`。設計は `docs/superpowers/specs/2026-11-10-cache-keepwarm-and-handoff-design.md` | [cache-keeper/README.md](cache-keeper/README.md) |

`prompt-rail`（プロンプトの一覧をレールで出す外部製 mod）はここに置かず、`claude plugin install prompt-rail@oikon48` でマーケットプレイスから入れている。

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

- `classic.*`（settings hook と同じイベント）の hook は、本体同梱の `cc-plugin-sec-default` が user 層の分を飛ばすので届かない（2.1.318 で確認。起動時に「its classic.SessionStart hook was skipped」と出る）。engine 側のイベント（`session.start` 等）と `$.session.*` で代わりを探す
- `$.command.run` は「ターンが待っている hook」の中では拒否される。`session.start` や `turn.complete` から実行するときは `$.clock.after(0, ...)` で hook の外に出す
- テストで `$` 呼び出しを受ける hook（`model.complete`・`ui.status`・`ui.open` など）は `{ value: ... }` で包んで返す
- テストの `$.command.run` には `origin` と `presentation` も渡す
- ボタンの `hotkey` は同じパネルの中で同じ文字を2つ置けない（後の方が勝つ）
- ボタンは描いた時点の位置を覚えている。押すまでに行がずれることがあるので、押したときに中身を照合する
- パネル（Pane）の地の色は本体が塗っている。半透明の WezTerm では黒い板に見えるが、mod からは消せない
