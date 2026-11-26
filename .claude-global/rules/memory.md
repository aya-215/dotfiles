# メモリの置き場所

メモリの実体は `agent-memory` スキル（`~/.claude/skills/agent-memory/memories/`、グローバル共有）に一元管理する。
ハーネスが自動注入するネイティブの「Memory」機構（プロジェクト配下の `MEMORY.md` 等）にはメモリ本体を書かず、ネイティブ側の frontmatter 形式（name/description/metadata）でも書かない。

- 保存・検索・更新は必ず `agent-memory` スキルを起動して行う。ネイティブ `MEMORY.md` の書き方（入口としての使い方）もスキルに従う
- 関連作業を始めるときは `rg "^summary:" ~/.claude/skills/agent-memory/memories/ --no-ignore --hidden` で既存メモリを確認する
- 調査に時間がかかった発見・非自明なバグや回避策・アーキテクチャ決定・中断しうる作業は、指示がなくても保存を検討する
