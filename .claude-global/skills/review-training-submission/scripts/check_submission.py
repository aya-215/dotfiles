#!/usr/bin/env python3
"""tamaki-ai-training の提出PRを、機械的に判定できる項目だけ検査して Markdown 表で出す。

使い方:
    python3 check_submission.py --repo-dir <clone> --meta <meta.json> [--merge-commit <sha>]

meta.json（MCP の get_issue / get_pr の結果から作る）:
    {
      "number": 117,
      "head": "agent-phase0/claude-code-ops",
      "base": "main",
      "body": "<PR本文そのまま>",
      "labels": ["needs-review", "agent-phase0"],
      "issue": {"number": 98, "labels": ["agent-phase0"], "body": "<Issue本文>"}
    }

判定: PASS / FAIL / WARN（要目視）/ UNKNOWN（判定不能）/ N/A（該当なし）
副作用: clone に refs/review/head と refs/review/base を fetch する（作業ツリー・index は触らない）。
内容の良し悪しは判定しない。それは SKILL.md の手順で行う。
"""

import argparse
import json
import posixpath
import re
import subprocess
import sys

HEAD_REF = "refs/review/head"
BASE_REF = "refs/review/base"

TEMPLATE_SECTIONS = [
    "対象フェーズ",
    "提出物",
    "消化したチェックリスト項目",
    "自己評価",
    "詰まった点・聞きたいこと",
    "確認事項",
]

SECRET_PATTERNS = [
    (r"sk-ant-[A-Za-z0-9_-]{10,}", "Anthropic APIキー"),
    (r"sk-[A-Za-z0-9]{20,}", "OpenAI系APIキー"),
    (r"lsv2_[A-Za-z0-9_]{10,}", "LangSmith APIキー"),
    (r"gh[pousr]_[A-Za-z0-9]{20,}", "GitHubトークン"),
    (r"AKIA[0-9A-Z]{16}", "AWSアクセスキー"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "秘密鍵"),
    (r"client-key-data:|client-certificate-data:", "kubeconfig"),
    (r"(?i)(password|passwd|api[_-]?key|secret|token)\s*[:=]\s*['\"]?[A-Za-z0-9/+_-]{12,}", "認証情報らしき代入"),
]


def git(repo, *args, binary=False):
    out = subprocess.run(["git", "-C", repo, *args], capture_output=True, check=True)
    return out.stdout if binary else out.stdout.decode("utf-8", errors="replace")


def exists_at(repo, ref, path):
    return subprocess.run(
        ["git", "-C", repo, "cat-file", "-e", f"{ref}:{path}"], capture_output=True
    ).returncode == 0


def sections(body):
    body = body.replace("\r\n", "\n")
    result, current = {}, None
    for line in body.split("\n"):
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            current = m.group(1)
            result[current] = []
        elif current:
            result[current].append(line)
    return {k: "\n".join(v).strip() for k, v in result.items()}


def task_state(line):
    """チェックボックス行の状態を返す。'task: :' 形式は GitBucket 側の表記で意味が確定していない。"""
    if re.match(r"^\s*[-*]\s+\[[xX]\]", line):
        return "checked"
    if re.match(r"^\s*[-*]\s+\[ \]", line):
        return "unchecked"
    if re.match(r"^\s*[-*]\s+task:\s*:", line):
        return "unknown"
    return None


