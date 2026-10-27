# somu-search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 総務パック（ミラー）の任意のボリュームを、eB-API 直叩き＋手元キャッシュで検索し、必要なら添付の本文も読めるスキルを作る。

**Architecture:** `.claude-global/skills/somu-search/` に SKILL.md と `scripts/somu.py`（標準ライブラリのみ・1ファイル）を置く。eB-API への POST は `Api` クラスに閉じ込め、送信関数を差し替えられるようにしてオフラインでテストする。取得・保存・検索・テキスト化は決定的にスクリプトが行い、Claude はボリューム選択と回答を担う。

**Tech Stack:** Python 3 標準ライブラリ（urllib, xml.etree, zipfile, unicodedata, json, argparse）、unittest、`pdftotext`（nix 導入済み）

**Spec:** `docs/superpowers/specs/2026-10-27-somu-search-design.md`

## Global Constraints

- 読むだけ。登録系（`eb-api-register`）は呼ばない。MCP は使わない。
- 接続先は実行時に `~/.dotfiles/.mcp.json` の `mcpServers["eb-api-somu"].headers` の `ebase-api-url` と `ebase-viewer-url` から読む。IP・ホスト名・item_id をスキル・テスト・コミットに書かない（dotfiles は PUBLIC）。テストのフィクスチャは `http://example.invalid/...` と架空の ID を使う。
- 添付のベース URL は `ebase-viewer-url` のスキーム＋ホスト＋`/volume/`。添付 URL は `<base><vol>/imag/<filename の \ を / に>`。
- サーバーの共有フォルダ（UNC・管理共有）には触れない。添付は HTTP で1ファイルずつ取る。
- キャッシュは `~/.cache/somu-search/<vol>.json`。環境変数 `SOMU_SEARCH_CACHE` で置き場所を差し替えられる（テスト用）。自動の期限切れは無し。取り直しは `--refresh` のみ。
- 全件取得の前に件数を数え、**10000 件を超えたら `--yes` が無い限り件数を出して終了コード 3 で止まる**。初回・`--refresh` とも同じ。
- `getSpecDataLite` は item_id を **200 件ずつ**、spec_type ごとに `spec_title="*"` で取る。`inv` で始まる spec_title は保存しない。
- 全 ID は `getItems` に空の `<search target="SPEC"></search>` を付けて取る。eB-API の条件検索は使わない。
- 詳細 URL は `<ebase-viewer-url>/DispDetail.do?volumeName=<vol>&itemID=<item_id>`。
- XML は UTF-8 バイト列で `Content-Type: text/plain; charset=utf-8` として POST。
- 実行は `python3 -I ~/.claude/skills/somu-search/scripts/somu.py <サブコマンド> ...`。エラーは `ERROR: ...` を stderr に出し終了コード 2（件数確認待ちだけ 3）。トレースバックを出さない。
- コメント・メッセージは日本語。コメントは非自明な WHY だけ。

## Review Focus

- ボリュームIDを `204` のようにゼロ埋め無しで渡される → `00204` として扱う。`00204_WK` のような接尾辞付きはそのまま。（Task 1 にテスト）
- 社内ネットワーク外・サーバー停止で接続できない → `ERROR: eB-API に接続できへん: ...` で終了コード 2、トレースバック無し。（Task 1 にテスト）
- 取得途中で中断・失敗 → 前回のキャッシュが壊れない（一時ファイルに書いてから置き換える）。（Task 2 にテスト）
- 一部の spec_type だけ `getSpecDataLite` が 404 を返す → その型を飛ばして警告を stderr に出し、残りは保存する。（Task 2 にテスト）
- IP の部分一致 `10.0.1.19` で `...190`〜`...199` も当たる → 値が語と完全一致した項目を持つレコードを先頭に並べる。（Task 2 にテスト）

---

## File Structure

| ファイル | 責務 |
|---|---|
| `.claude-global/skills/somu-search/scripts/somu.py` | 設定読込・eB-API 呼び出し・全件取得とキャッシュ・検索・添付取得とテキスト化・CLI |
| `.claude-global/skills/somu-search/scripts/test_somu.py` | オフラインのユニットテスト（送信関数を差し替え） |
| `.claude-global/skills/somu-search/SKILL.md` | 起動条件・手順・よく使うボリューム・読み方の注意・止まったとき |

`~/.claude/skills` は `.claude-global/skills` へのリンクなので、配置するだけで有効になる（Task 4 で確認）。

テスト実行コマンド（全タスク共通）:

