# nb コマンドリファレンス

実装ファイル: `~/.config/nb/functions.zsh`

## タスク管理

| コマンド | 説明 | 使用例 |
|----------|------|--------|
| `nbt` | タスク追加（対話形式） | `nbt` |
| `nbt "名前" [-d DATE] [-t TAGS] [-p PRIORITY] [-D DESC]` | クイック追加 | `nbt "レビュー" -d 3d -t work -p 1` |
| `nbtl [フィルタ]` | 未完了タスク一覧（grepフィルタ可） | `nbtl work` |
| `nbtd [ID]` | タスク完了（ID省略でfzf選択） | `nbtd 12` |
| `nbtu <ID>` | 完了取消（ID必須） | `nbtu 12` |
| `nbte` | タスク編集（fzf選択） | `nbte` |
| `nbts [検索語]` | タスク検索（省略でfzf） | `nbts "API"` |
| `nbtag` | タグで絞り込み（fzf選択） | `nbtag` |
| `nbtclosed` | 完了タスク一覧 | `nbtclosed` |

## 日報管理

| コマンド | 説明 |
|----------|------|
| `nbd` | 今日の日報作成/編集（前日サマリー・未完了タスク自動挿入） |
| `nbds` | 今日の日報表示 |
| `nbde` | 今日の日報編集 |
| `nbdy` | 昨日の日報表示 |
| `nbdl` | 日報一覧（fzf選択→表示） |

## 週報管理

| コマンド | 説明 | 使用例 |
|----------|------|--------|
| `nbw` | 今週の週報を編集（存在しない場合はエラー） | `nbw` |
| `nbws [日付]` | 週報表示（省略で今週） | `nbws 2025-12-15` |
| `nbwe [日付]` | 週報編集（省略で今週） | `nbwe` |
| `nbwl` | 週報一覧（fzf選択→表示） | `nbwl` |

## メモ管理

| コマンド | 説明 | 使用例 |
|----------|------|--------|
| `nbn` | メモ追加（対話形式） | `nbn` |
| `nbn "タイトル"` | クイック追加（タグなしで#inbox自動付与） | `nbn "会議メモ"` |
| `nbn "タイトル" -t TAGS` | タグ付きで追加 | `nbn "vim tips" -t tech,vim` |
| `nbnl` | メモ一覧（fzf選択→編集） | `nbnl` |
| `nbns [検索語]` | メモ検索（省略でfzf） | `nbns "vim"` |
| `nbntag` | タグで絞り込み（fzf選択） | `nbntag` |
| `nbninbox` | #inbox メモ一覧（整理用） | `nbninbox` |

## zeno補完

| パターン | 動作 |
|----------|------|
| `nbtd <Tab>` | タスクID補完 |
| `nbtu <Tab>` | タスクID補完 |
| `nb <Tab>` | ノートブック選択 |

## zenoスニペット

| キーワード | 展開 |
|------------|------|
| `nbta` | `nbt "{{task}}" -d {{due}} -t {{tags}}` |

## 内部関数

| 関数 | 用途 |
|------|------|
| `_nb_parse_date` | 相対日付パース（today, tomorrow, 3d, 1w など） |
| `_nb_parse_priority` | 優先度パース（1→priority/high など） |
| `_nb_get_tags` | notebook内のタグ一覧取得 |
| `_nb_select_tags` | fzfでタグを複数選択 |
| `_nb_priority_to_num` | 優先度を数値に変換（ソート用） |
| `_nb_format_single_task` | タスク1件を整形出力 |
| `_nb_format_tasks_for_daily` | 日報用タスク整形（work優先/日付順/優先度順） |
| `_nb_get_week_monday` | 指定日を含む週の月曜日を取得 |
