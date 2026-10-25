#!/usr/bin/env python3
"""Restore the generated API documentation of every release for Pages.

The shared release workflow publishes roc-time-docs-<version>.zip, holding the
compiler-generated pages under <version>/. Releases up to 0.3.1 published the
same tree as roc-time-docs-<version>.tar.gz.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
from urllib.request import Request, urlopen
import zipfile

REPOSITORY = 'lukewilliamboswell/roc-time'
from docs import VERSION_RE as VERSION


def version(value: str) -> str:
    if not VERSION.fullmatch(value):
        raise ValueError(f'Invalid documentation version: {value}')
    return value


def asset_names(value: str) -> tuple[str, str]:
    """The current archive name, then the legacy one."""
    return f'roc-time-docs-{version(value)}.zip', f'roc-time-docs-{version(value)}.tar.gz'


def safe_entry(name: str, value: str, regular: bool) -> None:
    path = PurePosixPath(name)
    if ('\\' in name or path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != value or not regular):
        raise ValueError(f'Unsafe documentation archive entry: {name}')


def restore(archive_path: Path, value: str, output: Path) -> None:
    """Unpack <value>/ from a zip or legacy tarball into output/<value>, checking every entry first."""
    version(value)
    output.mkdir(parents=True, exist_ok=True)
    if (output / value).exists() or (output / value).is_symlink():
        raise ValueError(f'Documentation destination already exists: {output / value}')
    # Stage outside the destination tree; never extract links or follow an
    # existing directory symlink in the output. Callers use isolated output.
    with tempfile.TemporaryDirectory(prefix='docs-restore-', dir=output) as tmp:
        stage = Path(tmp)
        if archive_path.name.endswith('.zip'):
            with zipfile.ZipFile(archive_path) as archive:
                entries = archive.infolist()
                for entry in entries:
                    kind = (entry.external_attr >> 16) & 0o170000
                    safe_entry(entry.filename.rstrip('/'), value, kind in (0, 0o100000, 0o040000))
                if not any(entry.filename == f'{value}/index.html' for entry in entries):
                    raise ValueError(f'Archive lacks {value}/index.html')
                for entry in entries:
                    target = stage / entry.filename
                    if entry.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                        continue
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(entry) as source, target.open('wb') as destination:
                        shutil.copyfileobj(source, destination)
        else:
            with tarfile.open(archive_path, 'r:gz') as archive:
                members = archive.getmembers()
                for member in members:
                    safe_entry(member.name, value, member.isfile() or member.isdir())
                if not any(member.name == f'{value}/index.html' and member.isfile() for member in members):
                    raise ValueError(f'Archive lacks {value}/index.html')
                for member in members:
                    target = stage / member.name
                    if member.isdir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with archive.extractfile(member) as source, target.open('wb') as destination:
                            shutil.copyfileobj(source, destination)
        shutil.move(str(stage / value), str(output / value))


def github(endpoint: str):
    if os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN'):
        result = subprocess.run(['gh', 'api', endpoint], check=True, capture_output=True, text=True)
        return json.loads(result.stdout)
    request = Request('https://api.github.com/' + endpoint, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'roc-time-docs'})
    with urlopen(request, timeout=60) as response:
        return json.load(response)


def fetch(output: Path, allow_missing: str | None = None) -> None:
    page = 1
    while True:
        releases = github(f'repos/{REPOSITORY}/releases?per_page=100&page={page}')
        for release in releases:
            value = release['tag_name']
            if release['draft'] or not VERSION.fullmatch(value):
                continue
            assets = [item for item in release['assets'] if item['name'] in asset_names(value)]
            if not assets and value == allow_missing:
                continue
            if not assets:
                raise ValueError(f'Missing historical documentation asset for {value}')
            if len(assets) != 1:
                raise ValueError(f'Multiple documentation assets for {value}')
            asset = assets[0]
            expected_url = f'https://github.com/{REPOSITORY}/releases/download/{value}/{asset["name"]}'
            if asset['browser_download_url'] != expected_url:
                raise ValueError('Unexpected documentation asset URL')
            with tempfile.TemporaryDirectory(prefix='roc-docs-download-') as tmp:
                archive = Path(tmp) / asset['name']
                with urlopen(expected_url, timeout=60) as response, archive.open('wb') as target:
                    shutil.copyfileobj(response, target)
                digest = asset.get('digest')
                if digest != 'sha256:' + hashlib.sha256(archive.read_bytes()).hexdigest():
                    raise ValueError(f'Documentation digest mismatch for {value}')
                restore(archive, value, output)
            print(f'Restored release documentation for {value}')
        if len(releases) < 100:
            return
        page += 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    download = commands.add_parser('fetch')
    download.add_argument('--allow-missing', help='Only this current version may lack an asset')
    download.add_argument('--output', type=Path, required=True, help='New directory for restored versioned docs')
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Use a new output directory for fetched release docs')
    args.output.mkdir(parents=True)
    fetch(args.output, args.allow_missing)


if __name__ == '__main__':
    main()
