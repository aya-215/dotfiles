#!/usr/bin/env python3
"""todo.md の唯一の書き込み口。変更案 JSON を検証して適用し、git にコミットする。

使い方: apply.py --changes <json> [--todo PATH] [--decisions PATH] [--today YYYY-MM-DD] [--allow-user]
source user（ユーザー指示の変更）は --allow-user のときだけ受け付け、環境変数 TODO_AI_DENY_USER=1 なら常に拒む。
終了コード: 0 適用（変更なし含む） / 3 nvim で編集中のためスキップ / 2 検証違反で未適用 / 1 その他
"""
import argparse
import copy
import datetime
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import time
import unicodedata
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import decisions
import todo_md
from origin import origin_of, title_written_by
from todo_md import TASK_SECTIONS, Doc, Item

SOURCES = ("ai", "sync", "user")
USER_OPS = ("edit_title", "delete", "note")
AI_OPS = ("edit_title",)
CLEANUP_PREFIX = decisions.CLEANUP_PREFIX
OPEN_SECTIONS = ("やる", "待ち")
ARCHIVE_DAYS = 30
OP_LABELS = {
    "add": "追加", "move": "移動", "set_next": "next更新", "attach": "紐付け",
    "edit_title": "タイトル変更", "delete": "削除", "note": "意図",
    "order": "並べ替え", "confirm": "確認待ち", "archive": "アーカイブ",
}
_CONFIRM_Q = re.compile(r"(\d+)\. (.+)\Z")
_CONFIRM_FIELD = re.compile(r"\s+(事実|選択|回答)[:：] ?(.*)\Z")
_CONFIRM_OPTIONS = re.compile(r"\s+(\S.*)\Z")
RECOMMENDED = "★"
OLD_RECOMMENDED = "（おすすめ）"
_OPTION = re.compile(r"(\S+) (.*?)(" + RECOMMENDED + "|" + OLD_RECOMMENDED + r")?\Z")
KINDS = ("policy", "before_share", "manual", "conflict", "is_task", "still_needed")
_TAG = re.compile(r" \[(" + "|".join(KINDS) + r") (.+)\]\Z")
_QUOTE = re.compile(r"『([^『』]+)』")
_NUMBER = re.compile(r"\A\d+\. ")
# 回答に基づく op（by_answer）にしてよい op。order・note は行を名指ししないか user だけの op なので外す
ANSWER_OPS = ("add", "move", "set_next", "attach", "edit_title", "delete")
PENDING_NAME = "todo-pending.json"
GIT_RETRIES = 10


class ChangeError(ValueError):
    """変更案そのものが不正、または適用すると人の記述を失う。"""


@dataclass
class Effects:
    """apply_changes が source user の op について集める副産物。

    intents は記録する意図（{"ref", "value", "op", 任意で "prev_ref"}）。deleted / retitled は適用前から
    あった行のうち delete で消した行・edit_title で題を変えた行（変更前の状態）で、validate の免除に使う。
    reopened は完了から出した行の (ref, 今の節)。完了へ戻さない pin として記録する。
    aliases は key の無い行に key を付けた (key, 旧 ref) と、source ai が key の無い行の題を変えた (新 ref, 旧 ref)。
    source を問わず集め、alias として記録する。
    answer_* は source ai の by_answer の op の分。answer_intents は記録する意図（{"ref", "value", "op", "by_answer",
    任意で "prev_ref"}）、answer_deleted / answer_retitled / answer_reopened は消した・題を変えた・完了から出した行の
    実行前の状態で、source ai の validate の免除に使う。
    pending は confirm を書いた実行での todo-pending.json の中身（on_answer のあるブロック）。confirm が無ければ None。
    held_answers は by_answer の回答文が今の回答欄と違ったブロックの (ref, kind)。記録せず回答欄ごと確認待ちに残す。
    skipped は飛ばした op の ops 内の位置（同じ op が2回入ることもある）。
    """

    intents: "list[dict]" = field(default_factory=list)
    reopened: "list[tuple[str, str]]" = field(default_factory=list)
    deleted: "list[Item]" = field(default_factory=list)
    retitled: "list[Item]" = field(default_factory=list)
    aliases: "list[tuple[str, str]]" = field(default_factory=list)
    answer_intents: "list[dict]" = field(default_factory=list)
    answer_deleted: "list[Item]" = field(default_factory=list)
    answer_retitled: "list[Item]" = field(default_factory=list)
    answer_reopened: "list[Item]" = field(default_factory=list)
    pending: "list[dict] | None" = None
    held_answers: "set[tuple[str, str]]" = field(default_factory=set)
    skipped: "list[int]" = field(default_factory=list)


def _str(op: dict, name: str, required: bool = True) -> "str | None":
    v = op.get(name)
    if v is None and not required:
        return None
    if not isinstance(v, str) or (required and not v):
        raise ChangeError(f"{op.get('op')}: {name} が文字列でない: {v!r}")
    if "\n" in v or "\r" in v:
        raise ChangeError(f"{op.get('op')}: {name} に改行は入れられない: {v!r}")
    return v


def _key(op: dict) -> str:
    key = _str(op, "key")
    if not todo_md.is_key(key):
        raise ChangeError(f"{op['op']}: key の形式が違う: {key!r}")
    _str(op, "url")
    return key


def _find(doc: Doc, ref: str) -> "list[tuple[str, int]]":
    return [(s, i) for s in TASK_SECTIONS for i, it in enumerate(doc.sections[s]) if it.ref == ref]


def _note(op: dict, head: str, url: "str | None") -> str:
    s = head
    if op.get("reason"):
        s += f": {op['reason']}"
    if url:
        s += f" {url}"
    return s


def split_facts(text: str) -> "tuple[str, str]":
    """タグを外した問いの行を (問い, 事実) に分ける。事実は末尾の釣り合った（…）。問いの途中の括弧は事実にしない。"""
    if not text.endswith("）"):
        return text, ""
    depth = 0
    for i in range(len(text) - 1, 0, -1):
        if text[i] == "）":
            depth += 1
        elif text[i] == "（":
            depth -= 1
            if depth == 0:
                return text[:i], text[i + 1:-1]
    return text, ""


def _field(lines: "list[str]", i: int, name: str) -> "str | None":
    f = _CONFIRM_FIELD.match(lines[i]) if i < len(lines) else None
    return f.group(2) if f and f.group(1) == name else None