```bash
python3 -m unittest discover -s /home/aya/.dotfiles/.claude-global/skills/somu-search/scripts -v
```

---

### Task 1: 設定読込と eB-API 呼び出し層

**Files:**
- Create: `.claude-global/skills/somu-search/scripts/somu.py`
- Create: `.claude-global/skills/somu-search/scripts/test_somu.py`
- 同じコミットに含める: `docs/superpowers/specs/2026-10-27-somu-search-design.md`, `docs/superpowers/plans/2026-10-27-somu-search.md`

**Interfaces:**
- Produces:
  - `class SomuError(Exception)` — 利用者向けメッセージを持つ。CLI が `ERROR: ` を付けて終了コード 2。
  - `@dataclass Config(api_url: str, viewer_url: str, file_base: str)`
  - `load_config(path: str = MCP_JSON) -> Config` — 無い・壊れている・定義が無いときは `SomuError`。
  - `norm_vol(v: str) -> str` — 数字部分を5桁ゼロ埋め。`"204"→"00204"`, `"204_WK"→"00204_WK"`, `"00204"→"00204"`。
  - `class Api(api_url: str, post: Callable[[str, bytes], bytes] | None = None)` — `post` 省略時は urllib で POST（timeout 300 秒）。接続失敗は `SomuError("eB-API に接続できへん: ...")`。
    - `volumes() -> list[tuple[str, str]]` — `(voldbname, volname)`
    - `spec_info(vol: str) -> list[dict]` — 各要素 `{"spec_type", "spec_title", "data_type"}`
    - `item_ids(vol: str) -> list[str]`
    - `spec_values(vol: str, ids: list[str], spec_type: str) -> dict[str, dict[str, str]]` — `{item_id: {spec_title: value}}`。空値と `inv` 始まりは除く。応答 status が 200 以外なら `SomuError`。
    - `item_files(vol: str, item_id: str) -> list[dict]` — `getItemImage` の各 `<image>` の子要素を dict に。
  - 定数 `MCP_JSON = os.path.expanduser("~/.dotfiles/.mcp.json")`

- [ ] **Step 1: 失敗するテストを書く**

`FakePost` は受け取った XML（UTF-8 デコード済み）を記録し、コマンド名ごとに用意した応答 XML を返す。

```python
def test_norm_vol(self):
    self.assertEqual(somu.norm_vol("204"), "00204")
    self.assertEqual(somu.norm_vol("204_WK"), "00204_WK")
    self.assertEqual(somu.norm_vol("00204"), "00204")

def test_load_config_derives_file_base(self):
    # tmp に {"mcpServers":{"eb-api-somu":{"headers":{"ebase-api-url":"http://example.invalid:8080/x/eb-api","ebase-viewer-url":"http://example.invalid/somu_v4"}}}}
    cfg = somu.load_config(path)
    self.assertEqual(cfg.file_base, "http://example.invalid/volume/")

def test_load_config_missing_raises(self):
    with self.assertRaises(somu.SomuError): somu.load_config("/nonexistent.json")

def test_volumes_parses(self):  # 応答 <volume><voldbname>00001</voldbname><volname>テスト</volname></volume>
    self.assertEqual(api.volumes(), [("00001", "テスト")])

def test_item_ids_sends_empty_search(self):
    api.item_ids("00204")
    self.assertIn('<search target="SPEC"></search>', fake.sent[-1])

def test_spec_values_drops_inv_and_empty(self):
    # 応答: item t1 に invデータ登録日=2021/01/01, IPアドレス=10.0.0.1, OS=(空)
    self.assertEqual(api.spec_values("00095", ["t1"], "メインスペック"), {"t1": {"IPアドレス": "10.0.0.1"}})

def test_spec_values_404_raises(self):
    with self.assertRaises(somu.SomuError): api.spec_values("00095", ["t1"], "X")

def test_post_failure_is_somu_error(self):
    api = somu.Api("http://127.0.0.1:9/eb-api")  # 閉じたポート
    with self.assertRaises(somu.SomuError) as cm: api.volumes()
    self.assertIn("接続できへん", str(cm.exception))

def test_request_is_utf8_bytes(self):
    api.spec_info("00204")
    self.assertIsInstance(fake.raw[-1], bytes)
```

- [ ] **Step 2: テストが落ちることを確認** — 上のテストコマンド。Expected: `ModuleNotFoundError` か `AttributeError` で FAIL。
- [ ] **Step 3: `somu.py` に上の Interfaces を実装** — XML は文字列テンプレートで組み、値は `xml.sax.saxutils.escape` / `quoteattr` で埋める。応答は `xml.etree.ElementTree` で読む。
- [ ] **Step 4: テストが通ることを確認** — Expected: 全 PASS。
- [ ] **Step 5: Commit**

