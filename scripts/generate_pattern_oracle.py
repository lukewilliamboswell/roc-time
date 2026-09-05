#!/usr/bin/env python3
"""Generate calendar-pattern observations from pinned dateutil, never roc-time."""
import argparse
import calendar
from collections import Counter
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


def week_rows(start, end, wkst, selected, weekdays):
    """Independent seven-day row enumeration, assigning each week by majority year.

    Unlike Roc's Jan-4 arithmetic and dateutil's indexed masks, this enumerates
    calendar rows and counts their years. Each ordinal uses its week-numbering
    year, including rows crossing a civil-year boundary.
    """
    result = set()
    cal = calendar.Calendar(wkst)
    for year in range(start.year-1, end.year+1):
        rows = set()
        for month in range(1, 13):
            for row in cal.monthdatescalendar(year, month):
                owner, count = Counter(date.year for date in row).most_common(1)[0]
                if owner == year:
                    assert count >= 4
                    rows.add(tuple(row))
        ordered = sorted(rows)
        assert len(ordered) in (52, 53)
        for ordinal in selected:
            index = ordinal-1 if ordinal > 0 else len(ordered)+ordinal
            if not 0 <= index < len(ordered):
                continue
            for date in ordered[index]:
                value = dt.datetime.combine(date, dt.time())
                if start <= value < end and (not weekdays or date.weekday() in weekdays):
                    result.add(value)
    return result