def parse_confirm(lines: "list[str]") -> "list[dict]":
    """確認待ちをブロックの列として厳密に読む。崩れていれば ChangeError。

    新書式は「問い（事実） [タグ]・選択肢・回答」の3行（選択肢が無ければ2行）、旧書式は「問い [タグ]・事実・選択・回答」の4行。
    各ブロックは {"question"（事実を外しタグは残した問い）, "事実", "選択", "回答", "lines"}。ブロックの間の空行だけ許す。
    """
    blocks = []
    i = 0
    while i < len(lines):
        if not lines[i].strip():
            i += 1
            continue
        m = _CONFIRM_Q.match(lines[i])
        if not m:
            raise ChangeError(f"確認待ちに解釈できない行がある（全置換すると消える）: {lines[i]!r}")
        head = m.group(2)
        if _field(lines, i + 1, "事実") is not None:
            facts, opts, ans = _field(lines, i + 1, "事実"), _field(lines, i + 2, "選択"), _field(lines, i + 3, "回答")
            if opts is None or ans is None:
                raise ChangeError(f"確認待ちのブロックが崩れている（選択・回答の行が無い）: {lines[i]!r}")
            n = 4
        else:
            body = strip_tag(head)
            q, facts = split_facts(body)
            head = q + head[len(body):]
            opts, n = "", 2
            ans = _field(lines, i + 1, "回答")
            if ans is None:
                o = _CONFIRM_OPTIONS.match(lines[i + 1]) if i + 1 < len(lines) else None
                ans = _field(lines, i + 2, "回答") if o else None
                if ans is None:
                    raise ChangeError(f"確認待ちのブロックが崩れている（回答の行が無い）: {lines[i]!r}")
                opts, n = o.group(1), 3
        blocks.append({"question": head, "事実": facts, "選択": opts, "回答": ans, "lines": lines[i:i + n]})
        i += n
    return blocks


def parse_options(s: str) -> "list[dict]":
    """選択肢の行を {label, text, recommended} の列に読む。おすすめは ★（旧書式は（おすすめ））。"""
    out = []
    for part in s.split(" / ") if s else []:
        m = _OPTION.match(part)
        # 空白の無い断片は選択肢の文中の " / " で割れたものなので、前の選択肢に戻す
        if out and (not m or not m.group(2)):
            prev = out[-1]
            prev["text"] += " / " + part
            for mark in (RECOMMENDED, OLD_RECOMMENDED):
                if prev["text"].endswith(mark):
                    prev["text"], prev["recommended"] = prev["text"][: -len(mark)], True
        elif m:
            out.append({"label": m.group(1), "text": m.group(2), "recommended": bool(m.group(3))})
        else:
            out.append({"label": part, "text": part, "recommended": False})
    return out


def with_tag(question: str, kind: str, ref: str) -> str:
    return f"{question} [{kind} {ref}]"


def parse_tag(question: str) -> "tuple[str | None, str | None]":
    """問いの末尾の `[<kind> <ref>]` を (kind, ref) で返す。kind が先なので空白を含む title: の ref も読める。"""
    m = _TAG.search(question)
    return (m.group(1), m.group(2)) if m else (None, None)


def strip_tag(question: str) -> str:
    return _TAG.sub("", question)


def answer_records(blocks: "list[dict]") -> "list[tuple[str, str, str]]":
    """回答欄が埋まったブロックの (ref, kind, 回答)。タグが無ければ記録先が分からないので ChangeError。"""
    out = []
    for b in blocks:
        ans = b["回答"].strip()
        if not ans:
            continue
        kind, ref = parse_tag(b["question"])
        if ref is None:
            raise ChangeError(f"回答のある確認待ちに [kind ref] のタグが無い（記録先が分からない）: {b['lines'][0]!r}")
        out.append((ref, kind, ans))
    return out


def kept_answers(changes: dict) -> "set[tuple[str, str]]":
    """keep_answered（回答欄ごと確認待ちに残し、この実行では記録も反映もしないブロック）の (ref, kind)。"""
    keep = changes.get("keep_answered")
    if keep is None:
        return set()
    if "confirm" not in changes:
        raise ChangeError("keep_answered は confirm と一緒にだけ使える")
    if not isinstance(keep, list):
        raise ChangeError("keep_answered が配列でない")
    out = set()
    for k in keep:
        if not isinstance(k, dict) or not all(isinstance(k.get(n), str) and k[n] for n in ("ref", "kind")):
            raise ChangeError(f"keep_answered の要素の ref/kind が空でない文字列でない: {k!r}")
        out.add((k["ref"], k["kind"]))
    return out


def consumed_answers(blocks: "list[dict]", keep: "set[tuple[str, str]]") -> "list[tuple[str, str, str]]":
    """この実行で記録し、確認待ちから外す回答の (ref, kind, 回答)。keep_answered のブロックは除く。"""
    return [r for r in answer_records(blocks) if (r[0], r[1]) not in keep]


def answer_label(answer: str, options: "list[dict]") -> "str | None":
    """回答が選択肢の文字1つだけ（全角・小文字も可）なら、その選択肢の label。"""
    a = unicodedata.normalize("NFKC", answer).strip().upper()
    if len(a) != 1:
        return None
    return next((o["label"] for o in options if unicodedata.normalize("NFKC", o["label"]).upper() == a), None)


def quoted_titles(block: dict) -> "set[str]":
    """ブロックの問い・事実の本文に『』で引用された文字列。"""
    return set(_QUOTE.findall(strip_tag(block["question"]) + "\n" + block["事実"]))


def in_answer_scope(it: Item, block: dict) -> bool:
    """回答に基づく op で触ってよい行か: ブロックの ref の行か、題が問い・事実の『』の引用と完全一致する行。"""
    _, ref = parse_tag(block["question"])
    return it.ref == ref or it.title in quoted_titles(block)


def _answer_value(block: dict) -> str:
    ans = block["回答"].strip()
    options = parse_options(block["選択"])
    label = answer_label(ans, options)
    opt = next((o for o in options if o["label"] == label), None)
    shown = f"{opt['label']} {opt['text']}" if opt else ans
    return f"確認待ち「{strip_tag(block['question'])}」への回答「{shown}」に基づく"