```bash
git -C /home/aya/.dotfiles add docs/superpowers/specs/2026-10-27-somu-search-design.md docs/superpowers/plans/2026-10-27-somu-search.md .claude-global/skills/somu-search/scripts/
git -C /home/aya/.dotfiles commit -m "feat(claude): 総務パックを eB-API 直叩きで読む somu-search スキルの API 層を追加する"
```

---

### Task 2: 全件取得・キャッシュ・検索と CLI（volumes / specs / search）

**Files:**
- Modify: `.claude-global/skills/somu-search/scripts/somu.py`
- Modify: `.claude-global/skills/somu-search/scripts/test_somu.py`

**Interfaces:**
- Consumes: Task 1 の `Api`, `Config`, `load_config`, `norm_vol`, `SomuError`
- Produces:
  - `LARGE_THRESHOLD = 10000`, `BATCH = 200`
  - `class NeedsConfirm(Exception)` — `count: int` を持つ。CLI が件数を出して終了コード 3。
  - `cache_path(vol: str) -> str` — `$SOMU_SEARCH_CACHE` か `~/.cache/somu-search` の下の `<vol>.json`
  - `load_cache(vol: str) -> dict | None`
  - `dump_volume(api: Api, vol: str, confirmed: bool = False) -> dict` — 戻り値 `{"vol", "fetched_at"(ISO8601), "specs": [...], "items": [{"item_id": ..., "<spec_type>:<spec_title>": value, ...}]}`。件数 > `LARGE_THRESHOLD` かつ未確認なら `NeedsConfirm`。spec_type ごとの `SomuError` は stderr に `WARN: <type> を飛ばした: ...` を出して続行。保存は一時ファイル → `os.replace`。
  - `get_or_dump(api, vol, refresh=False, confirmed=False) -> dict`
  - `normalize(s: str) -> str` — NFKC ＋ casefold
  - `search(items: list[dict], words: list[str]) -> list[tuple[dict, list[str]]]` — 全語を（どの項目でもよいので）含むレコードと、ヒットした項目キーの一覧。値が語のどれかと（正規化後に）完全一致する項目を持つレコードを先頭に、残りは item_id 順。
  - `snippet(text: str, word: str, width: int = 60) -> str` — 最初のヒット位置の前後 `width` 文字。改行は空白に。切った側に `…`。
  - `detail_url(viewer_url: str, vol: str, item_id: str) -> str`
  - `main(argv: list[str] | None = None) -> int` — サブコマンド `volumes [語]`（`_WK`/`_DEF`/`_WF` 接尾辞は `--all` 無しなら隠す）、`specs <vol>`、`search <vol> <語...> [--refresh] [--yes] [--limit N(既定20)]`。

search の出力形式（ビルダーの判断で細部は変えてよい。データ時点と総件数は必須）:

```
00204 ■社内規定 / 2026-10-27T10:00 時点 / 317件中 4件ヒット
=== <item_id>  <詳細URL>
  [メインスペック:概要] …テレワーク勤務を実施するため、当社就業規則…
  [メインスペック:改定日] 2024/09/19
```

ヒットした項目は抜粋、ほかの項目は 80 文字以内のものだけ全文で出す。

- [ ] **Step 1: 失敗するテストを書く**

