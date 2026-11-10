import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import my_tasks_schema  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "my-tasks-sample.json"


def load():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


class ValidateCandidatesTest(unittest.TestCase):
    def test_fixture_is_valid(self):
        self.assertEqual(my_tasks_schema.validate_candidates(load()), [])

    def test_fixture_covers_key_kinds(self):
        keys = [c["key"] for c in load()["candidates"]]
        self.assertTrue(any(k and k.startswith("epc#") for k in keys))
        self.assertTrue(any(k and k.startswith("rc:") and "#" in k[3:] for k in keys))
        self.assertIn(None, keys)

    def bad(self, mutate):
        d = copy.deepcopy(load())
        mutate(d["candidates"][0])
        return my_tasks_schema.validate_candidates(d)

    def test_missing_required_key(self):
        self.assertTrue(self.bad(lambda c: c.pop("evidence")))

    def test_bad_ball(self):
        self.assertTrue(self.bad(lambda c: c.update(ball="done")))

    def test_bad_key_format(self):
        self.assertTrue(self.bad(lambda c: c.update(key="PR#12")))

    def test_key_null_ok(self):
        self.assertEqual(self.bad(lambda c: c.update(key=None)), [])

    def test_bad_deadline(self):
        self.assertTrue(self.bad(lambda c: c.update(deadline="2026/11/20")))

    def test_blocks_must_be_list_of_str(self):
        self.assertTrue(self.bad(lambda c: c.update(blocks="epc#1")))
        self.assertTrue(self.bad(lambda c: c.update(blocks=[1])))

    def test_top_level_shape(self):
        self.assertTrue(my_tasks_schema.validate_candidates([]))
        self.assertTrue(my_tasks_schema.validate_candidates({"candidates": []}))
        d = load()
        d["candidates"] = "x"
        self.assertTrue(my_tasks_schema.validate_candidates(d))

    def test_window_and_generated_at(self):
        d = load()
        d["window"] = {"from": "2026-11-10"}
        self.assertTrue(my_tasks_schema.validate_candidates(d))

    def test_null_waiting_person_ok_but_wrong_type_not(self):
        self.assertTrue(self.bad(lambda c: c.update(waiting_person=3)))


if __name__ == "__main__":
    unittest.main()
