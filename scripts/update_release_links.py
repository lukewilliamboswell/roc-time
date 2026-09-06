#!/usr/bin/env python3
"""Advance README release links after published examples have been verified."""
import argparse
from pathlib import Path
import re
from docs import VERSION_RE


def update(source, version):
    if not VERSION_RE.fullmatch(version):
        raise ValueError('Expected a package SemVer')
    release = r'https://github\.com/lukewilliamboswell/roc-time/releases/(?:tag|download)/'
    docs = r'https://lukewilliamboswell\.github\.io/roc-time/'
    source = re.sub(r'(' + release + r')[^/\s)]+', lambda m: m[1] + version, source)
    source = re.sub(r'(' + docs + r')[0-9][^/\s)]+/', lambda m: m[1] + version + '/', source)
    source = re.sub(r'\*\*\[[^\]]+ is available\]', '**[' + version + ' is available]', source, count=1)
    return source


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--readme', type=Path, required=True)
    args = parser.parse_args()
    args.readme.write_text(update(args.readme.read_text(), args.version))