```python
def test_dump_batches_by_200_and_saves(self):  # FakePost: item_ids 450件, spec_info 2型
    data = somu.dump_volume(api, "00095")
    self.assertEqual(len(data["items"]), 450)
    self.assertEqual(fake.count("getSpecDataLite"), 3 * 2)
    self.assertTrue(os.path.exists(somu.cache_path("00095")))

def test_dump_large_needs_confirm(self):  # item_ids 10001件
    with self.assertRaises(somu.NeedsConfirm) as cm: somu.dump_volume(api, "00001")
    self.assertEqual(cm.exception.count, 10001)
    self.assertEqual(fake.count("getSpecDataLite"), 0)

def test_dump_skips_failing_spec_type(self):  # 型 "壊れ" だけ 404
    data = somu.dump_volume(api, "00095")
    self.assertIn("メインスペック:IPアドレス", data["items"][0])

def test_failed_dump_keeps_old_cache(self):  # 旧キャッシュを置いてから item_ids で SomuError
    with self.assertRaises(somu.SomuError): somu.dump_volume(api, "00095")
    self.assertEqual(somu.load_cache("00095")["fetched_at"], old["fetched_at"])

def test_search_and_width_case(self):
    items = [{"item_id": "t1", "a:b": "ＴＥＬＥワーク規則"}, {"item_id": "t2", "a:b": "出張"}]
    self.assertEqual([r[0]["item_id"] for r in somu.search(items, ["teleワーク"])], ["t1"])

def test_search_and_of_words(self):
    items = [{"item_id": "t1", "a:x": "テレワーク", "a:y": "開発"}, {"item_id": "t2", "a:x": "テレワーク"}]
    self.assertEqual([r[0]["item_id"] for r in somu.search(items, ["テレワーク", "開発"])], ["t1"])

def test_search_exact_value_first(self):
    items = [{"item_id": "t1", "m:IP": "10.0.1.190"}, {"item_id": "t2", "m:IP": "10.0.1.19"}]
    self.assertEqual([r[0]["item_id"] for r in somu.search(items, ["10.0.1.19"])], ["t2", "t1"])

def test_snippet_ellipsis(self):
    self.assertEqual(somu.snippet("あ" * 100 + "X" + "い" * 100, "X", 3), "…あああXいいい…")

def test_cli_large_exit_3(self):  # main(["search","00001","x"]) を FakePost 注入で
    self.assertEqual(rc, 3)
```

CLI テストのために `main` は `Api` を作る関数（`make_api(cfg) -> Api`）を経由させ、テストではそれを差し替える。

- [ ] **Step 2: テストが落ちることを確認**
- [ ] **Step 3: 上の Interfaces を実装**
- [ ] **Step 4: テストが通ることを確認**
- [ ] **Step 5: 実機で確認**

```bash
python3 -I /home/aya/.dotfiles/.claude-global/skills/somu-search/scripts/somu.py volumes 規定
python3 -I /home/aya/.dotfiles/.claude-global/skills/somu-search/scripts/somu.py search 95 <セッション中に調べた内部IP>
```

Expected: 1つ目に `00204 ■社内規定` が出る。2つ目でその IP と完全一致するレコードが先頭に出る（IP やサーバー名はコミットに書かない）。

- [ ] **Step 6: Commit**

```bash
git -C /home/aya/.dotfiles add .claude-global/skills/somu-search/scripts/
git -C /home/aya/.dotfiles commit -m "feat(claude): somu-search にボリューム一覧・全件キャッシュ・横断検索を追加する"
```

---

### Task 3: 添付の一覧とテキスト化（files / text）

**Files:**
- Modify: `.claude-global/skills/somu-search/scripts/somu.py`
- Modify: `.claude-global/skills/somu-search/scripts/test_somu.py`

**Interfaces:**
- Consumes: `Api.item_files`, `Config.file_base`, `norm_vol`, `SomuError`
- Produces:
  - `file_url(file_base: str, vol: str, filename: str) -> str` — `<file_base><vol>/imag/<filename の \ を />`
  - `is_old(f: dict) -> bool` — `link_comment` に `old`（大小無視）を含む
  - `extract_text(path: str, fmt: str) -> str` — `fmt` は `format` 要素の値（大小無視）。PDF→`pdftotext -layout <path> -`、DOCX→`word/document.xml` の `w:p` ごとに `w:t` を連結して改行区切り、XLSX→`xl/sharedStrings.xml` と `xl/worksheets/sheet*.xml` からシートごとにセルを行単位のタブ区切りで、TXT→UTF-8（失敗時 cp932）。それ以外（DOC・XLS 等）は `Unsupported` 例外。
  - `class Unsupported(Exception)`
  - CLI: `files <vol> <item_id>` — 旧版を後ろに回して一覧（file_id、link_title、download_name、format、link_comment、URL）。`text <vol> <item_id> [file_id...] [--old] [--max-chars N(既定20000)]` — file_id 省略時は旧版を除く全件。各ファイルの見出しに link_title と URL。`Unsupported` は「この形式はテキストにできへん。URL: ...」と出して次へ。ダウンロードは `tempfile.TemporaryDirectory` に。

- [ ] **Step 1: 失敗するテストを書く**

