#!/usr/bin/env bash
# update-all スキル用: 更新対象ごとに「今の版」と「最新版」を集めて表にする。
# 判断はしない（更新するかどうかはスキル側でユーザーに聞く）。インストール済みの物は何も変えない。
# ただし git fetch・Lazy の check・Claude プラグインのカタログ更新は行う。
#
#   bash scripts/update-all/status.sh            全対象
#   bash scripts/update-all/status.sh nix nvim   指定した対象だけ
#
# 対象: nix nvim zeno sidebar python tools plugins archify
# 出力: TSV（対象 / 項目 / 今 / 最新 / 状態）
#   状態: 最新 / 更新あり / 更新あり(メジャー) / 固定 / 要確認 / 取得失敗

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
SRC="$HOME/src/github.com"
ZENO="$SRC/yuki-yano/zeno.zsh"
SIDEBAR="$SRC/hiroppy/tmux-agent-sidebar"
ARCHIFY_UPSTREAM="$SRC/tt-a1i/archify"
PLUGINS_DIR="$HOME/.claude/plugins"

# 1行出力する: row <対象> <項目> <今> <最新> <状態>
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }

# 2つの版が同じなら「最新」、違えば「更新あり」を返す
cmp_state() { if [[ "$1" == "$2" ]]; then echo 最新; else echo 更新あり; fi; }

# epoch 秒を YYYY-MM-DD にする
ymd() { date -d "@$1" +%F 2>/dev/null || echo "?"; }

