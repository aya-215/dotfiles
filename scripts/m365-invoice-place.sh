#!/usr/bin/env bash
# M365 Copilot ライセンス請求書を管理部の共有フォルダへ設置する
#
# 手動でDLしたPDFを検証し、規約どおりの名前にリネームして共有フォルダへコピーする。
# 既定はドライラン。実コピーは --commit を付けたときだけ行う。
#
#   ./m365-invoice-place.sh                    # Downloads の最新PDFをドライラン
#   ./m365-invoice-place.sh path/to.pdf        # ファイル指定でドライラン
#   ./m365-invoice-place.sh path/to.pdf --commit

set -euo pipefail

# --- 設定 ---

# フォルダ名は AUTO-000011215 だがファイル名は AUTO-000010660。このズレは実在する仕様。
# 経理未確認のため変数化してある（旧：AUTO-000010660_ フォルダの存在から番号が逆の可能性が残る）
AUTO_NO="${M365_INVOICE_AUTO_NO:-AUTO-000010660}"

SHARE_DIR='\\kanri-yayoi-svr\共有\法人名義カード使用履歴\インボイス(領収書)eBASE\AUTO-000011215_マイクロソフト_Microsoft365Copilotのライセンス'
NAME_SUFFIX='Microsoft365Copilotのライセンス'
DOWNLOADS_GLOB='/mnt/c/Users/*/Downloads'

PS='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

# --- ユーティリティ ---

red()   { printf "\033[1;31m%s\033[0m\n" "$1"; }
green() { printf "\033[1;32m%s\033[0m\n" "$1"; }
header() { printf "\n\033[1;36m=== %s ===\033[0m\n" "$1"; }

die() { red "NG: $1"; exit 1; }
ok()  { green "OK: $1"; }

# PowerShell を UTF-8 出力で呼ぶ。共有フォルダのパスに日本語が入るため必須
ps_run() {
  "$PS" -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; $1" 2>/dev/null | tr -d '\r'
}

# --- 引数 ---

COMMIT=false
SRC=""
for arg in "$@"; do
  case "$arg" in
    --commit) COMMIT=true ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) SRC="$arg" ;;
  esac
done

# --- 1. 入力PDFの決定 ---

header "入力ファイル"

if [[ -z "$SRC" ]]; then
  # Downloads 内で最終更新が一番新しいPDFを拾う
  SRC="$(find $DOWNLOADS_GLOB -maxdepth 1 -name '*.pdf' -printf '%T@ %p\n' 2>/dev/null \
         | sort -rn | head -1 | cut -d' ' -f2-)"
  [[ -n "$SRC" ]] || die "Downloads にPDFが見つからん。パスを引数で渡してや"
  echo "自動検出（Downloads の最新PDF）"
fi

[[ -f "$SRC" ]] || die "ファイルが無い: $SRC"
echo "  $SRC"
echo "  $(stat -c%s "$SRC") bytes"

# --- 2. Copilot の請求書か機械判定 ---

header "内容の検証"

command -v pdftotext >/dev/null || die "pdftotext が無い（nix-env -iA nixpkgs.poppler_utils）"

TXT="$(mktemp)"
trap 'rm -f "$TXT"' EXIT
pdftotext -layout "$SRC" "$TXT" || die "PDFとして読めへん"

# 「Copilot」の語だけやと他の請求書にも出うるので、明細行の商品名で判定する
if grep -qi 'Microsoft 365 Copilot' "$TXT"; then
  ok "Microsoft 365 Copilot の請求書や"
  grep -i -m1 'Microsoft 365 Copilot' "$TXT" | sed 's/^ */  /'
else
  red "Copilot の請求書ちゃうかもしれん。中身の冒頭を出すで:"
  head -20 "$TXT" | sed 's/^/  /'
  die "Copilot の明細が見つからん。DLするファイルを間違えてへんか確認してや"
fi

# --- 3. 請求書発行日をPDFから取得 ---

# 「請求書発行日: 2026/09/15」形式。ハードコードせず必ず実データから取る
ISSUE_DATE="$(grep -oE '請求書発行日:[[:space:]]*[0-9]{4}/[0-9]{2}/[0-9]{2}' "$TXT" \
              | head -1 | grep -oE '[0-9]{4}/[0-9]{2}/[0-9]{2}')" || true

[[ -n "$ISSUE_DATE" ]] || die "請求書発行日をPDFから取得できへんかった。書式が変わったかもしれん"

YMD="${ISSUE_DATE//\//}"
ok "請求書発行日: $ISSUE_DATE"

# 規約では請求日＝その月の15日。ズレてたら止めて人間に判断させる
if [[ "${YMD:6:2}" != "15" ]]; then
  red "発行日が15日ちゃう（$ISSUE_DATE）。規約では毎月15日のはずや"
  die "想定外の日付やから止めた。手動で確認してや"
fi

DEST_NAME="${AUTO_NO}_${YMD}_${NAME_SUFFIX}.pdf"
echo "  設置名: $DEST_NAME"

# --- 4. 共有フォルダの到達確認と衝突チェック ---

header "設置先の確認"

[[ -x "$PS" ]] || die "powershell.exe が無い: $PS"

[[ "$(ps_run "if (Test-Path -LiteralPath '$SHARE_DIR') { 'YES' } else { 'NO' }")" == "YES" ]] \
  || die "共有フォルダに到達できへん: $SHARE_DIR"
ok "共有フォルダに到達できた"

DEST_PATH="${SHARE_DIR}\\${DEST_NAME}"

# 上書きは絶対にせん。経理が処理済みのファイルを壊す事故を物理的に防ぐ
if [[ "$(ps_run "if (Test-Path -LiteralPath '$DEST_PATH') { 'YES' } else { 'NO' }")" == "YES" ]]; then
  die "同名ファイルが既にある。上書きはせえへん: $DEST_NAME"
fi
ok "同名ファイルなし（上書きの心配なし）"

# --- 5. コピー ---

header "コピー"

echo "  from: $SRC"
echo "  to  : ${SHARE_DIR}"
echo "  name: $DEST_NAME"

if [[ "$COMMIT" != true ]]; then
  echo
  red "ドライラン。実際にはコピーしてへん"
  echo "問題なければ --commit を付けて再実行してや:"
  echo "  $0 '$SRC' --commit"
  exit 0
fi

SRC_WIN="$(wslpath -w "$SRC")"
ps_run "Copy-Item -LiteralPath '$SRC_WIN' -Destination '$DEST_PATH' -ErrorAction Stop" >/dev/null \
  || die "コピーに失敗した"

# --- 6. 転送先で照合 ---

SRC_SIZE="$(stat -c%s "$SRC")"
DEST_SIZE="$(ps_run "(Get-Item -LiteralPath '$DEST_PATH').Length")"

[[ "$SRC_SIZE" == "$DEST_SIZE" ]] \
  || die "サイズが合わへん（元 $SRC_SIZE / 先 $DEST_SIZE）。転送が壊れとる"

SRC_HASH="$(sha256sum "$SRC" | cut -d' ' -f1 | tr 'a-f' 'A-F')"
DEST_HASH="$(ps_run "(Get-FileHash -LiteralPath '$DEST_PATH' -Algorithm SHA256).Hash")"

[[ "$SRC_HASH" == "$DEST_HASH" ]] \
  || die "ハッシュが合わへん。転送が壊れとる"

ok "設置完了（サイズ・SHA256 ともに一致）"
echo "  $DEST_NAME  ($DEST_SIZE bytes)"
echo
echo "このあと 斎部経費レコード登録済/ へ移すのは経理側の作業や。こっちの担当はここまで。"
