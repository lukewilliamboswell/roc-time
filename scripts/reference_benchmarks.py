#!/usr/bin/env python3
"""Retained independent datetime benchmark reference, without process orchestration.

The oracle and checksum functions are unchanged from benchmark_chrono.py.
Measured Python subjects remain under benchmarks/comparison/.
"""
import datetime as dt
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
MODES = ("date_control", "date_to_day", "construct", "roundtrip", "add_days", "parse", "resolve", "format", "end_to_end", "parse_only")

def oracle(text):
    value = dt.datetime.fromisoformat(text)
    delta = value.astimezone(dt.timezone.utc) - dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
    micros = (delta.days * 86400 + delta.seconds) * 1000000 + delta.microseconds
    return {"text": text, "day": (value.date() - dt.date(1970, 1, 1)).days,
            "microseconds": micros, "canonical": value.isoformat(timespec="microseconds")}


def expected_sum(corpus, mode, iterations):
    values = []
    for case in corpus:
        date = dt.datetime.fromisoformat(case["text"]).date()
        if mode == "add_days":
            date += dt.timedelta(days=17)
        if mode in ("date_control", "construct", "roundtrip", "add_days"):
            values.append(date.year * 10000 + date.month * 100 + date.day)
        elif mode == "date_to_day":
            shifted_day = case["day"] + 1000000
            if not 0 <= shifted_day < 2**64:
                raise ValueError("day-coordinate checksum outside unsigned range")
            values.append(shifted_day)
        elif mode == "parse_only":
            local = dt.datetime.fromisoformat(case["text"])
            clock = ((local.hour * 60 + local.minute) * 60 + local.second) * 1000000 + local.microsecond
            offset = local.utcoffset()
            if offset is None or offset.microseconds:
                raise ValueError("parser-only corpus requires whole-second offsets")
            offset_seconds = offset.days * 86400 + offset.seconds
            values.append(date.year * 10000 + date.month * 100 + date.day
                          + clock + (offset_seconds + 86400) * 101)
        elif mode in ("parse", "resolve"):
            values.append(case["microseconds"] % 1000000007)
        elif mode in ("format", "end_to_end"):
            values.append(sum(case["canonical"].encode("ascii")))
        else:
            raise ValueError(f"unknown workload: {mode}")
    cycles, tail = divmod(iterations, len(values))
    return cycles * sum(values) + sum(values[:tail])


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: reference_benchmarks.py CORPUS ITERATIONS')
    source = Path(sys.argv[1])
    iterations = int(sys.argv[2])
    if source.stat().st_size > 1048576 or not 1 <= iterations <= 10000000:
        raise ValueError('Reference budget exceeded')
    corpus = [json.loads(line) for line in source.read_text().splitlines()]
    if not corpus or len(corpus) > 4096 or any(case != oracle(case['text']) for case in corpus):
        raise ValueError('Corpus disagrees with independent datetime oracle')
    print(json.dumps({'cases': corpus, 'checksums': {mode: expected_sum(corpus, mode, iterations) for mode in MODES}}, separators=(',', ':')))
