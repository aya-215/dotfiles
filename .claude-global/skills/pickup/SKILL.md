---
name: pickup
description: /handoff で残した引き継ぎメモを PR 番号・課題No・言葉で探して読み込み、新しいセッションで作業を再開する。「/pickup 1210」「/pickup 7400」「引き継ぎから再開」「続きから」「マージされたから残作業調べて（引き継ぎあり）」等で使う。引数なしなら待ち中の引き継ぎを一覧する。書く側は handoff スキル。
---

# pickup

## Overview

探すのは `scripts/find_handoff.py` が決定的にやる（番号の表記揺れ吸収・段階的に広げる）。
Claude の仕事は「候補が複数なら選んでもらう」「読み込んで要点を示す」「ユーザーの指示どおり続ける」の3つ。

## 手順

1. 探す（引数はユーザーが渡したものをそのまま。URL なら番号も言葉もそのまま渡してよい）:
   ```bash
   python3 -I ~/.claude/skills/pickup/scripts/find_handoff.py <引数...>
   ```
   出力は JSON: `stage`（`handoff-open` → `handoff-all` → `work-in-progress` → `all` → `none` の順に広げ、最初に当たった段）と `hits`（`path` / `summary` / `created` / `status`）。
2. 結果で分ける:
   - `none`: 引き継ぎは無い。`find-session` スキルで過去のセッションを探すことを提案する
   - 1 件: そのファイルを読む
   - 複数: 題名（`summary`）・日付・状態を並べ、どれを読むかユーザーに選んでもらう
   - `stage` が `handoff-open` 以外: 待ち中の引き継ぎではなく、終わった引き継ぎや他のメモに当たったことを一言添える
3. 読んだら、待っていたもの・今の状態・次にやることを短く示す。
   - 「元のセッション」の作業場所が今の作業ディレクトリと違えば伝える
   - 文脈が足りないときは、記載の `claude --resume <ID>` で元の会話に戻れることを示す
4. ユーザーの指示（「マージされたから残作業調べて」等）に従って続ける。
5. その件が片付いたら、引き継ぎメモの frontmatter を `status: resolved` に書き換える（ファイルは消さない）。
