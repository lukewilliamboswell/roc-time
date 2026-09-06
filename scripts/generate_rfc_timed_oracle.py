#!/usr/bin/env python3
"""R11–R12: pinned dateutil UTC clock selectors, counts, cutoffs and sets.

Finite synchronized rules; no timezone transitions, leap seconds or PERIODs.
Generation invokes no roc-time code. Normal replay uses only the saved corpus.
"""
import argparse
import datetime as dt
import hashlib
import itertools
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
    ('20241231T235958Z', 'FREQ=SECONDLY'),
    ('20240101T090000Z', 'FREQ=SECONDLY;BYSECOND=0,15,30,45'),
    ('20240229T235959Z', 'FREQ=MINUTELY'),
    ('20240101T090005Z', 'FREQ=MINUTELY;BYSECOND=5,35'),
    ('20240101T090035Z', 'FREQ=MINUTELY;BYSECOND=5,35;BYSETPOS=-1'),
    ('20241231T233017Z', 'FREQ=HOURLY'),
    ('20240101T090005Z', 'FREQ=HOURLY;BYMINUTE=0,30;BYSECOND=5,35'),
    ('20240101T093035Z', 'FREQ=HOURLY;BYMINUTE=0,30;BYSECOND=5,35;BYSETPOS=-1'),
    ('20240101T090005Z', 'FREQ=HOURLY;BYMINUTE=0,30;BYSECOND=5,35;BYSETPOS=1,-1'),
    ('20240101T090000Z', 'FREQ=DAILY;BYHOUR=9,17'),
    ('20240101T173035Z', 'FREQ=DAILY;BYHOUR=9,17;BYMINUTE=0,30;BYSECOND=5,35;BYSETPOS=-1'),
    ('20240131T090000Z', 'FREQ=MONTHLY;BYHOUR=9,17'),
]
FORMAT = '%Y%m%dT%H%M%SZ'
EPOCH = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)


def generate(directory):
    if platform.python_version() != '3.12.3' or platform.python_implementation() != 'CPython':
        raise SystemExit('Use pinned CPython 3.12.3')
    for filename, digest in PINS.items():
        path = directory / filename
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Wrong reference wheel: {filename}')
        sys.path.insert(0, str(path.resolve()))
    from dateutil.rrule import rrulestr, rruleset
    randomizer = random.Random(20260906)
    cases = []
    for start_text, template in TEMPLATES:
        anchor = dt.datetime.strptime(start_text, FORMAT).replace(tzinfo=dt.timezone.utc)
        for sample in range(32):
            text = template + f';INTERVAL={randomizer.randint(1, 3)}'
            # Bounded prefix supplies a synchronized cutoff, never expectations
            # from the package under test. +/- one second probes inclusivity.
            prefix = list(itertools.islice(rrulestr(text, dtstart=anchor), 12))
            assert len(prefix) == 12 and prefix[0] == anchor
            if sample % 2:
                text += f';COUNT={randomizer.randint(1, 12)}'
            else:
                cutoff = prefix[randomizer.randint(1, 10)] + dt.timedelta(seconds=(sample % 3)-1)
                text += ';UNTIL=' + cutoff.strftime(FORMAT)
            fields = text.split(';')
            randomizer.shuffle(fields)
            text = ';'.join(fields)
            if sample % 4 == 0:
                text = text.lower()
            rule = rrulestr(text, dtstart=anchor)
            generated = list(rule)
            assert 1 <= len(generated) <= 12 and generated[0] == anchor
            inclusions = [anchor-dt.timedelta(seconds=1), prefix[-1]+dt.timedelta(seconds=1), anchor, anchor] if sample % 3 else []
            exclusions = [generated[sample % len(generated)]] if sample % 5 else []
            if sample % 7 == 0:
                exclusions += [anchor, anchor]
            lower = anchor-dt.timedelta(seconds=2) if sample % 4 == 0 else prefix[sample % 6]
            upper = prefix[-1] + dt.timedelta(seconds=2)
            series = rruleset()
            series.rrule(rule)
            for value in inclusions:
                series.rdate(value)
            for value in exclusions:
                series.exdate(value)
            selected = series.between(lower, upper-dt.timedelta(seconds=1), inc=True)
            expected = ['ok'] + [str((value-EPOCH)//dt.timedelta(microseconds=1)) for value in selected]
            assert len(expected) <= 32
            inputs = [start_text, text, ','.join(x.strftime(FORMAT) for x in inclusions) or '-',
                      ','.join(x.strftime(FORMAT) for x in exclusions) or '-', lower.strftime(FORMAT), upper.strftime(FORMAT)]
            cases.append(dict(id=str(len(cases)), operation='rfc_timed', input=inputs, expected=expected,
                              evidence='dateutil-2.9.0.post0-utc-rrulestr-and-rruleset'))
    corpus = ROOT / 'tests/oracles/rfc_timed.jsonl'
    corpus.write_text(''.join(json.dumps(c, separators=(',', ':'))+'\n' for c in cases))
    driver = ROOT / 'tests/oracle_rfc_timed'
    driver.mkdir(exist_ok=True)
    selected = [cases[index*32] for index in range(len(TEMPLATES))]
    rows = ',\n'.join('{ input: '+json.dumps(c['input'])+', expected: '+json.dumps('\t'.join(c['expected']))+' }' for c in selected)
    smoke = driver / 'SmokeCases.roc'
    smoke.write_text('SmokeCases :: [].{\n inputs : List({ input : List(Str), expected : Str })\n inputs = [\n'+rows+'\n]\n}\n')
    manifest = dict(version=2, corpus_format='jsonl-v1', profile='rfc5545-timed-values-v1', case_count=len(cases),
                    corpus_sha256=hashlib.sha256(corpus.read_bytes()).hexdigest(),
                    smoke_case_count=len(selected), smoke_sha256=hashlib.sha256(smoke.read_bytes()).hexdigest(),
                    generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    reference='python-dateutil 2.9.0.post0 with six 1.17.0, CPython 3.12.3', seed=20260906,
                    source_wheels=list(PINS), source_sha256=list(PINS.values()),
                    sources=['https://pypi.org/project/python-dateutil/2.9.0.post0/', 'https://pypi.org/project/six/1.17.0/', 'https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.10'],
                    license='Numerical observations only; no reference implementation code copied. dateutil: BSD/Apache-2.0; six: MIT.',
                    independence='dateutil parses text and expands indexed calendar/clock masks; Roc uses native bounded cursors. Shared Gregorian and UTC conventions. Twelve synchronized templates, SECONDLY/MINUTELY/HOURLY/DAILY/MONTHLY, clock expansion/filtering and signed BYSETPOS, COUNT, inclusive UNTIL, duplicate RDATE/EXDATE and half-open windows. No local zones, leap seconds, PERIOD overrides, disputed yearly defaults or general RFC conformance claim.')
    (ROOT / 'tests/oracles/rfc_timed-manifest.toml').write_text('\n'.join(f'{k} = {json.dumps(v)}' for k,v in manifest.items())+'\n')
    print(f'Generated {len(cases)} RFC timed observations')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wheel_directory', type=Path)
    generate(parser.parse_args().wheel_directory)
