import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import apply
import context

CONTEXT = str(HERE / "context.py")
TODAY = "2026-11-10"


def doc(confirm="", yaru="", matsu="", done=""):
    return f"# TODO\n\n## 確認待ち\n{confirm}\n## やる\n{yaru}\n## 待ち\n{matsu}\n## 完了\n{done}"


class Repo:
    def __init__(self, d):
        self.dir = Path(d)
        self.todo = self.dir / "todo.md"
        self.git("init", "-q")

    def git(self, *args, env=None):
        return subprocess.run(
            ["git", "-C", str(self.dir), "-c", "user.name=t", "-c", "user.email=t@t", *args],
            check=True, capture_output=True, text=True, env=env,
        ).stdout

    def commit(self, text, msg, date=None):
        self.todo.write_text(text, encoding="utf-8")
        self.git("add", "todo.md")
        env = None
        if date:
            env = dict(os.environ, GIT_AUTHOR_DATE=f"{date}T10:00:00+09:00",
                       GIT_COMMITTER_DATE=f"{date}T10:00:00+09:00")
        self.git("commit", "-q", "-m", msg, env=env)


class OptionsTest(unittest.TestCase):
    def test_roundtrip_with_render_confirm(self):
        entries = [
            {"ref": "epc#1", "kind": "policy", "question": "相談する？", "facts": "710件",
             "options": [{"label": "A", "text": "相談する", "recommended": True},
                         {"label": "B", "text": "そのまま", "recommended": False}]},
            {"ref": "rc:x", "kind": "manual", "question": "やった？", "facts": "",
             "options": []},
        ]
        lines = apply._render_confirm(entries)
        blocks = context.confirm_blocks(lines)
        again = apply._render_confirm([{k: b[k] for k in ("ref", "kind", "question", "facts", "options")}
                                       for b in blocks])
        self.assertEqual(again, lines)
        self.assertEqual(lines[0], "1. 相談する？ [policy epc#1]")
        self.assertEqual((blocks[0]["question"], blocks[0]["ref"], blocks[0]["kind"]), ("相談する？", "epc#1", "policy"))
        self.assertEqual(blocks[0]["options"][0], {"label": "A", "text": "相談する", "recommended": True})
        self.assertEqual(blocks[1]["options"], [])

    def test_slash_inside_option_text_roundtrips(self):
        entries = [{"ref": "epc#1", "kind": "policy", "question": "q", "facts": "",
                    "options": [{"label": "A", "text": "x / y", "recommended": True},
                                {"label": "B", "text": "z", "recommended": False}]}]
        lines = apply._render_confirm(entries)
        opts = context.confirm_blocks(lines)[0]["options"]
        self.assertEqual(opts, entries[0]["options"])
        self.assertEqual(apply._render_confirm([{"ref": "epc#1", "kind": "policy", "question": "q", "facts": "",
                                                 "options": opts}]), lines)


