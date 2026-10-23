---
name: kintai-check
description: 自分の勤怠で、今月の実働が「出社日数×8時間」に届いているか・30分以上の遅刻が年度で何回カウントされるかを確認する。「今月の勤怠足りてる？」「勤務時間足りてる？」「8時間×出社日数いけてる？」「遅刻の回数大丈夫？」「年度の遅刻カウント」「/kintai-check」等で使用。判定は scripts/kintai-check.py が決定的に行い、Claude は判断しない。
---

# kintai-check

## Overview

総務パック（ミラー）の 00296「勤務時間記録(勤怠えびす)」を eb-api-somu MCP 経由で読み、
**月の実働合計が「出社日数×8h」以上か**を判定する。判定と集計は `scripts/kintai-check.py` が全部持つ。
Claude はスクリプトを叩いて、出力をそのまま伝える。

## ルール（ユーザー確認済み）

- 月の基準: 実働合計（休憩控除後）≥ 出社日数 × 8:00。有休の日は出社日に数えない
- 遅刻: 出社が基本出社時間（9:30）より30分以上遅い日
- **基準を満たさなかった月の遅刻だけ**を年度（4月始まり）で数え、**10回以上でNG**
- 基準を満たした月の遅刻はカウントされない

## 手順

```bash
# 今月だけ（既定。ユーザーが年度を聞いていなければこれだけ）
python3 -I ~/.claude/skills/kintai-check/scripts/kintai-check.py

# 特定の月
python3 -I ~/.claude/skills/kintai-check/scripts/kintai-check.py 2026/09

# 年度の遅刻カウントも聞かれたとき
python3 -I ~/.claude/skills/kintai-check/scripts/kintai-check.py --fiscal-year
```

伝え方:

1. 結論（足りている／足りていない）と差
2. 今月なら「見込み」の行
3. 今月の30分以上遅刻の一覧。差がプラスのうちは年度カウントに入らないことを添える
4. `--fiscal-year` を付けたときだけ年度累計と「今月が未達で終わった場合」の回数

## 読み方の注意

| 出力 | 意味 |
|---|---|
| `実績` | 昨日までの打刻だけで集計した値。判定はこれ |
| `見込み` | 今日以降の日には、打刻前から勤怠えびすが所定時刻（9:30〜18:30＝8:00）を予定値として入れている。それどおりに働いた場合の着地 |
| 勤怠えびすの月次集計と合わない | 月次集計は予定値込み。スクリプトの `見込み` と一致するはず |

- 接続先はミラー。前日の打刻までは入っている想定だが、本番の勤怠えびす画面とは別物
- 月末に勤怠修正（翌月3日まで）が入ると数字が変わる

## スクリプトが止まったとき

| メッセージ | 対処 |
|---|---|
| `.mcp.json に eb-api-somu の定義が無い` | `~/.dotfiles/.mcp.json`（gitignore）に eb-api-somu を登録する。値は portal-chat の `.mcp.json` と同じ |
| `config.local.json に item_id が無い` | 00296 で氏名検索して item_id を `~/.claude/skills/kintai-check/config.local.json` に `{"item_id": "..."}` で書く（gitignore） |
| `MCP に接続できへん` | 社内ネットワーク/VPN を確認 |

dotfiles は PUBLIC なので、接続先 IP・item_id は上の gitignore 済みファイルにしか置かない。
