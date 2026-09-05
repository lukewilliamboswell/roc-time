#!/usr/bin/env python3
"""Generate RFC date-rule observations from pinned dateutil, never roc-time."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import platform
import random
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
PINS = {
    'python_dateutil-2.9.0.post0-py2.py3-none-any.whl': 'a8b2bc7bffae282281c8140a97d3aa9c14da0b136dfe83f850eea9a5f7470427',
    'six-1.17.0-py2.py3-none-any.whl': '4721f391ed90541fddacab5acf947aa0d3dc7d27b2e1e8eda2be8970586c3274',
}
TEMPLATES = [
    ('20240101', 'FREQ=DAILY'),
    ('20240101', 'FREQ=DAILY;BYMONTH=1'),
    ('20240101', 'FREQ=WEEKLY;BYDAY=MO,FR'),
    ('20240104', 'FREQ=WEEKLY'),
    ('20240131', 'FREQ=MONTHLY'),
    ('20240129', 'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=-1'),
    ('20240101', 'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1,-1'),
    ('20240101', 'FREQ=MONTHLY;BYMONTHDAY=1,15,-1'),
    ('20240101', 'FREQ=YEARLY'),
    ('20240229', 'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29'),
    ('20240101', 'FREQ=YEARLY;BYMONTH=1,6;BYMONTHDAY=1'),
    ('20240101', 'FREQ=YEARLY;BYYEARDAY=1,-1'),
    ('20240101', 'FREQ=YEARLY;BYDAY=MO;BYSETPOS=1,-1'),
    ('20240126', 'FREQ=MONTHLY;BYDAY=-1FR'),
    ('20240101', 'FREQ=YEARLY;BYMONTH=1;BYDAY=1MO'),
    ('20240101', 'FREQ=YEARLY;BYMONTH=1,6;BYDAY=1MO'),
]


def generate(directory: Path) -> None:
    if platform.python_version() != '3.14.3' or platform.python_implementation() != 'CPython':
        raise SystemExit('Use pinned CPython 3.14.3')
    for filename, digest in PINS.items():
        path = directory / filename
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Wrong reference wheel: {filename}')
        sys.path.insert(0, str(path.resolve()))
    from dateutil.rrule import rrulestr, rruleset
    randomizer = random.Random(20260905)
    cases = []
    for start_text, template in TEMPLATES:
        anchor = dt.datetime.strptime(start_text, '%Y%m%d')
        for sample in range(32):
            interval = randomizer.randint(1, 3)
            text = template + f';INTERVAL={interval};WKST=' + randomizer.choice(['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'])
            if sample % 3:
                text += f';COUNT={randomizer.randint(1, 10)}'
            else:
                horizon = 18 if 'FREQ=DAILY' in text else 60 if 'FREQ=WEEKLY' in text else 180
                text += ';UNTIL=' + (anchor + dt.timedelta(days=randomizer.randint(0, horizon))).strftime('%Y%m%d')
            # Retain ordering/case variations as parser evidence.
            fields = text.split(';')
            randomizer.shuffle(fields)
            text = ';'.join(fields)
            if sample % 4 == 0:
                text = text.lower()
            rule = rrulestr(text, dtstart=anchor)
            generated = list(rule)
            assert generated and generated[0] == anchor, 'Oracle fixture DTSTART must be synchronized'
            inclusions = [dt.datetime(2023, 12, 30), dt.datetime(2024, 2, 4), dt.datetime(2025, 1, 1)] if sample % 2 else []
            if inclusions:
                inclusions += [anchor, inclusions[1]]
            exclusions = [generated[sample % len(generated)]] if sample % 5 else []
            if sample % 7 == 0:
                exclusions += [anchor, anchor]
            start = dt.datetime(2024, randomizer.randint(1, 12), 1) if sample % 4 else dt.datetime(2023, 12, 1)
            end = dt.datetime(2026, 1, 1)
            series = rruleset()
            series.rrule(rule)
            for date in inclusions:
                series.rdate(date)
            for date in exclusions:
                series.exdate(date)
            expected = ['ok'] + [date.strftime('%Y%m%d') for date in series.between(start, end-dt.timedelta(seconds=1), inc=True)]
            assert len(expected) <= 32
            inputs = [start_text, text,
                      ','.join(date.strftime('%Y%m%d') for date in inclusions) or '-',
                      ','.join(date.strftime('%Y%m%d') for date in exclusions) or '-',
                      start.strftime('%Y%m%d'), end.strftime('%Y%m%d')]
            cases.append(dict(id=str(len(cases)), operation='rfc_date', input=inputs, expected=expected,
                              evidence='dateutil-2.9.0.post0-rrulestr-and-rruleset'))
    data = ROOT / 'tests/oracles/rfc_date.jsonl'
    data.write_text(''.join(json.dumps(case, separators=(',', ':'))+'\n' for case in cases))
    driver = ROOT / 'tests/oracle_rfc_date'
    driver.mkdir(exist_ok=True)
    selected = [cases[index*32] for index in (0, 2, 4, 6, 9, 12, 14, 15)]
    rows = ',\n'.join('{ input: '+json.dumps(case['input'])+', expected: '+json.dumps('\t'.join(case['expected']))+' }' for case in selected)
    smoke = driver / 'SmokeCases.roc'
    smoke.write_text('SmokeCases :: [].{\n inputs : List({ input : List(Str), expected : Str })\n inputs = [\n'+rows+'\n]\n}\n')
    manifest = dict(version=2, corpus_format='jsonl-v1', profile='rfc5545-date-values-v1',
                    case_count=len(cases), corpus_sha256=hashlib.sha256(data.read_bytes()).hexdigest(),
                    smoke_case_count=len(selected), smoke_sha256=hashlib.sha256(smoke.read_bytes()).hexdigest(),
                    generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    reference='python-dateutil 2.9.0.post0 with six 1.17.0, CPython 3.14.3', seed=20260905,
                    source_wheels=list(PINS), source_sha256=list(PINS.values()),
                    sources=['https://pypi.org/project/python-dateutil/2.9.0.post0/', 'https://pypi.org/project/six/1.17.0/', 'https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.10', 'https://www.rfc-editor.org/rfc/rfc5545.html#section-3.8.5'],
                    license='Numerical observations only; no reference implementation code copied. dateutil: BSD/Apache-2.0; six: MIT.',
                    independence='dateutil parses and expands indexed calendar masks; Roc parses into DateRecurrence and scans bounded calendar periods. Shared Gregorian conventions. Synchronized DTSTART, DATE-valued rules only, 16 templates; no timed semantics, BYWEEKNO, disputed implicit yearly fields or complete RFC conformance claim.')
    (ROOT / 'tests/oracles/rfc_date-manifest.toml').write_text('\n'.join(f'{k} = {json.dumps(v)}' for k,v in manifest.items())+'\n')
    print(f'Generated {len(cases)} RFC date observations')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wheel_directory', type=Path)
    generate(parser.parse_args().wheel_directory)
