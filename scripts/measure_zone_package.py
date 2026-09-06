#!/usr/bin/env python3
"""Measure real zone packages using the instrumented, observable lookup fixture."""
from __future__ import annotations
from roc_version import package_pin

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from fixture_platform import build_host
from oracle_replay import parse_metrics

ROOT = Path(__file__).resolve().parents[1]
NAMES = ("Australia/Melbourne", "US/Eastern", "Pacific/Apia", "Etc/UTC")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, action='append', required=True)
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--opt', choices=('dev', 'speed'), default='dev')
    args = parser.parse_args()
    if not 1 <= args.samples <= 10:
        parser.error('--samples must be between 1 and 10')
    roc = os.environ.get('ROC', 'roc')
    if '/' in roc or '\\' in roc:
        roc = str(Path(roc).resolve())
    version = subprocess.check_output([roc, 'version'], text=True).strip()
    if version != 'Roc compiler version ' + package_pin(ROOT):
        raise SystemExit('Use the pinned Roc compiler')
    target = build_host()
    parent = ROOT / '.roc-time-tmp'
    parent.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='zone-package-measure-', dir=parent))
    fixture = (ROOT / 'tests/zone_database/resource/main.roc').read_text()
    # Compare historical providers too: measure their allocation counts without
    # imposing the current implementation's regression budget on them.
    fixture = '\n'.join(line for line in fixture.splitlines() if 'Host.assert!' not in line) + '\n'
    report = dict(compiler=version, target=target, backend='native', optimize=args.opt,
                  host=platform.platform(), samples=args.samples,
                  script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  limits='Uncached builds, no warmup; OS caches may be warm. Compiler wall time/RSS and '
                  'binary size only, not runtime latency or retained memory. Lookup counters exclude '
                  'argument preparation, core adaptation and output formatting. Immutable source data '
                  'may be shared. Each process performs one lookup and consumes its transitions.',
                  measurements=[])
    for number, supplied in enumerate(args.package):
        package = supplied.resolve()
        manifest = json.loads((package / 'manifest.json').read_text())
        for mode in ('static', 'dynamic'):
            app = work / f'{number}-{mode}'
            app.mkdir()
            source = fixture.replace('"../../platform/main.roc"',
                                     json.dumps(os.path.relpath(ROOT / 'tests/platform/main.roc', app)))
            source = source.replace('"../../../tzdb/package/main.roc"',
                                    json.dumps(os.path.relpath(package / 'main.roc', app)))
            if mode == 'static':
                source = source.replace('|args|', '|_args|').replace(
                    'args.get(1) ?? "Australia/Melbourne"', '"Australia/Melbourne"')
            (app / 'main.roc').write_text(source)
            binary = app / 'native'
            measurements = []
            for sample in range(args.samples):
                command = [roc, 'build', 'main.roc', '--no-cache', '--debug',
                           f'--target={target}', f'--opt={args.opt}', f'--output={binary}']
                if sys.platform == 'darwin':
                    command = ['/usr/bin/time', '-l', *command]
                started = time.perf_counter()
                result = subprocess.run(command, cwd=app, text=True, capture_output=True, timeout=180)
                elapsed = time.perf_counter() - started
                (app / f'build-{sample}.log').write_text(result.stdout + result.stderr)
                result.check_returncode()
                rss = re.search(r'(\d+)\s+maximum resident set size', result.stderr)
                measurements.append(dict(command=command, seconds=elapsed,
                                         compiler_peak_rss_bytes=int(rss[1]) if rss else None,
                                         binary_bytes=binary.stat().st_size))
            observed = {}
            for name in NAMES[:1] if mode == 'static' else NAMES:
                result = subprocess.run([str(binary), name], capture_output=True, text=True,
                                        check=True, timeout=10)
                canonical = manifest['names'][name]
                expected = manifest['transition_expectations'][canonical]
                metrics = parse_metrics(result.stderr)
                if (result.stdout != f'{canonical}|{expected["checksum"]}\n'
                        or len(metrics['work']) != 2 or metrics['work'][1] != expected['count']):
                    raise SystemExit(f'Observable lookup mismatch for {name}')
                observed[name] = dict(stdout=result.stdout, metrics=metrics)
            report['measurements'].append(dict(package=str(package), mode=mode,
                manifest_sha256=hashlib.sha256((package / 'manifest.json').read_bytes()).hexdigest(),
                builds=measurements, observed=observed))
            (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            print(f'Measured {package.name} {mode}: {measurements}', flush=True)
    print(f'Evidence: {work / "report.json"}', flush=True)


if __name__ == '__main__':
    main()
