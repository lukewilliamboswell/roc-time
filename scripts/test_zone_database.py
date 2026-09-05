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

ROOT = Path(__file__).resolve().parents[1]


def main():
    package = ROOT / 'tzdb/package'
    manifest = json.loads((package / 'manifest.json').read_text())
    generator = ROOT / 'scripts/generate_zone_database.py'
    if hashlib.sha256(generator.read_bytes()).hexdigest() != manifest['generator_sha256']:
        raise SystemExit('Zone generator changed: regenerate and review the committed pack')
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


if __name__ == '__main__':
    main()
