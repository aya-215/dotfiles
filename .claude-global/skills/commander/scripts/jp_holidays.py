"""日本の祝日（2020年以降の祝日法）を計算する。"""
from datetime import date, timedelta

FIXED = {
    (1, 1): "元日",
    (2, 11): "建国記念の日",
    (2, 23): "天皇誕生日",
    (4, 29): "昭和の日",
    (5, 3): "憲法記念日",
    (5, 4): "みどりの日",
    (5, 5): "こどもの日",
    (8, 11): "山の日",
    (11, 3): "文化の日",
    (11, 23): "勤労感謝の日",
}
# (月, 第何月曜, 名前)
HAPPY_MONDAY = [(1, 2, "成人の日"), (7, 3, "海の日"), (9, 3, "敬老の日"), (10, 2, "スポーツの日")]


def _equinox(year: int, base: float) -> int:
    # 1980〜2099年で有効な近似式
    return int(base + 0.242194 * (year - 1980) - (year - 1980) // 4)


def _nth_monday(year: int, month: int, n: int) -> date:
    first = date(year, month, 1)
    return first + timedelta(days=(7 - first.weekday()) % 7 + 7 * (n - 1))


def _base_holidays(year: int) -> "dict[date, str]":
    h = {date(year, m, d): name for (m, d), name in FIXED.items()}
    for month, n, name in HAPPY_MONDAY:
        h[_nth_monday(year, month, n)] = name
    h[date(year, 3, _equinox(year, 20.8431))] = "春分の日"
    h[date(year, 9, _equinox(year, 23.2488))] = "秋分の日"
    return h


def _year_holidays(year: int) -> "dict[date, str]":
    h = _base_holidays(year)
    for day in sorted(h):
        if day.weekday() == 6:
            sub = day + timedelta(days=1)
            while sub in h:
                sub += timedelta(days=1)
            h[sub] = "振替休日"
    for day in sorted(list(h)):
        mid = day + timedelta(days=1)
        if mid not in h and mid.weekday() != 6 and (day + timedelta(days=2)) in h:
            h[mid] = "国民の休日"
    return h


def holidays_between(start: date, end: date) -> "list[tuple[date, str]]":
    out = []
    for year in range(start.year, end.year + 1):
        out += [(d, n) for d, n in _year_holidays(year).items() if start <= d <= end]
    return sorted(out)