class BuildTest(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.r = Repo(self._t.name)

    def build(self, records=None):
        dpath = self.r.dir / "todo-decisions.jsonl"
        if records is not None:
            dpath.write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in records), encoding="utf-8")
        return context.build(self.r.todo, dpath, TODAY)

    def item(self, ctx, ref):
        hits = [i for i in ctx["items"] if i["ref"] == ref]
        self.assertEqual(len(hits), 1, ctx["items"])
        return hits[0]

    def test_items_with_origin_added_date_age(self):
        self.r.commit(doc(yaru="- [ ] 手で書いた\n"), "todo: 2026-10-01 10:00", date="2026-10-01")
        self.r.commit(doc(yaru="- [ ] 手で書いた\n", matsu="- [ ] 返事待ち [rc:abc](https://rc/x?msg=abc) — next: 待つ\n"),
                      "todo(ai): add", date="2026-10-20")
        ctx = self.build()
        h = self.item(ctx, "title:手で書いた")
        self.assertEqual((h["section"], h["origin"], h["added_date"], h["age_days"], h["pinned_to"]),
                         ("やる", "human", "2026-10-01", 40, []))
        a = self.item(ctx, "rc:abc")
        self.assertEqual((a["section"], a["origin"], a["added_date"], a["age_days"], a["key"], a["next"]),
                         ("待ち", "ai", "2026-10-20", 21, "rc:abc", "待つ"))

    def test_uncommitted_line_has_null_date(self):
        self.r.commit(doc(yaru="- [ ] 古い\n"), "todo: base", date="2026-10-01")
        self.r.todo.write_text(doc(yaru="- [ ] 古い\n- [ ] 新しい\n"), encoding="utf-8")
        h = self.item(self.build(), "title:新しい")
        self.assertIsNone(h["added_date"])
        self.assertIsNone(h["age_days"])

    def test_key_is_the_date_needle_when_present(self):
        self.r.commit(doc(yaru="- [ ] 返信\n"), "todo: base", date="2026-10-01")
        self.r.commit(doc(yaru="- [ ] 返信\n- [ ] 返信 [rc:k1](https://rc/k1)\n"), "todo(ai): add", date="2026-11-01")
        h = self.item(self.build(), "rc:k1")
        self.assertEqual((h["added_date"], h["age_days"]), ("2026-11-01", 9))

    def test_archived_keys(self):
        self.r.commit(doc(), "todo: base")
        arc = self.r.dir / "todo-archive"
        arc.mkdir()
        (arc / "2026-09.md").write_text("- [x] 古い [epc#7](https://g/7) (done: 2026-09-01)\n- [x] 鍵なし (done: 2026-09-02)\n",
                                        encoding="utf-8")
        (arc / "2026-10.md").write_text("- [x] 返信 [rc:z9](https://rc/z9) (done: 2026-10-01)\nゴミ行\n", encoding="utf-8")
        self.assertEqual(self.build()["archived_keys"], ["epc#7", "rc:z9"])

    def test_no_archive_dir(self):
        self.r.commit(doc(), "todo: base")
        self.assertEqual(self.build()["archived_keys"], [])

    def test_empty_title_uses_key_for_date(self):
        self.r.commit(doc(yaru="- [ ] [epc#5](https://g/5)\n"), "todo(ai): add", date="2026-11-01")
        h = self.item(self.build(), "epc#5")
        self.assertEqual((h["added_date"], h["age_days"]), ("2026-11-01", 9))

    def test_done_item_and_pinned(self):
        self.r.commit(doc(done="- [x] 済 [epc#1](https://g/1) (done: 2026-11-02)\n"), "todo: base")
        ctx = self.build([{"ts": "t", "ref": "epc#1", "kind": "revert_move", "value": "やる", "by": "human"}])
        h = self.item(ctx, "epc#1")
        self.assertEqual((h["section"], h["done"], h["done_date"], h["pinned_to"]),
                         ("完了", True, "2026-11-02", ["待ち", "完了"]))

    def test_pinned_to_is_the_undone_destination(self):
        self.r.commit(doc(yaru="- [ ] 調査 [epc#1](https://g/1)\n"), "todo: base")
        ctx = self.build([{"ts": "t", "ref": "epc#1", "kind": "revert_move", "value": "やる",
                           "from": "やる", "to": "待ち", "by": "human"}])
        self.assertEqual(self.item(ctx, "epc#1")["pinned_to"], ["待ち"])

    def test_unrecorded_reverts_are_shown_but_not_written(self):
        a = "- [ ] 調査 [epc#1](https://g/1)\n"
        self.r.commit(doc(yaru=a), "todo: base")
        self.r.commit(doc(matsu=a), "todo(ai): 移動1")
        self.r.commit(doc(yaru=a), "todo: 戻した")
        self.r.commit(doc(yaru=a + "- [ ] 追加 [epc#9](https://g/9)\n"), "todo(ai): 追加1")
        self.r.commit(doc(yaru=a), "todo: 消した")
        ctx = self.build()
        self.assertEqual(self.item(ctx, "epc#1")["pinned_to"], ["待ち"])
        self.assertEqual(ctx["rejected_refs"], ["epc#9"])
        self.assertFalse((self.r.dir / "todo-decisions.jsonl").exists())

    def test_intents_on_items_and_intent_refs(self):
        self.r.commit(doc(yaru="- [ ] 残す [epc#1](https://g/1)\n- [ ] 手書き\n"), "todo(user): base")
        recs = [{"ts": f"t{i}", "ref": "epc#1", "kind": "intent", "value": f"v{i}", "by": "human"} for i in range(7)]
        recs.append({"ts": "t9", "ref": "title:新", "kind": "intent", "value": "改名後", "by": "human", "prev_ref": "title:旧"})
        recs.append({"ts": "t10", "ref": "epc#gone", "kind": "intent", "value": "消した", "by": "human"})
        ctx = self.build(recs)
        self.assertEqual([i["value"] for i in self.item(ctx, "epc#1")["intents"]], ["v6", "v5", "v4", "v3", "v2"])
        self.assertEqual(self.item(ctx, "epc#1")["intents"][0], {"ts": "t6", "value": "v6"})
        self.assertEqual(self.item(ctx, "title:手書き")["intents"], [])
        self.assertEqual(ctx["intent_refs"], ["epc#1", "epc#gone", "title:新", "title:旧"])

    def test_decision_lists(self):
        self.r.commit(doc(), "todo: base")
        ctx = self.build([
            {"ts": "t1", "ref": "title:x", "kind": "is_task", "value": "B", "by": "human"},
            {"ts": "t2", "ref": "epc#9", "kind": "reject_add", "value": "やる", "by": "human"},
            {"ts": "t3", "ref": "epc#8", "kind": "revert_move", "value": "やる", "by": "human"},
        ])
        self.assertEqual(ctx["answered_refs"], [{"ref": "title:x", "kind": "is_task", "value": "B", "ts": "t1"}])
        self.assertEqual(ctx["rejected_refs"], ["epc#9"])

    def test_answered_block_becomes_answered_now(self):
        conf = ("1. 相談する？ [policy epc#1]\n   事実: f\n   選択: A する（おすすめ） / B しない\n   回答:\n"
                "2. やった？ [manual rc:x]\n   事実: \n   選択: A はい\n   回答:\n")
        self.r.commit(doc(confirm=conf), "todo(ai): base")
        self.r.commit(doc(confirm=conf.replace("回答:\n2.", "回答:  B で\n2.")), "todo: 回答")
        ctx = self.build()
        self.assertEqual(ctx["confirm_errors"], [])
        self.assertEqual([(b["number"], b["ref"], b["kind"], b["answer"]) for b in ctx["confirm_blocks"]],
                         [(1, "epc#1", "policy", "B で"), (2, "rc:x", "manual", "")])
        self.assertEqual(ctx["confirm_blocks"][0]["question"], "相談する？")
        self.assertEqual(ctx["answered_now"], [{"ref": "epc#1", "kind": "policy", "answer": "B で"}])

    def test_free_text_in_confirm_is_error(self):
        self.r.commit(doc(confirm="メモ: あとで\n"), "todo: base")
        ctx = self.build()
        self.assertEqual(ctx["confirm_blocks"], [])
        self.assertEqual(len(ctx["confirm_errors"]), 1)
        self.assertIn("メモ", ctx["confirm_errors"][0])

    def test_human_edited_question_is_error(self):
        conf = "1. 相談する？ [policy epc#1]\n   事実: f\n   選択: A する\n   回答:\n"
        self.r.commit(doc(confirm=conf), "todo(ai): base")
        self.r.commit(doc(confirm=conf.replace("事実: f", "事実: f と追記")), "todo: 直した")
        ctx = self.build()
        self.assertEqual(len(ctx["confirm_errors"]), 1)
        self.assertIn("相談する", ctx["confirm_errors"][0])

    def test_untagged_block_is_error(self):
        conf = "1. 相談する？\n   事実: f\n   選択: A する\n   回答: A\n"
        self.r.commit(doc(confirm=conf), "todo(ai): base")
        ctx = self.build()
        self.assertEqual(ctx["answered_now"], [])
        self.assertEqual(len(ctx["confirm_errors"]), 1)
        self.assertIn("タグ", ctx["confirm_errors"][0])

    def test_unanswered_untagged_block_is_error_too(self):
        conf = "1. 相談する？\n   事実: f\n   選択: A する\n   回答:\n"
        self.r.commit(doc(confirm=conf), "todo(ai): base")
        ctx = self.build()
        self.assertEqual(len(ctx["confirm_errors"]), 1)
        self.assertIn("タグ", ctx["confirm_errors"][0])