# flake.lock の各 input の更新日を、上流の最新と比べる
check_nix() {
  local lock="$DOTFILES/flake.lock" name ref cur latest
  for name in $(jq -r '.nodes.root.inputs | keys[]' "$lock"); do
    cur=$(jq -r --arg n "$name" '.nodes[$n].locked.lastModified' "$lock")
    # rev を直書きした input は意図的な固定なので最新を見ない
    if jq -e --arg n "$name" '.nodes[$n].original.rev' "$lock" >/dev/null; then
      row nix "$name" "$(ymd "$cur")" - 固定
      continue
    fi
    ref=$(jq -r --arg n "$name" '.nodes[$n].original
      | if .type == "github" then "github:\(.owner)/\(.repo)" + (if .ref then "/\(.ref)" else "" end)
        else "\(.type)+\(.url)" end' "$lock")
    latest=$(timeout 120 nix flake metadata --json "$ref" 2>/dev/null | jq -r '.lastModified // empty' || true)
    if [[ -z "$latest" ]]; then row nix "$name" "$(ymd "$cur")" '?' 取得失敗; continue; fi
    if (( latest > cur )); then row nix "$name" "$(ymd "$cur")" "$(ymd "$latest")" 更新あり
    else row nix "$name" "$(ymd "$cur")" "$(ymd "$latest")" 最新; fi
  done
}

# lazy.nvim のプラグインと Mason のパッケージに更新があるか見る（lazy-lock.json は変えない）
check_nvim() {
  local out n names
  out=$(timeout 300 nvim --headless "+lua require('lazy').check({wait=true, show=false})" \
    "+lua local t={} for _,p in pairs(require('lazy.core.config').plugins) do if p._ and p._.updates then t[#t+1]=p.name end end io.write('UPDATES:'..#t..':'..table.concat(t,' ')..'\n')" \
    +qa 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -o 'UPDATES:.*' || true)
  if [[ -z "$out" ]]; then
    row nvim plugins '?' '?' 取得失敗
  else
    n=$(cut -d: -f2 <<<"$out"); names=$(cut -d: -f3- <<<"$out")
    if (( n > 0 )); then row nvim plugins - "${n}件: $names" 更新あり; else row nvim plugins - - 最新; fi
  fi

  local lua got=0 _tag name cur latest
  lua=$(mktemp --suffix=.lua)
  cat >"$lua" <<'EOF'
require('lazy').load({ plugins = { 'mason.nvim' } })
local mr = require('mason-registry')
mr.refresh(function()
  for _, p in ipairs(mr.get_installed_packages()) do
    io.write('MASON\t' .. p.name .. '\t' .. tostring(p:get_installed_version()) .. '\t' .. tostring(p:get_latest_version()) .. '\n')
  end
  vim.schedule(function() vim.cmd('qa!') end)
end)
vim.defer_fn(function() vim.cmd('qa!') end, 60000)
EOF
  while IFS=$'\t' read -r _tag name cur latest; do
    got=1
    row nvim "mason:$name" "$cur" "$latest" "$(cmp_state "$cur" "$latest")"
  done < <(timeout 90 nvim --headless -c "luafile $lua" 2>&1 | tr '\r' '\n' | grep '^MASON' || true)
  rm -f "$lua"
  (( got )) || row nvim mason '?' '?' 取得失敗
}

# zeno.zsh の clone が上流から何コミット遅れているか見る
check_zeno() {
  local behind
  if ! git -C "$ZENO" fetch -q 2>/dev/null; then row zeno zeno.zsh '?' '?' 取得失敗; return; fi
  behind=$(git -C "$ZENO" rev-list --count 'HEAD..@{u}')
  row zeno zeno.zsh "$(git -C "$ZENO" rev-parse --short HEAD)" \
    "$(git -C "$ZENO" rev-parse --short '@{u}') (+$behind)" "$(if (( behind > 0 )); then echo 更新あり; else echo 最新; fi)"
}

# tmux-agent-sidebar の上流の新しいコミットと、ローカルパッチ元の PR の状態を見る
check_sidebar() {
  local branch new cur latest pr state
  if ! git -C "$SIDEBAR" fetch -q origin 2>/dev/null; then row sidebar tmux-agent-sidebar '?' '?' 取得失敗; return; fi
  branch=$(git -C "$SIDEBAR" rev-parse --abbrev-ref HEAD)
  new=$(git -C "$SIDEBAR" rev-list --count HEAD..origin/main)
  cur=$("$SIDEBAR/bin/tmux-agent-sidebar" version 2>/dev/null || echo ?)
  latest=$(git -C "$SIDEBAR" show origin/main:Cargo.toml | sed -n 's/^version *= *"\(.*\)"/\1/p' | head -1)
  row sidebar "tmux-agent-sidebar ($branch)" "$cur" "$latest (上流+$new)" \
    "$(if (( new > 0 )); then echo 更新あり; else echo 最新; fi)"
  # local-patches に当てている上流 PR。マージ済みならパッチを捨てて main に戻せる
  for pr in 159 167; do
    state=$(timeout 30 gh pr view "$pr" -R hiroppy/tmux-agent-sidebar --json state -q .state 2>/dev/null || echo ?)
    row sidebar "local-patch PR #$pr" - "$state" "$(if [[ $state == MERGED ]]; then echo 要確認; else echo -; fi)"
  done
}

# scripts/ 配下の uv プロジェクトの直接依存に新しい版があるか見る。
# pyproject で上限（<）を付けた依存は、上限を超える版が出ても「固定」とする
check_python() {
  local proj dir name line pkg cur latest spec found
  while IFS= read -r proj; do
    dir=$(dirname "$proj"); name=$(basename "$dir"); found=0
    while IFS= read -r line; do
      found=1
      pkg=$(sed -E 's/^[^a-zA-Z]*//; s/[[ ].*//' <<<"$line")
      cur=$(grep -oE ' v[0-9][^ ]*' <<<"$line" | head -1 | tr -d ' ')
      latest=$(grep -oE 'latest: v[^)]*' <<<"$line" | cut -d' ' -f2)
      spec=$(grep -oE "\"$pkg(\[[^]]*\])?[^\"]*\"" "$proj" | head -1 || true)
      if [[ "$spec" == *"<"* ]]; then row python "$name: $pkg" "$cur" "$latest (指定 $spec)" 固定
      else row python "$name: $pkg" "$cur" "$latest" 更新あり; fi
    done < <(cd "$dir" && timeout 120 uv tree --outdated --depth 1 2>/dev/null | grep 'latest:' || true)
    (( found )) || row python "$name" - - 最新
  done < <(find "$DOTFILES/scripts" -maxdepth 2 -name pyproject.toml -not -path '*/.venv/*')
}

# Nix 以外で単体で入れたコマンド（uv・uv tool・coderabbit・dotenvx）
check_tools() {
  local cur latest msg tool outdated
  msg=$(uv self update --dry-run 2>&1 | tail -1 || true)
  cur=$(uv --version | cut -d' ' -f2)
  if grep -q 'already on' <<<"$msg"; then row tools uv "$cur" "$cur" 最新
  else row tools uv "$cur" "$(grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' <<<"$msg" | tail -1 || echo ?)" 更新あり; fi

  outdated=$(uv tool list --outdated 2>/dev/null | grep -v '^-' || true)
  if [[ -z "$outdated" ]]; then row tools "uv tool" - - 最新
  else
    # 1行は「名前 v今 [latest: v最新]」。項目にはツール名だけを入れる（uv tool upgrade <名前> に使う）
    while IFS= read -r tool; do
      row tools "uv tool: $(awk '{print $1}' <<<"$tool")" "$(awk '{print $2}' <<<"$tool")" \
        "$(grep -oE 'latest: v?[^] ]+' <<<"$tool" | cut -d' ' -f2 || echo '?')" 更新あり
    done <<<"$outdated"
  fi

  # coderabbit には確認だけのオプションが無い
  row tools coderabbit "$(coderabbit --version 2>/dev/null || echo ?)" "coderabbit update で判定" 要確認

  cur=$(dotenvx --version 2>/dev/null || echo ?)
  latest=$(timeout 30 gh release view -R dotenvx/dotenvx --json tagName -q .tagName 2>/dev/null | sed 's/^v//' || true)
  if [[ -z "$latest" ]]; then row tools dotenvx "$cur" '?' 取得失敗
  elif [[ "${cur%%.*}" != "${latest%%.*}" ]]; then row tools dotenvx "$cur" "$latest" "更新あり(メジャー)"
  else row tools dotenvx "$cur" "$latest" "$(cmp_state "$cur" "$latest")"; fi
}

# インストール済みプラグインの版と、カタログ上の版（カタログに無ければプラグインの plugin.json）を比べる
check_plugins() {
  local id name mk cur mkdir latest src
  timeout 300 claude plugin marketplace update >/dev/null 2>&1 || row plugins カタログ更新 - - 取得失敗
  while IFS=$'\t' read -r id cur; do
    name=${id%@*}; mk=${id#*@}; mkdir="$PLUGINS_DIR/marketplaces/$mk"
    latest=$(jq -r --arg n "$name" '.plugins[] | select(.name==$n) | .version // empty' \
      "$mkdir/.claude-plugin/marketplace.json" 2>/dev/null || true)
    if [[ -z "$latest" ]]; then
      src=$(jq -r --arg n "$name" '.plugins[] | select(.name==$n) | .source | strings' \
        "$mkdir/.claude-plugin/marketplace.json" 2>/dev/null || true)
      if [[ -n "$src" ]]; then
        latest=$(jq -r '.version // empty' "$mkdir/$src/.claude-plugin/plugin.json" 2>/dev/null || true)
      fi
    fi
    if [[ -z "$latest" ]]; then row plugins "$id" "$cur" '?' 要確認
    else row plugins "$id" "$cur" "$latest" "$(cmp_state "$cur" "$latest")"; fi
  done < <(jq -r '.plugins | to_entries[] | "\(.key)\t\(.value[0].version)"' "$PLUGINS_DIR/installed_plugins.json" | sort)
}

# archify は上流リポジトリの archify/ をスキルとしてコピーして入れている
check_archify() {
  local cur latest
  cur=$(jq -r .version "$DOTFILES/.claude-global/skills/archify/package.json")
  if ! timeout 300 git -C "$ARCHIFY_UPSTREAM" fetch -q 2>/dev/null; then row archify archify "$cur" '?' 取得失敗; return; fi
  latest=$(git -C "$ARCHIFY_UPSTREAM" show '@{u}:archify/package.json' 2>/dev/null | jq -r .version || echo ?)
  if [[ "${cur%%.*}" != "${latest%%.*}" ]]; then row archify "archify (skill)" "$cur" "$latest" "更新あり(メジャー)"
  else row archify "archify (skill)" "$cur" "$latest" "$(cmp_state "$cur" "$latest")"; fi
}

ALL=(nix nvim zeno sidebar python tools plugins archify)
targets=("$@")
(( ${#targets[@]} )) || targets=("${ALL[@]}")
for t in "${targets[@]}"; do
  case "$t" in
    nix|nvim|zeno|sidebar|python|tools|plugins|archify) ;;
    *) echo "unknown target: $t (使えるのは: ${ALL[*]})" >&2; exit 2 ;;
  esac
done
printf '対象\t項目\t今\t最新\t状態\n'
for t in "${targets[@]}"; do "check_$t"; done
