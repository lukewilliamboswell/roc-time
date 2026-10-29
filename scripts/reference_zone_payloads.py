#!/usr/bin/env python3
"""Retained CPython TZif reference decoder from measure_zone_roc.py.

This emits the independently decoded fixture values only. Roc owns source
emission, bundling, builds, process supervision, comparison and measurement.
The reference domain and wheel pin are unchanged from the prototype driver.
"""
import hashlib
import io
import json
from pathlib import Path
import platform
import sys
import zipfile
from zoneinfo._common import load_data

sys.dont_write_bytecode = True
from generate_zone_oracle import WHEEL_SHA256


def decode(wheel: Path, smoke: bool) -> list[dict]:
    required = (Path(__file__).resolve().parents[1] / 'benchmarks/python-version').read_text().strip()
    if platform.python_implementation() != 'CPython' or platform.python_version() != required:
        raise ValueError(f'Requires pinned CPython {required} TZif reference decoder')
    if wheel.stat().st_size > 1024 * 1024 or hashlib.sha256(wheel.read_bytes()).hexdigest() != WHEEL_SHA256:
        raise ValueError('Wrong tzdata wheel')
    selected = {'Australia/Melbourne', 'America/New_York', 'Europe/London', 'Pacific/Apia'}
    rows = []
    with zipfile.ZipFile(wheel) as archive:
        for info in archive.infolist():
            if not info.filename.startswith('tzdata/zoneinfo/') or info.is_dir():
                continue
            name = info.filename.removeprefix('tzdata/zoneinfo/')
            if smoke and name not in selected:
                continue
            raw = archive.read(info)
            if not raw.startswith(b'TZif'):
                continue
            indices, times, offsets, _, _, footer = load_data(io.BytesIO(raw))
            rows.append({'name': name, 'sha256': hashlib.sha256(raw).hexdigest(),
                         'data': {'times': list(times), 'indices': list(indices),
                                  'offsets': list(offsets), 'footer': (footer or b'').decode(),
                                  'bytes': list(raw)}})
    if smoke:
        melbourne = next(row for row in rows if row['name'] == 'Australia/Melbourne')
        rows.append({**melbourne, 'name': 'Fixture/MelbourneAlias'})
    return rows


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[2] not in ('smoke', 'full'):
        raise SystemExit('usage: reference_zone_payloads.py WHEEL smoke|full')
    print(json.dumps(decode(Path(sys.argv[1]), sys.argv[2] == 'smoke'), separators=(',', ':')))
