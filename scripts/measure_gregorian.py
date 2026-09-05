#!/usr/bin/env python3
"""Measure validated date construction and coordinate round trips, including startup."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iterations', type=int, default=1_000_000)
    parser.add_argument('--runs', type=int, default=15)
    parser.add_argument('--warmups', type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.iterations <= 100_000_000 or args.runs < 2 or args.warmups < 0:
        parser.error('iterations must be 1..100000000, runs >= 2, warmups >= 0')
    roc = os.environ.get('ROC', 'roc')
    version = subprocess.check_output([roc, 'version'], text=True).strip()
    if version != 'Roc compiler version ' + (ROOT / '.roc-version').read_text().strip():
        raise SystemExit('Select the pinned compiler with ROC')
    output = ROOT / '.roc-time-tmp/gregorian-performance'
    output.mkdir(parents=True, exist_ok=True)
    binary = output / 'date-bench'
    subprocess.run([roc, 'build', '--opt=speed', f'--output={binary}',
                    'tests/gregorian_performance/main.roc'], cwd=ROOT, check=True)
    # Independent expected fields; no conversion formula in the timing harness.
    expected = str(sum(1970 + (i * 37) % 8030 + (i * 17) % 12 + 1
                       + (i * 13) % 28 + 1 for i in range(args.iterations)))
    result = {'compiler': version, 'backend': 'LLVM speed',
              'machine': platform.machine(), 'platform': platform.platform(),
              'iterations': args.iterations, 'warmups': args.warmups,
              'runs': args.runs, 'checksum': expected,
              'scope': 'Process wall time including startup and checksum formatting; '
                       'scalar dates, no shared input lists. No allocation or retained-memory measurement.',
              'workloads': {}}
    for mode in ('fields', 'roundtrip'):
        samples = []
        for index in range(args.warmups + args.runs):
            start = time.perf_counter()
            observed = subprocess.check_output([str(binary), str(args.iterations), mode],
                                               text=True, timeout=120).strip()
            elapsed = time.perf_counter() - start
            if observed != expected:
                raise SystemExit(f'{mode}: checksum {observed!r}, expected {expected!r}')
            if index >= args.warmups:
                samples.append(elapsed)
        result['workloads'][mode] = {'seconds': samples,
                                     'mean_seconds': statistics.mean(samples),
                                     'stdev_seconds': statistics.stdev(samples)}
        print(f'{mode}: {statistics.mean(samples) * 1000:.2f} ms '
              f'+/- {statistics.stdev(samples) * 1000:.2f} ms')
    path = output / 'results.json'
    path.write_text(json.dumps(result, indent=2) + '\n')
    print(path)


if __name__ == '__main__':
    main()
