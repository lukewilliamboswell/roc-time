#!/usr/bin/env python3
"""Assemble authored guides and restored immutable API pages outside Git."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--api-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--roc', default=os.environ.get('ROC', 'roc'))
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise ValueError('Assembly requires a fresh output directory')
    output.mkdir(parents=True)
    builder = output.parent / (output.name + '-builder')
    subprocess.run([args.roc, 'build', str(ROOT / 'www/site/main.roc'), '--output=' + str(builder)], check=True)
    subprocess.run([str(builder), str(ROOT / 'www/site/content'), str(output)], check=True)
    subprocess.run([sys.executable, str(ROOT / 'www/site/verify.py'), str(output), '--api-root', str(args.api_root.resolve())], check=True)
    from docs import VERSION_RE
    for entry in args.api_root.iterdir():
        if entry.is_dir() and VERSION_RE.fullmatch(entry.name):
            shutil.copytree(entry, output / entry.name)
    if (output / 'site').exists():
        raise ValueError('Authored source leaked into deployment')
    print('Assembled authored guides and release API documentation')

if __name__ == '__main__':
    main()
