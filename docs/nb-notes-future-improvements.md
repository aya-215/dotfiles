# nb メモ機能 将来の改善案

運用が軌道に乗ってから検討する機能。

## 提案2: ノート間リンクの活用

nbの`[[wiki link]]`を活用してノート間を繋ぐ。

### メモでの使い方

```markdown
# Docker Composeの使い方

#tech #docker

---

基本的な使い方は [[Docker基礎]] を参照。

関連: [[Kubernetes入門]]
```

### コマンド追加案

```bash
# ノートへのリンクをクリップボードにコピー
nblink <id>

# バックリンク確認（どこから参照されているか）
nb backlinks <id>
```

## 提案4: Progressive Summarization対応

メモに「要約セクション」を追加して、後から磨く。

### メモ形式

```markdown
# 長いミーティングメモ

#meeting #work/portal

## TL;DR

← 後から追記する1-2行の要約

---

詳細な内容...
```

### 運用フロー

1. 最初は詳細を書くだけ
2. 後で読み返したときに TL;DR を追記
3. 検索時に要約だけで内容を把握できる

## 提案5: 検索強化

### 最近のメモ表示（inbox整理用）

```bash
# 直近N件のメモを表示
nbnr [N]
```

### 孤立ノート検出

```bash
# リンクされていないノートを検出（整理の手がかりに）
nbnorphan
```

### 実装イメージ

```bash
# nbnr - 最近のメモ一覧
nbnr() {
  local limit="${1:-10}"
  nb ${_NB_NOTES}list --limit "$limit" --sort updated
}

# nbnorphan - 孤立ノート（リンクされていない）
nbnorphan() {
  # TODO: バックリンクがないノートを検出
  echo "未実装"
}
```

## 参考リンク

- [nb公式ドキュメント](https://xwmx.github.io/nb/)
- [Zettelkasten Method](https://zettelkasten.de/overview/)
- [PKM Best Practices](https://anthonytd.com/blog/pkm-best-practices/)