class CliTest(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.r = Repo(self._t.name)

    def run_cli(self, *args, env_todo=None):
        env = dict(os.environ, LANG="C.UTF-8")
        env.pop("TODO_MD_PATH", None)
        if env_todo:
            env["TODO_MD_PATH"] = str(env_todo)
        return subprocess.run([sys.executable, CONTEXT, "--today", TODAY, *args],
                              capture_output=True, text=True, env=env)

    def test_prints_json(self):
        self.r.commit(doc(yaru="- [ ] a\n"), "todo: base", date="2026-11-03")
        res = self.run_cli("--todo", str(self.r.todo))
        self.assertEqual(res.returncode, 0, res.stderr)
        out = json.loads(res.stdout)
        self.assertEqual(out["today"], TODAY)
        self.assertEqual([i["ref"] for i in out["items"]], ["title:a"])

    def test_env_path(self):
        self.r.commit(doc(yaru="- [ ] a\n"), "todo: base")
        res = self.run_cli(env_todo=self.r.todo)
        self.assertEqual(res.returncode, 0, res.stderr)

    def test_unparsable_todo_exits_1(self):
        self.r.commit("## 謎\n", "todo: base")
        res = self.run_cli("--todo", str(self.r.todo))
        self.assertEqual(res.returncode, 1)
        self.assertIn("context:", res.stderr)
        self.assertEqual(res.stdout, "")


if __name__ == "__main__":
    unittest.main()
