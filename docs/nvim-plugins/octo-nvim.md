# octo.nvim

Neovim内でGitHubのPR / Issue / Discussionを操作するプラグイン。

設定ファイル: `config/nvim/lua/plugins/octo.lua`
前提条件: `gh auth login` 済みであること

---

## クイックリファレンス

| キー | 説明 |
|---|---|
| `<Space>gop` | PR一覧 |
| `<Space>goi` | Issue一覧 |
| `<Space>goc` | PR作成 |
| `<Space>gor` | レビュー開始 |
| `<Space>gos` | レビュー送信 |
| `<Space>gov` | レビュー再開 |
| `<Space>gok` | PRチェックアウト |
| `<Space>gox` | CIチェック確認 |
| `<Space>goe` | PR再読込 |
| `:Octo pr list` | PR一覧表示 |
| `:Octo issue list` | Issue一覧表示 |
| `:Octo review start` | レビュー開始 |
| `:Octo review submit` | レビュー送信 |

---

## 詳細

### PR操作

- `:Octo pr list` — PR一覧表示
- `:Octo pr list owner/repo` — 別リポジトリのPR一覧
- `:Octo pr search assignee:me is:pr` — PR検索
- `:Octo pr create` — PR作成
- `:Octo pr checkout` — PRブランチをチェックアウト
- `:Octo pr commits` — PRのコミット一覧
- `:Octo pr changes` — PRの変更ファイル一覧
- `:Octo pr diff` — PRのdiff表示
- `:Octo pr merge` — マージ（デフォルト: squash）
- `:Octo pr ready` — Ready for reviewにマーク
- `:Octo pr close` — PRを閉じる
- `:Octo pr reopen` — PRを再オープン
- `:Octo pr checks` — CIチェック状態の確認
- `:Octo pr reload` — PRデータ再読込
- `:Octo pr url` — PRのURLをコピー

### Issue操作

- `:Octo issue list` — Issue一覧
- `:Octo issue list labels=bug` — ラベルでフィルタ
- `:Octo issue list assignee=@me` — 自分にアサインされたIssue
- `:Octo issue create` — Issue作成
- `:Octo issue create owner/repo` — 別リポジトリにIssue作成
- `:Octo issue search assignee:me is:issue` — Issue検索
- `:Octo issue close` — Issueを閉じる
- `:Octo issue reopen` — Issueを再オープン

### レビュー操作

- `:Octo review start` — 新規レビュー開始
- `:Octo review resume` — 保留中のレビュー再開
- `:Octo review submit` — レビュー送信
- `:Octo review discard` — レビュー破棄
- `:Octo review comments` — 保留中のコメント一覧
- `:Octo review resolve-thread` — スレッド解決

### コメント操作

- `:Octo comment add` — コメント追加
- `:Octo comment delete` — コメント削除
- `\c` — コメント追加（`\ca` の短縮）
- `\d` — コメント削除（`\cd` の短縮）
- `\w` — スレッドに返信（`\cr` の短縮）
- `\t` — スレッド解決（`\rt` の短縮）
- `\g` — 👍 リアクション（`\r+` の短縮）
- `\sa` — コード修正提案（suggestion）追加

### レビュー送信

- `<C-a>` — Approve（承認）して送信
- `<C-r>` — Request Changes（変更要求）して送信
- `<C-p>` — Comment（コメントのみ）で送信
- `<C-c>` — レビュータブを閉じる

### ラベル・アサイン

- `:Octo label add` — ラベル追加
- `:Octo label remove` — ラベル削除
- `:Octo label create` — ラベル新規作成
- `:Octo assignee add` — アサイン追加
- `:Octo assignee remove` — アサイン削除
- `:Octo reviewer add` — レビュアー追加
- `:Octo reviewer remove` — レビュアー削除
- `\la` — ラベル追加（レビューモード）
- `\ld` — ラベル削除
- `\aa` — アサイン追加
- `\ad` — アサイン削除
- `\va` — レビュアー追加
- `\vd` — レビュアー削除

### ナビゲーション

- `]c` — 次のコメントへ
- `[c` — 前のコメントへ
- `\po` — PRブランチをチェックアウト
- `\pm` — マージ
- `\pd` — diff表示
- `\pc` — コミット一覧
- `\pf` — 変更ファイル一覧
- `\vs` — レビュー開始
- `\vr` — レビュー再開

### Issue/PRバッファ共通

- `<CR>` — オプションメニュー表示
- `<C-b>` — ブラウザで開く
- `<C-y>` — URLをクリップボードにコピー
- `<C-r>` — 内容を再読込

### リアクション

- `:Octo reaction thumbs_up` / `\g` — 👍
- `:Octo reaction thumbs_down` / `\r-` — 👎
- `:Octo reaction laugh` / `\rl` — 😄
- `:Octo reaction hooray` / `\rp` — 🎉
- `:Octo reaction confused` / `\rc` — 😕
- `:Octo reaction heart` / `\rh` — ❤️
- `:Octo reaction rocket` / `\rr` — 🚀
- `:Octo reaction eyes` / `\re` — 👀

### その他

- `:Octo actions` — 利用可能なアクション表示
- `:Octo search <query>` — GraphQLで検索

---

## 使い方

### PRレビューの流れ

1. `:Octo pr list` でPRを選択
2. `:Octo review start` でレビューモード開始（diffが表示される）
3. カーソルを該当行に移動
4. `\c` でインラインコメント記入
5. `:w` でコメント保存（まだpending状態）
6. 必要なだけ 3〜5 を繰り返す
7. `<C-a>` でApproveして全コメント送信（または `<C-r>` でRequest Changes、`<C-p>` でCommentのみ）

### コード修正提案（Suggestion）の書き方

レビューコメント内で以下の形式を使うと、レビュイーがワンクリックで適用可能：

````markdown
```suggestion
const optimized = cache.get(key) ?? fetchFromDB()
```
````

### PRフィルタ例

- `:Octo pr list labels=bug,enhancement`
- `:Octo pr list states=OPEN`
- `:Octo pr list assignee=@me`
- `:Octo pr list createdBy=username`

## 注意事項

- コメントはレビューをsubmitするまで公開されない（pending状態）
- 大量ファイル（50+）のPRではパフォーマンスが低下する場合がある
- ファイルレベルコメントは非対応（行単位のみ）
- `gh auth refresh -s read:project` でProjects v2対応可能
