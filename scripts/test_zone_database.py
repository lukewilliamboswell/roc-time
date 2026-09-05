#!/usr/bin/env python3
"""Verify committed zone data offline and exercise every name through the core."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from generate_zone_database import verify
from fixture_platform import build_host
from oracle_replay import parse_metrics

ROOT = Path(__file__).resolve().parents[1]


def main():
    package = ROOT / 'tzdb/package'
    manifest = json.loads((package / 'manifest.json').read_text())
    generator = ROOT / 'scripts/generate_zone_database.py'
    if hashlib.sha256(generator.read_bytes()).hexdigest() != manifest['generator_sha256']:
        raise SystemExit('Zone generator changed: regenerate and review the committed pack')
    if (ROOT / 'tzdb/Database.roc').read_bytes() != (package / 'Database.roc').read_bytes():
        raise SystemExit('Zone implementation changed: regenerate the distributable pack')
    expected = set(manifest['files']) | {'manifest.json'}
    if {p.name for p in package.iterdir()} != expected:
        raise SystemExit('Unexpected or missing generated package files')
    for name, digest in manifest['files'].items():
        if hashlib.sha256((package / name).read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Zone artifact integrity mismatch: {name}')
    roc = os.environ.get('ROC', 'roc')
    if '/' in roc or '\\' in roc: roc = str(Path(roc).resolve())
    temporary = ROOT / '.roc-time-tmp'
    temporary.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zone-replay-', dir=temporary) as directory:
        copied = Path(directory) / 'package'
        shutil.copytree(package, copied)
        verify(copied, manifest['names'], roc)
        app = 'tests/zone_database/main.roc'
        binary = Path(directory) / ('provider.exe' if os.name == 'nt' else 'provider')
        for command in [[roc, 'check', app], [roc, app], [roc, 'build', app, f'--output={binary}'], [str(binary)]]:
            subprocess.run(command, cwd=ROOT, check=True, timeout=180)
        target = build_host()
        source = 'tests/zone_database/resource/main.roc'
        for mode in ('dev', 'speed'):
            executable = Path(directory) / f'lookup-{mode}'
            subprocess.run([roc, 'build', source, f'--opt={mode}', '--debug',
                            f'--target={target}', f'--output={executable}', '--no-cache'],
                           cwd=ROOT, check=True, timeout=180)
            for name in ('Australia/Melbourne', 'US/Eastern', 'Pacific/Apia', 'Etc/UTC'):
                canonical = manifest['names'][name]
                expected = manifest['transition_expectations'][canonical]
                result = subprocess.run([str(executable), name], text=True, capture_output=True,
                                        check=True, timeout=10)
                if result.stdout != f'{canonical}|{expected["checksum"]}\n':
                    raise SystemExit(f'Zone resource fixture changed its observable result: {result.stdout}')
                metrics = parse_metrics(result.stderr)
                budget = 0 if mode == 'dev' else 1
                if (len(metrics['work']) != 2 or metrics['work'][0] > budget
                        or metrics['work'][1] != expected['count']
                        or [trace['mark'] for trace in metrics['traces']] != [1, 2]
                        or metrics['traces'][1]['allocations'] - metrics['traces'][0]['allocations'] != metrics['work'][0]):
                    raise SystemExit(f'Unexpected zone lookup metrics: {metrics}')
                # Host.assert! enforces the lookup allocation budget in both modes.
                # Keep full counter/trace output for the verification transcript.
                print(f'PASS {mode} lookup {name}: {result.stderr.strip()}', flush=True)


if __name__ == '__main__':
    main()
