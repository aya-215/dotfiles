"""変更点ページの HTML に、`src="shots/…"` の画像を base64 で埋め込んで1ファイルにする。

使い方: python3 -I build.py <書いた HTML> <出力 HTML>
画像は書いた HTML と同じフォルダの shots/ から読む。document-share には出力の1ファイルだけを送る。
"""
import base64
import mimetypes
import pathlib
import re
import sys

src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
html = src.read_text(encoding="utf-8")


def inline(m: re.Match) -> str:
    path = src.parent / "shots" / m.group(1)
    mime = mimetypes.guess_type(path.name)[0] or "image/png"
    return f'src="data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"'


html = re.sub(r'src="shots/([^"]+)"', inline, html)
out.write_text(html, encoding="utf-8")
print(f"{out} {len(html)} bytes")
