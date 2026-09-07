"""Explicit corpus regeneration; requires the pinned independent runtime."""
import json
import sys
from datetime import date

if sys.version_info[:3] != (3, 12, 3):
    raise SystemExit("Reference requires CPython 3.12.3")

for year in (1, 4, 100, 400, 1582, 1900, 1999, 2000, 2004, 2020, 2021,
             2100, 2400, 9999, -2147483648, -2147483647, -401, -400,
             -100, -4, -1, 0, 2147483646, 2147483647):
    mapped = year if 1 <= year <= 9999 else 2000 + year % 400
    for month, day in ((1, 1), (1, 4), (2, 28), (2, 29), (3, 1),
                       (12, 28), (12, 29), (12, 30), (12, 31)):
        try:
            value = date(mapped, month, day)
        except ValueError:
            continue
        iso = value.isocalendar()
        spelling = f"{year:04}" if 0 <= year <= 9999 else (f"-{abs(year):04}" if year < 0 else f"+{year}")
        print(json.dumps({
            "input": f"{spelling}-{month:02}-{day:02}",
            "origin": "direct-python" if mapped == year else "cycle-extension",
            "reference_year": mapped,
            "expected": [value.weekday() + 1, value.timetuple().tm_yday,
                         iso.year + year - mapped, iso.week, iso.weekday],
        }, separators=(",", ":")))
