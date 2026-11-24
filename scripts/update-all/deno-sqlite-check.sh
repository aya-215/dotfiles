#!/usr/bin/env bash
# update-all スキル用: 指定した deno で zeno.zsh が使う @db/sqlite を読み込めるか確かめる。
# deno 2.9.7〜2.9.8 はここでセグフォする（flake.nix で nixpkgs-deno を 2.9.2 に固定している理由）。
#
#   bash scripts/update-all/deno-sqlite-check.sh <deno バイナリ>
#
# 終了コード: 0 = 読み込めた（固定を外せる候補）、それ以外 = 失敗（139 ならセグフォ）

set -euo pipefail

DENO="${1:?usage: deno-sqlite-check.sh <deno binary>}"
SQLITE_VERSION=$(grep -oE 'jsr:@db/sqlite@[0-9.]+' "$HOME/src/github.com/yuki-yano/zeno.zsh/src/deps.ts" | head -1)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat >"$work/check.ts" <<EOF
import { Database } from "${SQLITE_VERSION:-jsr:@db/sqlite@0.12.0}";
const db = new Database(":memory:");
console.log("sqlite-ok", db.prepare("select sqlite_version() v").get());
db.close();
EOF

echo "$("$DENO" --version | head -1) / ${SQLITE_VERSION:-jsr:@db/sqlite@0.12.0}"
rc=0
(cd "$work" && timeout 180 "$DENO" run -A check.ts >"$work/out.txt" 2>&1) || rc=$?
grep -v '^Download' "$work/out.txt" || true
echo "rc=$rc"
exit "$rc"