```python
def test_file_url(self):
    self.assertEqual(somu.file_url("http://example.invalid/volume/", "00204", "file0222\\t010.pdf"),
                     "http://example.invalid/volume/00204/imag/file0222/t010.pdf")

def test_is_old(self):
    self.assertTrue(somu.is_old({"link_comment": "OLD 2019"}))
    self.assertFalse(somu.is_old({"link_comment": "2024/9/19更新"}))

def test_extract_docx(self):  # zipfile で word/document.xml に 2段落 "第1条", "在宅勤務" を作る
    self.assertEqual(somu.extract_text(p, "DOCX"), "第1条\n在宅勤務")

def test_extract_xlsx(self):  # sharedStrings ["IP","PC名"], sheet1 の1行目 A1=s0, B1=s1
    self.assertIn("IP\tPC名", somu.extract_text(p, "xlsx"))

def test_extract_doc_unsupported(self):
    with self.assertRaises(somu.Unsupported): somu.extract_text(p, "DOC")

def test_extract_pdf(self):  # pdftotext が無ければ skipTest。最小 PDF をバイト列で用意し "Hello" を含むこと
```

- [ ] **Step 2: テストが落ちることを確認**
- [ ] **Step 3: 上の Interfaces を実装**
- [ ] **Step 4: テストが通ることを確認**
- [ ] **Step 5: 実機で確認**

```bash
S=/home/aya/.dotfiles/.claude-global/skills/somu-search/scripts/somu.py
python3 -I $S search 204 テレワーク 開発
python3 -I $S files 204 <上でヒットした開発テレワークの item_id>
python3 -I $S text 204 <同 item_id>
```

Expected: 本文に「開発業務従事者のテレワークルール」「週２日～４日」が出る。誓約書（docx）の本文も出る。

- [ ] **Step 6: Commit**

```bash
git -C /home/aya/.dotfiles add .claude-global/skills/somu-search/scripts/
git -C /home/aya/.dotfiles commit -m "feat(claude): somu-search で添付の一覧と PDF・Word・Excel の本文を読めるようにする"
```

---

### Task 4: SKILL.md と仕上げ

**Files:**
- Create: `.claude-global/skills/somu-search/SKILL.md`

**Interfaces:**
- Consumes: Task 2・3 の CLI

- [ ] **Step 1: SKILL.md を書く** — kintai-check の SKILL.md と同じ構成（frontmatter / Overview / 手順 / 読み方の注意 / 止まったとき）。含めるもの:
  - frontmatter `description`: 「社内のサーバーやPCのIPアドレス」「社内規定・就業規則」「ルールDBの開発知見」など総務パックにある社内情報を調べるときに使う、とトリガー語（「〇〇のIP」「内部IP」「社内規定で」「ルールDBで」「総務パックで調べて」「/somu-search」）を並べる。「取得と検索は scripts/somu.py が決定的に行う」を明記。
  - よく使うボリュームの早見表（ボリューム名と用途。ID を書くかはビルダーの判断。仕様書参照）
  - 手順: `volumes [語]` で選ぶ → `search` → 0件なら語を減らす・言い換える・別ボリューム → 本文が要るときだけ `files` → `text`
  - 終了コード 3（件数確認）のときはユーザーに件数を伝えて了承を得てから `--yes` で再実行する
  - 読み方の注意: ミラーなので本番より遅れることがある / おかしいと思ったら `--refresh` / 改定日と添付の版が食い違うことがある / 回答には詳細URLを添える
  - 止まったときの表: `.mcp.json` が無い・接続できない（社内ネットワーク/VPN）・テキストにできない形式
  - 「サーバーの共有フォルダを直接探しに行かない」を明記
- [ ] **Step 2: スキルとして見えることを確認**

```bash
ls -l /home/aya/.claude/skills/somu-search/SKILL.md
```

Expected: ファイルが見える（リンク経由）。

- [ ] **Step 3: 全テストを通す** — 共通のテストコマンド。Expected: 全 PASS。
- [ ] **Step 4: 社内情報が混ざっていないことを確認**

```bash
git -C /home/aya/.dotfiles diff --cached --stat; grep -rnE '192\.168\.|203\.140\.|t0001[0-9]{8}|ebase-jp\.com' /home/aya/.dotfiles/.claude-global/skills/somu-search /home/aya/.dotfiles/docs/superpowers/plans/2026-10-27-somu-search.md /home/aya/.dotfiles/docs/superpowers/specs/2026-10-27-somu-search-design.md
```

Expected: grep の出力なし。

- [ ] **Step 5: Commit と push**

```bash
git -C /home/aya/.dotfiles add .claude-global/skills/somu-search/SKILL.md
git -C /home/aya/.dotfiles commit -m "feat(claude): 総務パックを選んで検索する somu-search スキルの手順書を追加する"
git -C /home/aya/.dotfiles push
```
