#!/usr/bin/env python3
"""Independent Python datetime corpus generator; writes JSONL to stdout only.

Refresh deliberately and review the diff:
python3 benchmarks/chrono/generate_corpus.py > .roc-time-tmp/chrono-corpus.jsonl
"""
import datetime as dt
import json

DATES = [(1900, 2, 28), (1969, 12, 31), (1970, 1, 1), (1999, 12, 31),
         (2000, 2, 29), (2000, 3, 1), (2024, 2, 29), (2100, 2, 28)]
OFFSETS = ["+05:30", "-03:30", "+01:00", "-12:00"]

for i, (year, month, day) in enumerate(DATES):
    for j, offset in enumerate(OFFSETS):
        text = (f"{year:04}-{month:02}-{day:02}T{(i * 3 + j) % 24:02}:"
                f"{(i * 7 + j * 13) % 60:02}:{(i * 11 + j * 17) % 60:02}."
                f"{(i * 123457 + j * 27183) % 1000000:06}{offset}")
        value = dt.datetime.fromisoformat(text)
        delta = value.astimezone(dt.timezone.utc) - dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
        micros = (delta.days * 86400 + delta.seconds) * 1000000 + delta.microseconds
        print(json.dumps({"text": text, "day": (value.date() - dt.date(1970, 1, 1)).days,
                          "microseconds": micros, "canonical": value.isoformat(timespec="microseconds")}, sort_keys=True))
