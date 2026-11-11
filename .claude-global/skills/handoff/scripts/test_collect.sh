#!/usr/bin/env bash
# Tests for collect.sh: it must exit 0 and print every key even where git or a PR is missing.
set -euo pipefail

collect="$(cd "$(dirname "$0")" && pwd)/collect.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# Report one failed expectation and count it.
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Assert that the output holds a line exactly equal to the expected one.
expect_line() {
  local out=$1 line=$2 label=$3
  grep -qxF -- "$line" <<<"$out" || fail "$label: missing line '$line'"
}

# Assert that the output holds a key=value line with a non-empty value.
expect_value() {
  local out=$1 key=$2 label=$3
  grep -qE "^${key}=.+" <<<"$out" || fail "$label: '$key' should have a value"
}

mkdir "$work/plain"
if out=$(cd "$work/plain" && bash "$collect"); then
  expect_line "$out" "cwd=$work/plain" "outside git"
  expect_line "$out" "remote=" "outside git"
  expect_line "$out" "branch=" "outside git"
  expect_line "$out" "pr_url=" "outside git"
  expect_line "$out" "pr_number=" "outside git"
  expect_value "$out" created "outside git"
else
  fail "outside git: exit status was not 0"
fi

mkdir "$work/repo"
git -C "$work/repo" init -q -b feat/x
git -C "$work/repo" remote add origin https://gitbucket.example/x.git
if out=$(cd "$work/repo" && bash "$collect"); then
  expect_line "$out" "remote=https://gitbucket.example/x.git" "gitbucket repo"
  expect_line "$out" "branch=feat/x" "gitbucket repo"
  expect_line "$out" "pr_url=" "gitbucket repo"
else
  fail "gitbucket repo: exit status was not 0"
fi

mkdir -p "$work/repo-gh" "$work/bin"
git -C "$work/repo-gh" init -q -b feat/y
git -C "$work/repo-gh" remote add origin git@github-aya215:aya-215/dotfiles.git
printf '#!/usr/bin/env bash\necho %s\n' "'{\"url\":\"https://github.com/aya-215/dotfiles/pull/7\",\"number\":7}'" > "$work/bin/gh"
chmod +x "$work/bin/gh"
if out=$(cd "$work/repo-gh" && PATH="$work/bin:$PATH" bash "$collect"); then
  expect_line "$out" "pr_url=https://github.com/aya-215/dotfiles/pull/7" "github ssh alias"
  expect_line "$out" "pr_number=7" "github ssh alias"
else
  fail "github ssh alias: exit status was not 0"
fi

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures failure(s)"
  exit 1
fi
