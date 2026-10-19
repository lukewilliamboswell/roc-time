#!/usr/bin/env python3
"""Verify committed zone data offline and exercise every name through the core."""
import hashlib
import io
import zipfile
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from generate_zone_database import (verify, package_header, validate_integrity, validate_source,
                                    WHEEL_SHA256, WHEEL_URL, SOURCE_VERSION, SOURCE_REVISION, PROFILE)
from fixture_platform import build_host
from oracle_replay import parse_metrics

ROOT = Path(__file__).resolve().parents[1]


def validate_header(source):
    if source != package_header():
        raise ValueError("Zone package must expose only Database and pin no compiler")


def check_integrity(package):
    manifest = json.loads((package / 'manifest.json').read_text())
    for field, expected_value in dict(wheel_sha256=WHEEL_SHA256, wheel_url=WHEEL_URL,
                                     source_version=SOURCE_VERSION, source_revision=SOURCE_REVISION,
                                     profile=PROFILE).items():
        if manifest[field] != expected_value:
            raise SystemExit(f'Zone source pin mismatch: {field}')
    generator = ROOT / 'scripts/generate_zone_database.py'
    if hashlib.sha256(generator.read_bytes()).hexdigest() != manifest['generator_sha256']:
        raise SystemExit('Zone generator changed: regenerate and review the committed pack')
    if (ROOT / 'tzdb/Database.roc').read_bytes() != (package / 'Database.roc').read_bytes():
        raise SystemExit('Zone implementation changed: regenerate the distributable pack')
    if 'main.roc' in manifest['files']:
        raise SystemExit('Compiler header must not be part of the generated-data digests')
    validate_header((package / 'main.roc').read_text())
    expected = set(manifest['files']) | {'manifest.json', 'main.roc'}
    if {p.name for p in package.iterdir()} != expected:
        raise SystemExit('Unexpected or missing generated package files')
    for name, digest in manifest['files'].items():
        if hashlib.sha256((package / name).read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Zone artifact integrity mismatch: {name}')
    return manifest


def header_controls():
    # The header is outside the generated-data manifest, so constrain it
    # independently: no compiler pin, extra exports or dependencies can hide there.
    validate_header(package_header())
    for malformed in ('package [Database] { roc: "nightly-2026-09-05-b195f5b" }\n',
                      package_header().replace('[Database]', '[Database, Extra]'),
                      package_header() + 'extra = 1\n',
                      'package [Database] { other: "../x/main.roc" }\n'):
        try:
            validate_header(malformed)
        except ValueError:
            pass
        else:
            raise AssertionError('Invalid zone package header was accepted')


def source_controls():
    try:
        validate_integrity(b'corrupted wheel')
    except ValueError as error:
        assert str(error) == 'Pinned wheel integrity mismatch'
    else:
        raise AssertionError('Corrupt wheel accepted')
    # Reject a mismatched version in either independently embedded metadata file.
    for zi_version, module_version in [('2025b', SOURCE_VERSION), (SOURCE_VERSION, '2025b')]:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            archive.writestr('tzdata/zoneinfo/tzdata.zi', f'# version {zi_version}\n')
            archive.writestr('tzdata/__init__.py', f'IANA_VERSION = "{module_version}"\n')
        with zipfile.ZipFile(io.BytesIO(buffer.getvalue())) as archive:
            try:
                validate_source(archive)
            except ValueError as error:
                assert str(error) == 'Wrong source version'
            else:
                raise AssertionError('Wrong source version accepted')


def main():
    package = ROOT / 'tzdb/package'
    manifest = check_integrity(package)
    header_controls()
    source_controls()
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
        for command in [[roc, 'check', app], [roc, '--opt=interpreter', app], [roc, 'build', app, f'--output={binary}'], [str(binary)]]:
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
