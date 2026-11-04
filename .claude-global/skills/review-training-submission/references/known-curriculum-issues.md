# 既知のカリキュラム・運用側の不備

レビューで見つけ、メンター側の修正待ちになっているもの。ここに載っているものは「カリキュラム・運用側の新しい修正候補」に出さない。
直ったら行を消す。直ったかは「確かめ方」の文字列がまだあるかで判断する。

カリキュラム本体は `curl -s http://192.168.208.80:8080/gitbucket/AI_dev/ai-team-docs/raw/main/docs/training/agent-onboarding/README.md` で取れる。

| 見つけたPR | 内容 | 確かめ方 |
|---|---|---|
| #117 | 権限モード表で bypass を「一切のチェックが効かない」と書いている。公式docsでは deny と ask は bypass 中も有効 | カリキュラム本体に `一切のチェックが効かない` がある |
| #117 | `framework-selection` skill は langchain-skills で `ecosystem-primer` に置き換わった | カリキュラム本体に `framework-selection` がある |
| #119 | `progress/agent/blank-page-tests.md` が旧構成（T1〜T9・T6a/T6b・フェーズ7〜9）のまま。カリキュラムの必須は T1・T3・T5・T6 | tamaki-ai-training の main の同ファイルに `T6a` がある |
| #119 | 評価をフェーズ4で扱う表と、「フェーズ5で扱う範囲（評価する）」が食い違う | カリキュラム本体に `フェーズ5で扱う範囲` がある |
| #121 | フェーズ2の ebase-agents の説明が実物と合わない（「二層」→実物は3層、targets に「どのスキルを載せるか」は無い、content の本文は `.md` ではなく YAML＋`prompts/`、「憲法」という語は無い）。Issue #102 とフェーズ README も同じ | カリキュラム本体に `の二層` がある |
