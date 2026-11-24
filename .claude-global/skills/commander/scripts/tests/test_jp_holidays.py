import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from jp_holidays import holidays_between  # noqa: E402


def d(s):
    return date.fromisoformat(s)


class HolidaysTest(unittest.TestCase):
    def test_fixed(self):
        nov = holidays_between(d("2026-11-01"), d("2026-11-30"))
        self.assertIn((d("2026-11-23"), "勤労感謝の日"), nov)
        self.assertIn((d("2026-11-03"), "文化の日"), nov)

    def test_happy_monday(self):
        self.assertIn((d("2027-01-11"), "成人の日"), holidays_between(d("2027-01-01"), d("2027-01-31")))
        self.assertIn((d("2026-09-21"), "敬老の日"), holidays_between(d("2026-09-01"), d("2026-09-30")))

    def test_equinox_and_kokumin(self):
        sep = holidays_between(d("2026-09-01"), d("2026-09-30"))
        self.assertIn((d("2026-09-23"), "秋分の日"), sep)
        self.assertIn((d("2026-09-22"), "国民の休日"), sep)

    def test_substitute(self):
        self.assertIn((d("2026-05-06"), "振替休日"), holidays_between(d("2026-05-01"), d("2026-05-31")))

    def test_range_inclusive_and_sorted(self):
        self.assertEqual(holidays_between(d("2026-11-23"), d("2026-11-23")), [(d("2026-11-23"), "勤労感謝の日")])
        got = holidays_between(d("2026-12-20"), d("2027-01-15"))
        self.assertEqual(got, sorted(got))
        self.assertEqual([x[1] for x in got], ["元日", "成人の日"])


if __name__ == "__main__":
    unittest.main()
