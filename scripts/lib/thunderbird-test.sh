#!/bin/bash
# thunderbird-test.sh - thunderbird_collect.py の除外・判定ロジックのテスト
# 使用方法: bash scripts/lib/thunderbird-test.sh （全部 ok なら ALL OK で exit 0）
#
# MCP サーバや実メールには触らない。ノイズ除去・宛先判定・署名除去といった
# 決定的な部分だけを関数単位で検証する（実データ依存の確認は --stats で行う）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

TB_MCP_ENTRY=/dev/null python3 - "$SCRIPT_DIR" <<'PYEOF'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("tb", f"{sys.argv[1]}/thunderbird_collect.py")
tb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tb)

fails = 0


def check(desc, got, want):
    global fails
    if got == want:
        print(f"ok: {desc}")
    else:
        print(f"NG: {desc} → got={got!r} want={want!r}")
        fails += 1


def keep(author="x@example.com", subject="件名"):
    """main() 内の keep() と同じ判定を再現する。"""
    a = tb.addr(author)
    if a in tb.EXCLUDE_AUTHORS:
        return False
    if any(dom in a for dom in tb.EXCLUDE_AUTHOR_DOMAINS):
        return False
    return not tb.EXCLUDE_SUBJECT_RE.search(subject or "")


# --- 宛先判定 ---
check("to にアドレスで自分",
      tb.addressed_to_me({"recipients": "foo@ebase.co.jp, mori.a@ebase.co.jp"}), True)
check("表示名だけで自分（アドレス省略）",
      tb.addressed_to_me({"recipients": "eBASE 森 彪人 eBASE 松本 久方"}), True)
check("スペースなし表示名でも自分",
      tb.addressed_to_me({"recipients": "eBASE森彪人"}), True)
check("AIチームML",
      tb.addressed_to_me({"recipients": "ai-team@ebase.co.jp"}), True)
check("自分が居ない宛先は除外",
      tb.addressed_to_me({"recipients": "yamamoto.m@ebase.co.jp, 開発課内"}), False)
check("recipients 欠損でも落ちない",
      tb.addressed_to_me({}), False)

# --- ノイズ送信元 ---
check("GitHub通知は除外", keep(author="notifications@github.com"), False)
check("勤怠通知は除外", keep(author="kintai@ebase.co.jp"), False)
check("予定通知は除外", keep(author="schedule@ebase.co.jp"), False)
check("表示名付きでも除外", keep(author="eBASE勤怠 <kintai@ebase.co.jp>"), False)
check("大文字混在でも除外", keep(author="<Kintai@eBASE.co.jp>"), False)
check("Anthropicはドメインで除外",
      keep(author="no-reply-abc@mail.anthropic.com"), False)
check("人間からのメールは採用", keep(author="k.ochi@ebase.co.jp"), True)

# --- 件名による除外 ---
check("早退連絡は除外", keep(subject="早退連絡（葛井）"), False)
check("掃除当番は除外", keep(subject="08/03~08/07の掃除当番は[松本さん]です"), False)
check("懇親会は除外", keep(subject="2026年度 開発部懇親会のお知らせ"), False)
check("案件メールは採用", keep(subject="シフトオン/AI eBASEの件"), True)

# --- 署名・引用の除去 ---
body = "越智さん\nお疲れ様です。\n本題です。\n-- \n:::::\neBASE株式会社\nTEL: 06-0000-0000"
check("署名以降を落とす", "TEL" in tb.clean_body(body), False)
check("署名前の本文は残る", "本題です。" in tb.clean_body(body), True)
check("引用行を落とす",
      ">前のメール" in tb.clean_body("返信します\n>前のメール"), False)
check("全角引用も落とす",
      "＞前のメール" in tb.clean_body("返信します\n＞前のメール"), False)
check("空文字でも落ちない", tb.clean_body(""), "")
check("None でも落ちない", tb.clean_body(None), "")
check(f"本文は{tb.BODY_CHARS}文字で切る",
      len(tb.clean_body("あ" * 2000)) <= tb.BODY_CHARS + 1, True)

# --- 件名の正規化 ---
check("Re: を剥がす", tb.normalize_subject("Re: 件名"), "件名")
check("多重 RE:/FW: を剥がす", tb.normalize_subject("RE: FW: 件名"), "件名")
check("件名なしを補う", tb.normalize_subject(""), "(件名なし)")

print("---")
if fails:
    print(f"{fails} 件失敗")
    sys.exit(1)
print("ALL OK")
PYEOF