def load_pending(repo: Path) -> "list[dict]":
    """todo-pending.json のブロック。無い・読めない・形が違うときは空。"""
    try:
        data = json.loads((Path(repo) / PENDING_NAME).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    blocks = data.get("blocks") if isinstance(data, dict) else None
    return [b for b in blocks if isinstance(b, dict)] if isinstance(blocks, list) else []


def pending_for(block: dict, pending: "list[dict]") -> "dict | None":
    """block の選択肢ごとの変更案。apply が書いたときと問い・選択肢の行が一字一句同じで、1つに決まるときだけ。"""
    kind, ref = parse_tag(block["question"])
    line = _CONFIRM_Q.match(block["lines"][0]).group(2)
    hits = [p for p in pending if (p.get("ref"), p.get("kind")) == (ref, kind)]
    if len(hits) != 1 or hits[0].get("line") != line or hits[0].get("options") != block["選択"]:
        return None
    on = hits[0].get("on_answer")
    return on if isinstance(on, dict) else None


def _bad_on_answer(e: dict) -> bool:
    on = e.get("on_answer")
    labels = {o.get("label") for o in e.get("options") or []}
    return not (isinstance(on, dict) and all(
        k in labels and isinstance(v, list)
        and all(isinstance(op, dict) and op.get("op") in ANSWER_OPS and "by_answer" not in op for op in v)
        for k, v in on.items()))


def _check_answers(blocks: "list[dict]", answered: list) -> None:
    """answered は記録には使わない。渡されたときだけ、回答欄から読んだ内容と一致するか確かめる。"""
    got = Counter()
    for a in answered:
        if not isinstance(a, dict) or not isinstance(a.get("answer"), str):
            raise ChangeError(f"answered の要素に answer の文字列が無い: {a!r}")
        if not all(isinstance(a.get(k), str) and a[k] for k in ("ref", "kind")):
            raise ChangeError(f"answered の要素の ref/kind が空でない文字列でない: {a!r}")
        got[(a["ref"], a["kind"], a["answer"].strip())] += 1
    if got != Counter(answer_records(blocks)):
        raise ChangeError("answered が確認待ちの回答欄と食い違う")


def _confirm_key(block: dict) -> tuple:
    """書式（新旧・★/（おすすめ））によらず、同じ問い・事実・選択なら同じになる比較用の値。"""
    body = strip_tag(block["question"])
    head = body + (f"（{block['事実']}）" if block["事実"] else "")
    opts = tuple((o["label"], o["text"], o["recommended"]) for o in parse_options(block["選択"]))
    return head, block["question"][len(body):], opts


def confirm_edit_errors(current: "list[str]", written: "list[str]") -> "list[str]":
    """確認待ちの問い・事実・選択が、apply が最後に書いた内容から変わっていれば違反を返す。

    written は最後の todo(ai)/todo(sync) コミット時点の確認待ち。人が足した文は全置換で消えるため止める。
    """
    try:
        cur = parse_confirm(current)
    except ChangeError as e:
        return [str(e)]
    try:
        prev = parse_confirm(written)
    except ChangeError:
        prev = []
    pool = Counter(_confirm_key(b) for b in prev)
    errs = []
    for b in cur:
        k = _confirm_key(b)
        if pool[k] <= 0:
            errs.append(f"確認待ちの問い・事実・選択が apply の書いた内容と違う（人の追記が消える）: {b['lines'][0]!r}")
        else:
            pool[k] -= 1
    return errs


def _render_entry(e) -> "tuple[str, str]":
    """confirm の要素を（番号を除いた問いの行, 選択肢の行の中身。無ければ ""）にする。"""
    if not isinstance(e, dict):
        raise ChangeError(f"confirm の要素が object でない: {e!r}")
    ref = _str(e, "ref")
    if e.get("kind") not in KINDS:
        raise ChangeError(f"confirm の kind が不正: {e.get('kind')!r}")
    facts = _str(e, "facts", required=False) or ""
    q = with_tag(strip_tag(_str(e, "question")) + (f"（{facts}）" if facts else ""), e["kind"], ref)
    opts = []
    options = e.get("options") or []
    if not isinstance(options, list) or not all(isinstance(o, dict) for o in options):
        raise ChangeError(f"confirm の options が object の配列でない: {options!r}")
    for o in options:
        label = _str(o, "label")
        text = _str(o, "text")
        opts.append(f"{label} {text}" + (RECOMMENDED if o.get("recommended") else ""))
    return q, " / ".join(opts)


def _render_confirm(entries: list, held: "list[dict]" = ()) -> "list[str]":
    """entries を3行の書式で書き、held（keep_answered のブロック）を回答欄ごとそのまま番号だけ振り直して後ろに足す。"""
    out = []
    for n, e in enumerate(entries, 1):
        q, opts = _render_entry(e)
        out += [f"{n}. {q}", *([f"   {opts}"] if opts else []), "   回答:"]
    for n, b in enumerate(held, len(entries) + 1):
        out += [_NUMBER.sub(f"{n}. ", b["lines"][0], count=1), *b["lines"][1:]]
    return out


def apply_changes(
    doc: Doc, changes: dict, origins: Callable[[str], str], today: str, records: "list[dict]" = (),
    effects: "Effects | None" = None, asked_at: "int | None" = None,
    retitle_origins: "Callable[[str], str] | None" = None,
) -> "tuple[Doc, list[str]]":
    """変更案を適用した新しい Doc とコミット本文の行を返す（doc は変更しない）。

    存在しない・複数に当たる ref への op はその op だけ飛ばし `skip: ...` を本文に残す。
    records（判断記録。未記録の戻しも含めて渡す）に従い、人が消した key の add/attach、
    人が戻した移動先への move、回答済みの (ref, kind) の確認待ちも飛ばす（行の系譜で見る。conflict は、回答より後に
    同じ行の意図が記録されていれば回答済みにしない）。asked_at は今の確認待ちを書いたときの判断記録の件数で、
    それ以降に意図が記録された行の conflict は、回答欄が埋まっていても回答済みにしない（None なら見ない）。
    source ai では、ユーザー指示で消えた ref（decisions.deleted_refs。今の台帳にある ref は除く。
    後片付けは題の前方一致）の add/attach も飛ばす。
    source user（ユーザー指示）は例外: 戻し・却下の記録に縛られず、完了から戻せ、edit_title / delete / note を
    使える。各 op に intent が必須で、op を1つでも飛ばすなら全体を ChangeError にする（承認された変更を欠かさない）。
    source ai も edit_title を使えるが、retitle_origins（省けば origins）が "ai" の行（この実行で足した行を含む）だけ。
    人の行・完了の行・後片付けの行・key の無い行の題の重なりになる edit_title は飛ばす。
    source ai の op に by_answer（{"ref", "kind"}）を付けると、この実行で読む確認待ちの、その (ref, kind) のブロックの
    回答に基づく op になる。回答が無い（confirm の無い実行・空欄・keep_answered・古い conflict・同じタグが複数）なら
    `skip: no answer`。行を指す op は、実行前の台帳で in_answer_scope に当たった行だけを対象にでき（それ以外は
    `skip: out of answer scope`）、その行には人の行でも delete・edit_title・完了からの move・pin を越える move ができる。
    effects を渡すと、source user と by_answer の意図、validate の免除対象、todo-pending.json の中身をそこに集める。
    変更案の形が不正なら ChangeError。人のタイトル保護などの結果の検証は validate が行う。
    """
    if not isinstance(changes, dict):
        raise ChangeError("変更案が object でない")
    source = changes.get("source")
    if source not in SOURCES:
        raise ChangeError(f"source が不正: {source!r}")
    user = source == "user"
    ops = changes.get("ops", [])
    if not isinstance(ops, list):
        raise ChangeError("ops が配列でない")
    if user and ("confirm" in changes or "answered" in changes):
        # 確認待ちの基準は ai/sync のコミットから取るので、user が書き換えると以後の ai 実行が止まる
        raise ChangeError("user は確認待ちを書き換えられない")
    keep = kept_answers(changes)
    if source != "ai" and any(isinstance(op, dict) and "by_answer" in op for op in ops):
        raise ChangeError(f"by_answer は ai だけが使える: {source}")
    fx = effects if effects is not None else Effects()
    retitle_origins = retitle_origins or origins
    doc = copy.deepcopy(doc)
    body: "list[str]" = []
    fresh: "list[Item]" = []
    reopened: "list[Item]" = []

    # 回答で触ってよい行は op を当てる前に決める。先の attach 等で key・題を変えた行を後から名指しさせないため
    answer_blocks: "dict[tuple[str, str], tuple[dict, list[tuple[Item, Item]]]]" = {}
    if source == "ai" and "confirm" in changes and any(isinstance(op, dict) and "by_answer" in op for op in ops):
        tagged = [(parse_tag(b["question"]), b) for b in parse_confirm(doc.confirm)]
        seen = Counter((ref, kind) for (kind, ref), _ in tagged)
        for (kind, ref), b in tagged:
            if (ref is None or not b["回答"].strip() or (ref, kind) in keep or seen[(ref, kind)] > 1
                    or stale_answer(records, ref, kind, asked_at)):
                continue
            answer_blocks[(ref, kind)] = (b, [(it, copy.deepcopy(it)) for s in TASK_SECTIONS
                                              for it in doc.sections[s] if in_answer_scope(it, b)])

    current = [-1]

    def skip(msg: str) -> None:
        if user:
            raise ChangeError(f"user の変更を適用できない: {msg}")
        body.append(f"skip: {msg}")
        fx.skipped.append(current[0])

    present = {it.ref for s in TASK_SECTIONS for it in doc.sections[s]}
    deleted = set(decisions.deleted_refs(records, present)) if source == "ai" else set()
    gone_cleanup = sorted(r for r in deleted | {x.get("ref") for x in records if x.get("kind") == "reject_add"}
                          if isinstance(r, str) and r.startswith("title:" + CLEANUP_PREFIX) and r not in present)

    def deleted_by_user(ref: str, title: "str | None" = None) -> "str | None":
        """source ai が足し直そうとしている、ユーザーが消した ref（無ければ None）。"""
        if ref in deleted:
            return ref
        # 後片付けは日付で題が変わるので、一度消されたら別の日の行も足さない
        if source == "ai" and title is not None and title.startswith(CLEANUP_PREFIX) and gone_cleanup:
            return gone_cleanup[0]
        return None

    def locate(ref: str) -> "tuple[str, int] | None":
        hits = _find(doc, ref)
        if len(hits) == 1:
            return hits[0]
        skip(f"{'unknown' if not hits else 'ambiguous'} ref {ref}")
        return None

    for current[0], op in enumerate(ops):
        if not isinstance(op, dict):
            raise ChangeError(f"op が object でない: {op!r}")
        kind = op.get("op")
        intent = _str(op, "intent", required=user)
        if user and not intent.strip():
            raise ChangeError(f"{kind}: intent が空白だけ")
        ba = op.get("by_answer")
        if ba is not None:
            if not (isinstance(ba, dict) and isinstance(ba.get("ref"), str) and ba["ref"] and ba.get("kind") in KINDS):
                raise ChangeError(f"{kind}: by_answer が {{ref, kind}} でない: {ba!r}")
            if kind not in ANSWER_OPS:
                raise ChangeError(f"{kind} に by_answer は付けられない")
            if ba.get("answer") is not None and not isinstance(ba["answer"], str):
                raise ChangeError(f"{kind}: by_answer の answer が文字列でない: {ba!r}")
        if kind in USER_OPS and not user and not (source == "ai" and (kind in AI_OPS or ba is not None)):
            raise ChangeError(f"{kind} は user だけが使える")
        answer = None
        if ba is not None:
            answer = answer_blocks.get((ba["ref"], ba["kind"]))
            if answer is None:
                skip(f"no answer {ba['ref']}")
                continue
            # /todo が読んだ後に人が回答を書き換えていたら、古い回答で行を触らず、新しい回答を次の実行に残す
            if (ba.get("answer") or "").strip() != answer[0]["回答"].strip():
                fx.held_answers.add((ba["ref"], ba["kind"]))
                skip(f"answer changed {ba['ref']}")
                continue

        def scoped(it: Item) -> "Item | None":
            """by_answer の op が触ってよい行なら実行前の状態を返す。by_answer の無い op は常に None。"""
            return next((snap for x, snap in answer[1] if x is it), None) if answer else None

        def out_of_scope(it: Item, ref: str) -> bool:
            if answer is not None and scoped(it) is None:
                skip(f"out of answer scope {ref}")
                return True
            return False

        refs_out: "list[tuple[str, str]]" = []
        if kind == "add":
            section = op.get("section")
            if section not in OPEN_SECTIONS:
                raise ChangeError(f"add: section が不正: {section!r}")
            title = _str(op, "title")
            key = _key(op) if op.get("key") is not None else None
            nxt = _str(op, "next", required=False)
            it = Item(title, key, op.get("url") if key else None, nxt or None)
            if key and not user and decisions.is_rejected(records, key):
                skip(f"rejected {key}")
                continue
            gone = deleted_by_user(it.ref, title)
            if gone:
                skip(f"intent_deleted {gone}")
                continue
            # key の無い行は is_task の「追加」の回答で足すので、同じ題の完了行があっても新しい作業として足す
            if any(s in (TASK_SECTIONS if key else OPEN_SECTIONS) for s, _ in _find(doc, it.ref)):
                skip(f"duplicate {it.ref}")
                continue
            doc.sections[section].append(it)
            fresh.append(it)
            body.append(_note(op, f"add {it.ref} → {section}", it.url))
            refs_out.append((it.ref, it.ref))
        elif kind == "move":
            ref, to = _str(op, "ref"), op.get("to")
            if to not in TASK_SECTIONS:
                raise ChangeError(f"move: to が不正: {to!r}")
            loc = locate(ref)
            if loc is None or out_of_scope(doc.sections[loc[0]][loc[1]], ref):
                continue
            refs_out.append((ref, ref))
            if loc[0] != to:
                # 回答は戻しより新しい人の判断なので、名指しされた行では pin より回答に従う
                if not user and answer is None and decisions.is_pinned(records, ref, to):
                    skip(f"pinned {ref}")
                    continue
                if loc[0] == "完了" and not user and answer is None:
                    raise ChangeError(f"{source} は完了から戻せない: {ref}")
                it = doc.sections[loc[0]].pop(loc[1])
                if loc[0] == "完了":
                    reopened.append(it)
                    if answer is not None:
                        fx.answer_reopened.append(scoped(it))
                if to == "完了":
                    it.done, it.done_date = True, today
                    doc.sections[to].insert(0, it)
                else:
                    it.done, it.done_date = False, None
                    doc.sections[to].append(it)
                body.append(_note(op, f"move {ref} → {to}", op.get("url") or it.url))
        elif kind == "set_next":
            ref = _str(op, "ref")
            nxt = _str(op, "next", required=False)
            loc = locate(ref)
            if loc is None or out_of_scope(doc.sections[loc[0]][loc[1]], ref):
                continue
            it = doc.sections[loc[0]][loc[1]]
            it.next = nxt or None
            body.append(_note(op, f"set_next {ref}", op.get("url") or it.url))
            refs_out.append((ref, ref))
        elif kind == "attach":
            ref = _str(op, "ref")
            key = _key(op)
            nxt = _str(op, "next", required=False)
            loc = locate(ref)
            if loc is None or out_of_scope(doc.sections[loc[0]][loc[1]], ref):
                continue
            it = doc.sections[loc[0]][loc[1]]
            if it.key:
                skip(f"already linked {ref}")
                continue
            if not user and decisions.is_rejected(records, key):
                skip(f"rejected {key}")
                continue
            if deleted_by_user(key):
                skip(f"intent_deleted {key}")
                continue
            if _find(doc, key):
                skip(f"duplicate {key}")
                continue
            if nxt and it.next:
                skip(f"next already set {ref}")
                continue
            fx.aliases.append((key, ref))
            it.key, it.url = key, op["url"]
            if nxt:
                it.next = nxt
            body.append(_note(op, f"attach {ref} ← {key}", it.url))
            refs_out.append((it.ref, ref))
        elif kind == "edit_title":
            ref, title = _str(op, "ref"), _str(op, "title")
            loc = locate(ref)
            if loc is None or out_of_scope(doc.sections[loc[0]][loc[1]], ref):
                continue
            it = doc.sections[loc[0]][loc[1]]
            if title != it.title:
                if not user:
                    # validate は題の数で比べるので、人の行の改名と同じ題の add の組を見逃す。ここで行ごとに飛ばす
                    if answer is None and all(it is not f for f in fresh) and retitle_origins(it.title) != "ai":
                        skip(f"human title {ref}")
                        continue
                    if answer is None and loc[0] == "完了":
                        skip(f"done {ref}")
                        continue
                    if it.title.startswith(CLEANUP_PREFIX) or title.startswith(CLEANUP_PREFIX):
                        skip(f"cleanup {ref}")
                        continue
                if not it.key and _find(doc, "title:" + title):
                    if not user:
                        skip(f"duplicate title {ref}")
                        continue
                    raise ChangeError(f"edit_title: 同じ題の key の無い行が既にあり ref が重なる: {title!r}")
                if not user:
                    if not it.key:
                        fx.aliases.append(("title:" + title, ref))
                    if answer is not None:
                        fx.answer_retitled.append(scoped(it))
                elif all(it is not f for f in fresh):
                    fx.retitled.append(copy.deepcopy(it))
                it.title = title
                body.append(_note(op, f"edit_title {ref} → {title}", it.url))
            refs_out.append((it.ref, ref))
        elif kind == "delete":
            ref = _str(op, "ref")
            loc = locate(ref)
            if loc is None or out_of_scope(doc.sections[loc[0]][loc[1]], ref):
                continue
            it = doc.sections[loc[0]].pop(loc[1])
            if answer is not None:
                fx.answer_deleted.append(scoped(it))
            elif all(it is not f for f in fresh):
                fx.deleted.append(it)
            body.append(_note(op, f"delete {ref}", it.url))
            refs_out.append((ref, ref))
        elif kind == "note":
            ref = _str(op, "ref")
            # 台帳に無い key には、足される前に意図を残せる。key の無い行は題だけが手がかりなので実在を求める
            if not todo_md.is_key(ref) and locate(ref) is None:
                continue
            body.append(f"note {ref}")
            refs_out.append((ref, ref))
        elif kind == "order":
            section, refs = op.get("section"), op.get("refs")
            if section not in TASK_SECTIONS or not isinstance(refs, list):
                raise ChangeError(f"order: section/refs が不正: {op!r}")
            items = doc.sections[section]
            first: "list[Item]" = []
            for ref in refs:
                hits = [i for i, it in enumerate(items) if it.ref == ref]
                if len(hits) != 1:
                    skip(f"{'unknown' if not hits else 'ambiguous'} ref {ref}")
                elif items[hits[0]] not in first:
                    first.append(items[hits[0]])
                    refs_out.append((ref, ref))
            rest = [it for it in items if all(it is not f for f in first)]
            new = first + rest
            if any(a is not b for a, b in zip(new, items)):
                doc.sections[section] = new
                body.append(_note(op, f"order {section}", None))
        else:
            raise ChangeError(f"未知の op: {kind!r}")
        if user:
            for now, prev in refs_out:
                fx.intents.append({"ref": now, "value": intent, "op": kind,
                                   **({"prev_ref": prev} if prev != now else {})})
        elif answer is not None:
            for now, prev in refs_out:
                fx.answer_intents.append({"ref": now, "value": _answer_value(answer[0]), "op": kind,
                                          "by_answer": {"ref": ba["ref"], "kind": ba["kind"]},
                                          **({"title": op["title"]} if kind == "edit_title" else {}),
                                          **({"prev_ref": prev} if prev != now else {})})
    # 後の op で改名・再移動されうるので、最後の状態で取る
    for it in reopened:
        sec = next((s for s in OPEN_SECTIONS if any(x is it for x in doc.sections[s])), None)
        if sec:
            fx.reopened.append((it.ref, sec))

    if "confirm" in changes:
        entries = changes["confirm"]
        answered = changes.get("answered")
        if not isinstance(entries, list) or not isinstance(answered, (list, type(None))):
            raise ChangeError("confirm/answered が配列でない")
        old_blocks = parse_confirm(doc.confirm)
        answered_tags = Counter((ref, kind) for ref, kind, _ in answer_records(old_blocks))
        for k in keep:
            if answered_tags[k] != 1:
                raise ChangeError(f"keep_answered が回答のある確認待ちのブロック1つに当たらない: {k!r}")
        if any(isinstance(e, dict) and (e.get("ref"), e.get("kind")) in keep for e in entries):
            raise ChangeError("keep_answered のブロックを confirm にも書いている")
        holding = keep | fx.held_answers
        held = [b for b in old_blocks if b["回答"].strip() and tuple(reversed(parse_tag(b["question"]))) in holding]
        done_now = {(ref, kind) for ref, kind, _ in consumed_answers(old_blocks, holding)
                    if not stale_answer(records, ref, kind, asked_at)}
        if answered is not None:
            _check_answers(old_blocks, answered)

        def done(e: dict) -> bool:
            ref, kind = e.get("ref"), e.get("kind")
            if not isinstance(ref, str) or kind not in KINDS:
                return False
            refs = decisions.lineage_refs(records, ref)
            return any((r, kind) in done_now for r in refs) or decisions.already_answered(records, ref, kind) is not None

        kept = []
        for e in entries:
            if isinstance(e, dict) and (e.get("ref"), e.get("kind")) in fx.held_answers:
                body.append(f"skip: answer changed {e['kind']} {e['ref']}")
            elif isinstance(e, dict) and done(e):
                body.append(f"skip: answered {e['kind']} {e['ref']}")
            else:
                kept.append(e)
        fx.pending = []
        for e in kept:
            if e.get("on_answer") is None:
                continue
            line, opts = _render_entry(e)
            if _bad_on_answer(e):
                body.append(f"skip: bad on_answer {e['ref']}")
                continue
            fx.pending.append({"ref": e["ref"], "kind": e["kind"], "line": line, "options": opts,
                               "on_answer": e["on_answer"]})
        new_confirm = _render_confirm(kept, held)
        if new_confirm != doc.confirm:
            doc.confirm = new_confirm
            body.append(f"confirm: {len(kept) + len(held)} 件")
            # decisions に記録されるまでは、コミット本文が人の回答の唯一の控えになる
            for b in old_blocks:
                if b["回答"].strip() and all(b is not h for h in held):
                    body.append(f"answer: {b['lines'][0]}")
                    body.extend(b["lines"][1:])
    return doc, body


def origin_fn(repo: Path, name: str, records: "list[dict]") -> Callable[[str], str]:
    """origin_of に、確認待ちの回答で人の行に付けた題（todo(ai) のコミットで入る）を "human" と見なす判定を足したもの。"""
    human = decisions.answer_titles(records)
    return lambda t: "human" if t in human else origin_of(repo, name, t)


def retitle_fn(repo: Path, name: str, records: "list[dict]") -> Callable[[str], str]:
    human = decisions.answer_titles(records)
    return lambda t: "human" if t in human else _retitle_origin(repo, name, t)


def _retitle_origin(repo: Path, name: str, title: str) -> str:
    """AI が題を変えてよい行か。出現数でも、題をちょうどその文字列にしたコミットでも ai のときだけ "ai"。"""
    if origin_of(repo, name, title) != "ai":
        return "human"
    return title_written_by(repo, name, title)


def stale_answer(records: "list[dict]", ref: str, kind: str, asked_at: "int | None") -> bool:
    """確認待ちに今ある conflict の回答が、問いを書いた後に記録された同じ行の意図で古くなったか。"""
    return kind == "conflict" and asked_at is not None and decisions.newest_intent_pos(records, ref) >= asked_at


def _ident(it: Item) -> str:
    return it.title or it.key or ""


def _items(doc: Doc, sections=TASK_SECTIONS) -> "list[Item]":
    return [it for s in sections for it in doc.sections[s] if _ident(it)]


def validate(before: Doc, after: Doc, origins: Callable[[str], str], source: str,
             exempt: "Effects | None" = None) -> "list[str]":
    """適用前後を比べ、人の行・判断を壊す変更なら違反メッセージを返す（空なら OK）。

    source user のときだけ、exempt（apply_changes の effects）が名指しした行の消失・題の変更と、
    完了から戻すことを許す。source ai では exempt の answer_*（by_answer の op が触った行）だけを同じように許す。
    sync では exempt を無視する。
    """
    ex = exempt if source == "user" and exempt is not None else Effects()
    ans = exempt if source == "ai" and exempt is not None else Effects()
    gone = [it for it in ex.deleted + ans.answer_deleted if _ident(it)]
    retitled = ex.retitled + [it for it in ans.answer_retitled if all(it is not g for g in gone)]
    errs = []
    nb, na = len(_items(before)) - len(gone), len(_items(after))
    if na < nb:
        errs.append(f"タスク行が減る: {nb} → {na}")
    keys_b = Counter(it.key for it in _items(before) if it.key) - Counter(it.key for it in gone if it.key)
    keys_a = Counter(it.key for it in _items(after) if it.key)
    for k in keys_b - keys_a:
        errs.append(f"リンク付きの行が消える: {k}")
    titles_a = Counter(it.title for it in _items(after))
    titles_ex = Counter(it.title for it in gone + retitled if it.title)
    for t, n in Counter(it.title for it in _items(before) if it.title).items():
        if titles_a[t] < n - titles_ex[t] and origins(t) == "human":
            errs.append(f"人が書いたタイトルが変わる: {t!r}")
    if source != "user":
        done_b, done_a = _items(before, ["完了"]), _items(after, ["完了"])
        back = ans.answer_reopened
        pairs_a = Counter((it.title, it.key) for it in done_a + back if it.key)
        for (t, k), n in Counter((it.title, it.key) for it in done_b if it.key).items():
            if pairs_a[(t, k)] < n:
                errs.append(f"{source} は完了から戻せない: {k} {t!r}")
        # key の無い完了行は attach で key が付きうるので、タイトルだけで数える
        titles_done_a = Counter(it.title for it in done_a) + Counter(it.title for it in back if not it.key)
        for t, n in Counter(it.title for it in done_b if not it.key).items():
            if titles_done_a[t] < n:
                errs.append(f"{source} は完了から戻せない: {t!r}")
    return errs


def roundtrip_errors(doc: Doc) -> "list[str]":
    """render した結果を parse し直して同じ Doc に戻らなければ、書くと意味が変わる。"""
    try:
        back = todo_md.parse(todo_md.render(doc))
    except ValueError as e:
        return [f"書き出せない: {e}"]
    errs = []
    if back.preamble != doc.preamble or back.confirm != doc.confirm:
        errs.append("確認待ち・前置きが書き出し後に変わる")
    fields = lambda it: (it.title, it.key, it.url, it.next, it.done, it.done_date)
    for s in TASK_SECTIONS:
        if [fields(i) for i in back.sections[s]] != [fields(i) for i in doc.sections[s]]:
            errs.append(f"{s} の行が書き出し後に別の意味になる（タイトルに — next: や ]( 等）")
    return errs


def split_archive(doc: Doc, today: str) -> "tuple[Doc, dict[str, list[Item]]]":
    """完了日から 30 日を超えた完了行を、完了月ごとに取り出す。日付が無い・読めない行は残す。"""
    t = datetime.date.fromisoformat(today)
    doc = copy.deepcopy(doc)
    archived: "dict[str, list[Item]]" = {}
    kept = []
    for it in doc.sections["完了"]:
        try:
            d = datetime.date.fromisoformat(it.done_date) if it.done_date else None
        except ValueError:
            d = None
        if it.done and d and (t - d).days > ARCHIVE_DAYS:
            archived.setdefault(d.strftime("%Y-%m"), []).append(it)
        else:
            kept.append(it)
    doc.sections["完了"] = kept
    return doc, archived


def nvim_editing(todo_dir: Path) -> bool:
    """`.todo.lock` の PID が生きていれば True。死んだ PID・読めない中身は古いロックとして消す。"""
    lock = todo_dir / ".todo.lock"
    try:
        content = lock.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return False
    try:
        pid = int(content)
        if pid > 0:
            os.kill(pid, 0)
            return True
    except PermissionError:
        return True
    except (ValueError, OverflowError, OSError):
        pass
    try:
        lock.unlink()
    except FileNotFoundError:
        pass
    return False


class _Changed(Exception):
    """読んだ後に todo.md が書き換えられた。"""


def _git(repo: Path, *args: str, retry: bool = False) -> str:
    """retry=True なら index.lock の競合（nvim の git 連携など）を、ロックを消して最大10回まで再試行する。"""
    for n in range(GIT_RETRIES):
        r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8")
        if r.returncode == 0:
            return r.stdout
        if not retry or "index.lock" not in r.stderr or n == GIT_RETRIES - 1:
            raise RuntimeError(f"git {' '.join(args)} failed: {r.stderr.strip()}")
        git_dir = Path(_git(repo, "rev-parse", "--absolute-git-dir").strip())
        (git_dir / "index.lock").unlink(missing_ok=True)
        time.sleep(1)
    raise AssertionError("unreachable")


def _commit_human_edits(repo: Path, name: str) -> None:
    # nvim は保存ごとに書きコミットは閉じるときだけなので、未コミット分を AI のコミットに混ぜると出どころが ai になる
    if not _git(repo, "status", "--porcelain", "--", name).strip():
        return
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    _git(repo, "add", "--", name, retry=True)
    _git(repo, "commit", "-q", "-m", f"todo: {stamp}", "--", name, retry=True)


def _confirms_at(repo: Path, revs: "list[str]") -> "list[list[str] | None]":
    """各 rev（`<commit>:<path>` の形）の確認待ち。無い・読めないものは None。git は1回だけ起動する。"""
    r = subprocess.run(["git", "-C", str(repo), "cat-file", "--batch"], input="".join(v + "\n" for v in revs).encode(),
                       capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"git cat-file failed: {r.stderr.decode(errors='replace').strip()}")
    data, pos, out = r.stdout, 0, []
    for _ in revs:
        end = data.index(b"\n", pos)
        header = data[pos:end].split()
        pos = end + 1
        if len(header) != 3 or header[1] != b"blob":
            out.append(None)
            continue
        size = int(header[2])
        blob, pos = data[pos:pos + size], pos + size + 1
        try:
            out.append(todo_md.parse(blob.decode("utf-8")).confirm)
        except ValueError:
            out.append(None)
    return out


CONFIRM_SCAN_CHUNK = 50


def _last_confirm_commit(repo: Path, name: str) -> "tuple[str | None, list[str]]":
    """確認待ちを実際に変えた最後の ai/sync コミットと、その確認待ち。件数で打ち切らない。"""
    # 確認待ちを変えなかった AI/同期コミットは人の追記をそのまま運ぶので、基準にすると追記を apply の内容と取り違える
    commits = _git(repo, "log", "--format=%H", "-E", r"--grep=^todo\((ai|sync)\): ", "--", name).split()
    for i in range(0, len(commits), CONFIRM_SCAN_CHUNK):
        chunk = commits[i:i + CONFIRM_SCAN_CHUNK]
        got = _confirms_at(repo, [r for h in chunk for r in (f"{h}:{name}", f"{h}^:{name}")])
        for j in range(len(chunk)):
            mine, parent = got[2 * j], got[2 * j + 1]
            if mine is not None and mine != parent:
                return chunk[j], mine
    return None, []


def _last_written_confirm(repo: Path, name: str) -> "list[str]":
    return _last_confirm_commit(repo, name)[1]


def confirm_asked_at(repo: Path, name: str, dpath: Path) -> "int | None":
    """今の確認待ちを書いたコミット時点の判断記録の件数。判断記録が repo の外・確認待ちを書いたことが無いなら None。"""
    if dpath.parent != repo:
        return None
    commit, _ = _last_confirm_commit(repo, name)
    if commit is None:
        return None
    r = subprocess.run(["git", "-C", str(repo), "show", f"{commit}:{dpath.name}"], capture_output=True)
    if r.returncode != 0:
        return 0
    return len(decisions.parse_text(r.stdout.decode("utf-8", errors="replace")))


def _write_atomic(path: Path, text: str, expect: "str | None" = None) -> None:
    """expect を渡すと、置き換える直前に中身が expect のままか確かめ、違えば書かずに _Changed。"""
    tmp = path.with_name(f".{path.name}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    if path.exists():
        shutil.copymode(path, tmp)
    if expect is not None and path.read_text(encoding="utf-8") != expect:
        tmp.unlink()
        raise _Changed(str(path))
    os.replace(tmp, path)


def _restore(originals: "dict[Path, str | None]") -> None:
    for p, old in originals.items():
        if old is None:
            p.unlink(missing_ok=True)
        else:
            _write_atomic(p, old)


def summarize(body: "list[str]") -> str:
    counts = Counter(l.split(" ", 1)[0].rstrip(":") for l in body)
    # 確認待ちは本文に「confirm: N 件」の1行だけなので、行数ではなく N を出す
    m = next((re.match(r"confirm: (\d+) 件\Z", l) for l in body if l.startswith("confirm: ")), None)
    parts = []
    for k, label in OP_LABELS.items():
        if k == "confirm" and m:
            parts.append(f"{label}{m.group(1)}")
        elif counts[k] and k != "confirm":
            parts.append(f"{label}{counts[k]}")
    return " ".join(parts)


def run(changes_path: Path, todo: Path, today: str, decisions_path: "Path | None" = None,
        allow_user: bool = False) -> int:
    try:
        changes = json.loads(changes_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"apply: 変更案を読めない: {e}", file=sys.stderr)
        return 2
    source = changes.get("source") if isinstance(changes, dict) else None
    # source は変更案の自己申告なので、無人の /todo が user を名乗っても保護が外れないよう呼び出し側で絞る
    if source == "user" and os.environ.get("TODO_AI_DENY_USER", "") not in ("", "0"):
        print("apply: 未適用: TODO_AI_DENY_USER が立っているので source user は受け付けない", file=sys.stderr)
        return 2
    if source == "user" and not allow_user:
        print("apply: 未適用: source user は --allow-user を付けたときだけ受け付ける", file=sys.stderr)
        return 2
    repo, name = todo.parent, todo.name
    dpath = (decisions_path or repo / decisions.DECISIONS_NAME).expanduser().absolute()
    if not todo.is_file():
        print(f"apply: todo.md が無い: {todo}", file=sys.stderr)
        return 1
    _git(repo, "rev-parse", "--is-inside-work-tree")

    with open(repo / ".todo.write.lock", "w") as wl:
        fcntl.flock(wl, fcntl.LOCK_EX)
        if nvim_editing(repo):
            print("apply: todo.md を編集中のためスキップ", file=sys.stderr)
            return 3
        _commit_human_edits(repo, name)
        text = todo.read_text(encoding="utf-8")
        try:
            before = todo_md.parse(text)
            old_records = decisions.load(dpath)
            new_records = decisions.detect_reverts(repo, name, old_records)
            blocks_now = (consumed_answers(parse_confirm(before.confirm), kept_answers(changes))
                          if "confirm" in changes else [])
            asked_at = (confirm_asked_at(repo, name, dpath)
                        if any(kind == "conflict" for _, kind, _ in blocks_now) else None)
            fx = Effects()
            origins = origin_fn(repo, name, old_records)
            after, body = apply_changes(before, changes, origins, today,
                                        old_records + new_records, effects=fx, asked_at=asked_at,
                                        retitle_origins=retitle_fn(repo, name, old_records))
        except ValueError as e:
            print(f"apply: 未適用: {e}", file=sys.stderr)
            return 2
        blocks_now = [r for r in blocks_now if (r[0], r[1]) not in fx.held_answers]
        errs = validate(before, after, origins, source, fx) + roundtrip_errors(after)
        if "confirm" in changes:
            errs += confirm_edit_errors(before.confirm, _last_written_confirm(repo, name))
        if errs:
            print("apply: 検証違反のため未適用:\n" + "\n".join(errs), file=sys.stderr)
            return 2
        ts = decisions.now_iso()
        # 回答より後に同じ行の意図があると conflict の回答が古くなる（decisions.superseded）ので、回答の前に置く
        for i in fx.answer_intents:
            new_records.append({"ts": ts, "ref": i["ref"], "kind": "intent", "value": i["value"], "by": "human",
                                "op": i["op"], "by_answer": i["by_answer"],
                                **({"title": i["title"]} if "title" in i else {}),
                                **({"prev_ref": i["prev_ref"]} if "prev_ref" in i else {})})
        for ref, kind, ans in blocks_now:
            new_records.append({"ts": ts, "ref": ref, "kind": kind, "value": ans, "by": "human",
                                **({"stale": True} if stale_answer(old_records, ref, kind, asked_at) else {})})
        for i in fx.intents:
            new_records.append({"ts": ts, "ref": i["ref"], "kind": "intent", "value": i["value"], "by": "human",
                                "op": i["op"], **({"prev_ref": i["prev_ref"]} if "prev_ref" in i else {})})
        for ref, sec in fx.reopened:
            new_records.append({"ts": ts, "ref": ref, "kind": "revert_move", "value": sec, "from": sec,
                                "to": "完了", "by": "human"})
        for key, prev in fx.aliases:
            new_records.append({"ts": ts, "ref": key, "kind": "alias", "prev_ref": prev, "by": "ai"})
        body += [f"record {r['kind']} {r['ref']}" for r in new_records]
        kept, archived = split_archive(after, today)
        kept = todo_md.regroup(kept, todo_md.load_groups(repo / todo_md.GROUPS_NAME))
        new_text = todo_md.render(kept)
        todo_changed = new_text != todo_md.render(before) or bool(archived)
        ppath = repo / PENDING_NAME
        old_pending = ppath.read_text(encoding="utf-8") if ppath.exists() else None
        pending_text = None
        if fx.pending is not None and (fx.pending or old_pending is not None):
            pending_text = json.dumps({"blocks": fx.pending}, ensure_ascii=False, indent=1) + "\n"
            if pending_text == old_pending:
                pending_text = None
            else:
                body.append(f"pending: {len(fx.pending)} 件")
        if not todo_changed and not new_records and pending_text is None:
            return 0
        if nvim_editing(repo) or todo.read_text(encoding="utf-8") != text:
            print("apply: todo.md を編集中のためスキップ", file=sys.stderr)
            return 3

        archive_dir = repo / "todo-archive"
        originals: "dict[Path, str | None]" = {}
        for month, items in sorted(archived.items()):
            p = archive_dir / f"{month}.md"
            originals[p] = p.read_text(encoding="utf-8") if p.exists() else None
            archive_dir.mkdir(exist_ok=True)
            _write_atomic(p, (originals[p] or "") + "".join(todo_md._render_item(it) + "\n" for it in items))
            body += [f"archive {it.ref} → todo-archive/{month}.md" for it in items]
        if new_records:
            originals[dpath] = dpath.read_text(encoding="utf-8") if dpath.exists() else None
            _write_atomic(dpath, (originals[dpath] or "") + decisions.render_lines(new_records))
        if pending_text is not None:
            originals[ppath] = old_pending
            _write_atomic(ppath, pending_text)
        if todo_changed:
            try:
                _write_atomic(todo, new_text, expect=text)
            except _Changed:
                _restore(originals)
                print("apply: 読んだ後に todo.md が変わったためスキップ", file=sys.stderr)
                return 3

        paths = ([name] if todo_changed else []) + [p for p in ("todo-archive", "todo-decisions.jsonl", PENDING_NAME)
                                                    if (repo / p).exists()]
        if dpath.exists() and dpath.parent == repo and dpath.name != "todo-decisions.jsonl":
            paths.append(dpath.name)
        subject = summarize(body) or ("判断の記録" if new_records else "回答の反映案")
        try:
            _git(repo, "add", "--", *paths, retry=True)
            _git(repo, "commit", "-q", "-m", f"todo({source}): {subject}", "-m", "\n".join(body),
                 "--", *paths, retry=True)
        except RuntimeError:
            # 未コミットのまま残すと次の人のコミットに AI の変更が混ざるので戻す。人が触った後なら触らない
            try:
                if todo_changed:
                    _write_atomic(todo, text, expect=new_text)
                _restore(originals)
            except _Changed:
                pass
            raise
    return 0


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"apply: {message}", file=sys.stderr)
        sys.exit(1)


def main(argv=None) -> int:
    p = _Parser(description="変更案 JSON を todo.md に適用する")
    p.add_argument("--changes", required=True, type=Path)
    p.add_argument("--todo", type=Path)
    p.add_argument("--decisions", type=Path, help="判断記録（既定は todo.md と同じディレクトリの todo-decisions.jsonl）")
    p.add_argument("--today", default=datetime.date.today().isoformat())
    p.add_argument("--allow-user", action="store_true", help="source user（/todo-edit のユーザー指示）を受け付ける")
    a = p.parse_args(argv)
    todo = a.todo or Path(os.environ.get("TODO_MD_PATH") or Path.home() / "memo" / "todo.md")
    try:
        datetime.date.fromisoformat(a.today)
        return run(a.changes, todo.expanduser().absolute(), a.today, a.decisions, a.allow_user)
    except Exception as e:
        print(f"apply: {type(e).__name__}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
