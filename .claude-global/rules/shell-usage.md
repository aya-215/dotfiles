# Bash でのファイル探索

`grep` / `find` には探索先の絶対パスを直接渡すこと。
`cd /path && grep -rn ... .` のように `cd` と相対パスを組み合わせない。

auto mode は `cd` 後の探索先を実行前に解決できず、`Read(.env)` 等の deny ルールに
触れるか判定できないため、安全側に倒れて毎回承認プロンプトが出る。

```bash
# NG
cd /path/to/app && grep -rn "foo" . --include='*.ts'

# OK
grep -rn "foo" /path/to/app --include='*.ts'
```