def generate(directory: Path) -> None:
    if platform.python_version() != '3.14.3' or platform.python_implementation() != 'CPython':
        raise SystemExit('Use pinned CPython 3.14.3')
    for filename, digest in PINS.items():
        path = directory / filename
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Wrong reference wheel: {filename}')
        sys.path.insert(0, str(path.resolve()))
    from dateutil import rrule
    frequencies = [rrule.DAILY, rrule.WEEKLY, rrule.MONTHLY, rrule.YEARLY]
    randomizer = random.Random(20260905)
    cases, disagreements = [], []
    for frequency in range(4):
        for sample in range(256 if frequency == 3 else 64):
            anchor = dt.datetime(randomizer.choice([1900, 1997, 1999, 2000, 2015, 2016, 2025]),
                                 randomizer.randint(1, 12), randomizer.randint(1, 28))
            interval, index, wkst = randomizer.randint(1, 3), randomizer.randint(1, 3), randomizer.randrange(7)
            selectors = dict(bymonth=[], bymonthday=[], byyearday=[], byweekno=[], byweekday=[])
            mode = sample % 8
            if mode in (1, 5): selectors['bymonth'] = [1, 2, 12]
            if mode in (2, 5, 6) and frequency != 1: selectors['bymonthday'] = [1, 15, -1]
            if mode in (3, 5, 7): selectors['byweekday'] = [(0, 0), (0, 4)]
            if mode == 4 and frequency >= 2: selectors['byweekday'] = [(1, 1), (-1, 4)]
            if mode == 6 and frequency == 3:
                selectors['bymonthday'] = []
                selectors['byyearday'] = [1, 60, -1]
            if mode == 7 and frequency == 3: selectors['byweekno'] = [1, -1, 53]
            if frequency == 3 and sample >= 64:
                # Isolate week selectors: a union with week 53 can conceal a
                # wrong interpretation of negative weeks at a year boundary.
                anchor = dt.datetime([1996, 1997, 1998, 1999, 2003, 2008, 2014, 2015][sample % 8], 1, 1)
                interval, index, wkst = 1, 1, sample % 7
                selectors = dict(bymonth=[], bymonthday=[], byyearday=[],
                                 byweekno=[[1], [-1], [53], [-53]][sample % 4],
                                 byweekday=[] if sample % 3 else [(0, 0)])
            if frequency == 0:
                start = anchor + dt.timedelta(days=interval * index)
                end = start + dt.timedelta(days=1)
            elif frequency == 1:
                start = anchor - dt.timedelta(days=(anchor.weekday()-wkst) % 7) + dt.timedelta(weeks=interval*index)
                end = start + dt.timedelta(days=7)
            elif frequency == 2:
                month = anchor.year*12 + anchor.month-1 + interval*index
                year, zero_month = divmod(month, 12)
                start = dt.datetime(year, zero_month+1, 1)
                end = start + dt.timedelta(days=calendar.monthrange(year, zero_month+1)[1])
            else:
                start = dt.datetime(anchor.year + interval*index, 1, 1)
                end = dt.datetime(start.year+1, 1, 1)
            kwargs = {key: values for key, values in selectors.items() if values}
            if selectors['byweekday']:
                kwargs['byweekday'] = [rrule.weekday(day, ordinal or None) for ordinal, day in selectors['byweekday']]
            # Only later whole periods: dateutil's DTSTART truncation cannot
            # hide candidates before the anchor within the first period.
            rule = rrule.rrule(frequencies[frequency], dtstart=anchor, interval=interval, wkst=wkst,
                               until=end-dt.timedelta(seconds=1), **kwargs)
            dates = set(rule.between(start, end-dt.timedelta(seconds=1), inc=True))
            reference_dates = dates
            if selectors['byweekno']:
                assert not selectors['bymonth'] and not selectors['bymonthday'] and not selectors['byyearday']
                assert all(ordinal == 0 for ordinal, _ in selectors['byweekday'])
                dates = week_rows(start, end, wkst, selectors['byweekno'], [day for _, day in selectors['byweekday']])
            bits = ''.join('1' if start+dt.timedelta(days=i) in dates else '0' for i in range((end-start).days))
            epoch = dt.datetime(1970, 1, 1)
            expected = ['ok', str((start-epoch).days), str((end-epoch).days), *[bits[i:i+128] for i in range(0,len(bits),128)]]
            inputs = list(map(str, [anchor.year, anchor.month, anchor.day, frequency, interval, wkst, index]))
            for key in ('bymonth', 'bymonthday', 'byyearday', 'byweekno'):
                inputs.append(','.join(map(str, selectors[key])) or '-')
            inputs.append(','.join(f'{ordinal}:{day}' for ordinal,day in selectors['byweekday']) or '-')
            evidence = 'enumerated-week-rows' if selectors['byweekno'] else 'dateutil-2.9.0.post0-calendar-period'
            if dates != reference_dates:
                # Refuse to silently extend the known reference gap to arbitrary
                # mid-year differences. Preserve both outputs for review.
                assert all((d.month == 1 and d.day <= 7) or (d.month == 12 and d.day >= 25)
                           for d in dates.symmetric_difference(reference_dates))
                disagreements.append(dict(id=str(len(cases)), input=inputs,
                    dateutil=sorted(d.date().isoformat() for d in reference_dates),
                    week_rows=sorted(d.date().isoformat() for d in dates)))
            cases.append(dict(id=str(len(cases)), operation='pattern', input=inputs, expected=expected, evidence=evidence))
    data = ROOT / 'tests/oracles/calendar_pattern.jsonl'
    data.write_text(''.join(json.dumps(case, separators=(',', ':'))+'\n' for case in cases))
    gaps = ROOT / 'tests/oracles/calendar_pattern-reference-gaps.jsonl'
    gaps.write_text(''.join(json.dumps(case, separators=(',', ':'))+'\n' for case in disagreements))
    driver = ROOT / 'tests/oracle_calendar_pattern'
    driver.mkdir(exist_ok=True)
    rows = ',\n'.join('{ input: '+json.dumps(case['input'])+', expected: '+json.dumps('\t'.join(case['expected']))+' }' for case in cases[:4])
    smoke = driver / 'SmokeCases.roc'
    smoke.write_text('SmokeCases :: [].{\n inputs : List({ input : List(Str), expected : Str })\n inputs = [\n'+rows+'\n]\n}\n')
    manifest = dict(version=2, corpus_format='jsonl-v1', profile='gregorian-calendar-patterns-v1',
                    case_count=len(cases), corpus_sha256=hashlib.sha256(data.read_bytes()).hexdigest(),
                    smoke_case_count=4, smoke_sha256=hashlib.sha256(smoke.read_bytes()).hexdigest(),
                    generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    reference_gap_count=len(disagreements), reference_gap_sha256=hashlib.sha256(gaps.read_bytes()).hexdigest(),
                    reference='python-dateutil 2.9.0.post0 with six 1.17.0, CPython 3.14.3', seed=20260905,
                    source_wheels=list(PINS), source_sha256=list(PINS.values()),
                    sources=['https://pypi.org/project/python-dateutil/2.9.0.post0/', 'https://pypi.org/project/six/1.17.0/', 'https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.10', 'https://www.rfc-editor.org/rfc/rfc8984.html#section-4.3.3.1'],
                    license='Numerical observations only; no reference implementation code copied. dateutil: BSD/Apache-2.0; six: MIT.',
                    independence='dateutil expands indexed day masks; Roc tests dates against calendar selectors. Week selectors instead enumerate calendar rows and majority-year assignment; retained dateutil differences expose its adjacent-year gaps. Shared Gregorian/week convention assumptions. Positive years only; no timezone, COUNT, BYSETPOS, exclusions or first-period truncation claim.')
    (ROOT / 'tests/oracles/calendar_pattern-manifest.toml').write_text('\n'.join(f'{k} = {json.dumps(v)}' for k,v in manifest.items())+'\n')
    print(f'Generated {len(cases)} pattern observations; {len(disagreements)} retained dateutil/week-row differences')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wheel_directory', type=Path)
    generate(parser.parse_args().wheel_directory)