def task_text(line):
    return re.sub(r"^\s*[-*]\s+(\[[ xX]\]|task:\s*:)\s*", "", line).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-dir", required=True)
    ap.add_argument("--meta", required=True)
    ap.add_argument("--merge-commit", help="マージ済みPRを再検査するときのマージコミット（^1=base, ^2=head）")
    a = ap.parse_args()
    repo = a.repo_dir
    meta = json.load(open(a.meta, encoding="utf-8"))
    body = meta.get("body", "")
    head, base = meta["head"], meta.get("base", "main")
    rows = []

    def row(cid, item, verdict, evidence):
        rows.append((cid, item, verdict, evidence))

    global HEAD_REF, BASE_REF
    if a.merge_commit:
        HEAD_REF, BASE_REF = f"{a.merge_commit}^2", f"{a.merge_commit}^1"
    else:
        git(repo, "fetch", "-q", "origin", f"+refs/heads/{head}:{HEAD_REF}", f"+refs/heads/{base}:{BASE_REF}")
    mb = git(repo, "merge-base", BASE_REF, HEAD_REF).strip()
    status = git(repo, "diff", "--name-status", "--no-renames", mb, HEAD_REF).strip().splitlines()
    changes = [(s.split("\t")[0], s.split("\t")[1]) for s in status if s]
    added_lines = {}
    for _, path in changes:
        diff = git(repo, "diff", "-U0", mb, HEAD_REF, "--", path)
        added_lines[path] = [l[1:] for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")]

    # トラック・フェーズは Issue ラベル → ブランチ名の順に決める
    labels = meta.get("labels", [])
    issue = meta.get("issue") or {}
    track = phase = None
    for lb in issue.get("labels", []) + labels:
        m = re.fullmatch(r"(agent-)?phase(\d+)", lb)
        if m:
            track, phase = ("agent" if m.group(1) else "infra"), m.group(2)
            break
    bm = re.match(r"^(agent-)?phase(\d+)/", head)

    sec = sections(body)

    # F01 closes
    cm = re.search(r"(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#(\d+)", body)
    if cm and issue.get("number") and int(cm.group(3)) != int(issue["number"]):
        row("F01", "`closes #N` が対象Issueを指す", "FAIL", f"本文は #{cm.group(3)}、meta の Issue は #{issue['number']}")
    elif cm:
        row("F01", "`closes #N` が対象Issueを指す", "PASS", f"`{cm.group(0)}`")
    else:
        row("F01", "`closes #N` が対象Issueを指す", "FAIL", "本文に closes 系キーワードが無い")

    # F02 雛形の見出し
    missing = [s for s in TEMPLATE_SECTIONS if s not in sec]
    row("F02", "PR本文が雛形の見出しを網羅", "FAIL" if missing else "PASS",
        "欠落: " + ", ".join(missing) if missing else "6見出しあり")

    # F03 確認事項
    states = [task_state(l) for l in sec.get("確認事項", "").splitlines() if task_state(l)]
    if not states:
        row("F03", "確認事項3項目にチェック", "FAIL", "チェックボックスが見つからない")
    elif "unchecked" in states:
        row("F03", "確認事項3項目にチェック", "FAIL",
            f"未チェック {states.count('unchecked')}/{len(states)}（pr-checklist.md: 全部チェックが無いPRはレビューしない）")
    elif "unknown" in states:
        row("F03", "確認事項3項目にチェック", "UNKNOWN", "`* task: :` 形式でチェック状態を判別できない。画面で確認")
    else:
        row("F03", "確認事項3項目にチェック", "PASS" if len(states) >= 3 else "WARN", f"チェック済み {len(states)}件")

    # F04 自己評価
    se = sec.get("自己評価", "")
    stars = re.search(r"★[★☆]{2}", se)
    reason = re.sub(r"★[★☆]{2}", "", se).strip()
    reason_lines = [l for l in reason.splitlines() if l.strip()]
    if stars and len(reason_lines) >= 2:
        row("F04", "自己評価に★と理由", "PASS", f"{stars.group(0)}／理由 {len(reason_lines)}行")
    elif stars and reason:
        row("F04", "自己評価に★と理由", "WARN", f"{stars.group(0)}／理由 {len(reason_lines)}行（pr-checklist.md は2〜3行）")
    else:
        row("F04", "自己評価に★と理由", "FAIL", "★" + ("あり" if stars else "なし") + "・理由" + ("あり" if reason else "なし"))

    # F05 needs-review
    if not labels:
        row("F05", "PRに `needs-review` ラベル", "UNKNOWN", "meta に labels が無い（get_issue をPR番号で呼んで取得する）")
    else:
        row("F05", "PRに `needs-review` ラベル", "PASS" if "needs-review" in labels else "FAIL", ", ".join(labels))

    # F06 ブランチ名
    if not track:
        row("F06", "ブランチ名がトラック・フェーズと一致", "UNKNOWN", f"Issueラベルからフェーズを特定できない（head: `{head}`）")
    else:
        want = f"{'agent-' if track == 'agent' else ''}phase{phase}/"
        ok = bm and head.startswith(want)
        row("F06", "ブランチ名がトラック・フェーズと一致", "PASS" if ok else "FAIL", f"`{head}`（期待: `{want}<topic>`）")

    # F07 提出先
    subs = [p for st, p in changes if st != "D" and (p.startswith("submissions/") or p.startswith("docs/reports/"))]
    if not subs:
        row("F07", "提出物がトラック・フェーズの提出先にある", "FAIL", "submissions/ にも docs/reports/ にも追加が無い")
    elif track:
        phase_dirs = [d for d in git(repo, "ls-tree", "--name-only", BASE_REF, f"submissions/{track}/").split()
                      if re.fullmatch(rf"submissions/{track}/phase{phase}-[^/]+", d)]
        bad = [p for p in subs if not p.startswith("docs/reports/") and not any(p.startswith(d + "/") for d in phase_dirs)]
        row("F07", "提出物がトラック・フェーズの提出先にある", "FAIL" if bad else "PASS",
            ("場違い: " + ", ".join(bad)) if bad else ", ".join(f"`{p}`" for p in subs))
    else:
        row("F07", "提出物がトラック・フェーズの提出先にある", "UNKNOWN", ", ".join(subs))

    # F08 本文「提出物」と実ファイルの一致
    listed = set(re.findall(r"`([^`]+\.[A-Za-z0-9]+)`", sec.get("提出物", "")))
    if subs:
        diff_set = set(subs) ^ listed
        row("F08", "本文「提出物」と差分のファイルが一致", "WARN" if diff_set else "PASS",
            ("不一致: " + ", ".join(sorted(diff_set))) if diff_set else f"{len(subs)}件一致")
        if len(subs) > 1:
            row("F08b", "提出物1点＝PR1本", "WARN", f"提出ファイル {len(subs)}件。1つのIssueの提出物か目視")

    # F09 ファイル名・エンコーディング
    bad_name, bad_enc = [], []
    for st, p in changes:
        if st == "D":
            continue
        name = posixpath.basename(p)
        if st == "A" and name != "README.md" and not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*\.[a-z0-9]+", name):
            bad_name.append(p)
        raw = git(repo, "show", f"{HEAD_REF}:{p}", binary=True)
        if raw.startswith(b"\xef\xbb\xbf"):
            bad_enc.append(f"{p}（BOM付き）")
        else:
            try:
                raw.decode("utf-8")
            except UnicodeDecodeError:
                bad_enc.append(f"{p}（UTF-8でない）")
        if b"\r\n" in raw:
            bad_enc.append(f"{p}（CRLF）")
    row("F09", "追加ファイル名が kebab-case", "FAIL" if bad_name else "PASS", ", ".join(bad_name) or "OK")
    row("F10", "UTF-8・BOMなし・LF", "FAIL" if bad_enc else "PASS", ", ".join(bad_enc) or "OK")

    # F11 フェーズ README を消していない
    deleted = [p for st, p in changes if st == "D" and p.startswith("submissions/") and p.endswith("README.md")]
    row("F11", "フェーズの README.md を削除していない", "FAIL" if deleted else "PASS", ", ".join(deleted) or "OK")

    # F12〜F13 チェックリスト
    claimed = [task_text(l) for l in sec.get("消化したチェックリスト項目", "").splitlines() if task_state(l)]
    claimed_none = sec.get("消化したチェックリスト項目", "").strip() in ("なし", "特になし")
    cl_path = f"progress/{track}/checklist.md" if track else None
    if cl_path and cl_path in dict((p, s) for s, p in changes):
        newly = [l for l in added_lines.get(cl_path, []) if l.startswith("| [x]")]
        texts = [l.split("|")[2].strip() for l in newly]
        unmatched = [c for c in claimed if c not in texts]
        extra = [t for t in texts if t not in claimed]
        if unmatched:
            row("F12", "チェックリストの[x]と本文「消化した項目」が一致", "FAIL",
                "本文で主張したがチェックリストで[x]になっていない: " + " / ".join(unmatched))
        elif extra:
            # 運用変更（チェックリストを同じPRに含める）前の分をまとめて付けた可能性があるので目視に回す
            row("F12", "チェックリストの[x]と本文「消化した項目」が一致", "WARN",
                "本文に無い[x]が混在: " + " / ".join(extra))
        else:
            row("F12", "チェックリストの[x]と本文「消化した項目」が一致", "PASS", f"{len(texts)}件")
        broken, no_evidence, still_unmet = [], [], []
        for l in newly:
            cols = [c.strip() for c in l.split("|")]
            name, evidence = cols[2][:30], (cols[4] if len(cols) > 4 else "")
            if not evidence:
                no_evidence.append(name)
            elif re.search(r"未達|繰り越し", evidence):
                still_unmet.append(name)
            for u in re.findall(r"\]\(([^)\s]+)\)", evidence):
                if re.match(r"^[a-z]+://", u):
                    continue
                target = posixpath.normpath(posixpath.join(posixpath.dirname(cl_path), u.split("#")[0]))
                if not exists_at(repo, HEAD_REF, target):
                    broken.append(u)
        problems = list(filter(None, [
            ("根拠が「未達・繰り越し」のまま[x]: " + ", ".join(still_unmet)) if still_unmet else "",
            ("根拠欄が空: " + ", ".join(no_evidence)) if no_evidence else "",
            ("リンク切れ: " + ", ".join(broken)) if broken else ""]))
        row("F13", "[x]にした行の根拠が実在し矛盾しない", "FAIL" if problems else "PASS", "; ".join(problems) or "OK")
    elif claimed and not claimed_none:
        row("F12", "チェックリストの[x]と本文「消化した項目」が一致", "FAIL",
            f"本文で {len(claimed)}件を主張しているが `{cl_path or 'progress/<track>/checklist.md'}` が差分に無い（同じPRに含める運用）")
    else:
        row("F12", "チェックリストの[x]と本文「消化した項目」が一致", "PASS", "消化項目なし・チェックリスト差分なし")

    # F14 コミットメッセージ
    subjects = git(repo, "log", "--no-merges", "--format=%s", f"{mb}..{HEAD_REF}").splitlines()
    bad_sub = [s for s in subjects if not re.match(r"^(docs|fix): \S", s)]
    row("F14", "コミットが `docs:` / `fix:` 形式", "FAIL" if bad_sub else "PASS",
        " / ".join(bad_sub) or f"{len(subjects)}件OK")

    # F15 TODO(human)
    todo = [p for p, ls in added_lines.items() if any("TODO(human)" in l for l in ls)]
    row("F15", "`TODO(human)` の残存なし", "FAIL" if todo else "PASS", ", ".join(todo) or "OK")

    # F16 秘匿情報らしきパターン（追加行のみ）
    hits = []
    for p, ls in added_lines.items():
        for l in ls:
            for pat, label in SECRET_PATTERNS:
                if re.search(pat, l):
                    hits.append(f"{p}: {label}")
    row("F16", "追加行に秘匿情報らしきパターンなし", "WARN" if hits else "PASS",
        "; ".join(sorted(set(hits))) + "（誤検知か目視）" if hits else "OK")

    # F17 白紙再現テスト
    if "白紙再現テスト" in issue.get("body", ""):
        touched = "progress/agent/blank-page-tests.md" in [p for _, p in changes]
        row("F17", "白紙再現テストの記録を更新", "PASS" if touched else "WARN",
            "blank-page-tests.md 更新あり" if touched else "Issueに白紙再現テストの記載あり。記録の更新が差分に無い")
    else:
        row("F17", "白紙再現テストの記録を更新", "N/A", "Issueに白紙再現テストの記載なし")

    print(f"## 形式チェック（PR #{meta.get('number')} / {track or '?'} phase{phase or '?'}）\n")
    print("| ID | 項目 | 判定 | 根拠 |\n|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(str(x).replace("|", "\\|") for x in r) + " |")
    print("\n変更ファイル: " + ", ".join(f"{s} `{p}`" for s, p in changes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
