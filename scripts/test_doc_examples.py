#!/usr/bin/env python3
"""Compile and run every Roc code block in public module doc comments."""
from roc_version import package_pin
from pathlib import Path
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    roc = os.environ.get('ROC', 'roc')
    version = subprocess.check_output([roc, 'version'], text=True).strip()
    if version != 'Roc compiler version ' + package_pin(ROOT):
        raise SystemExit('Set ROC to the pinned compiler')
    imports = set()
    bodies = []
    count = 0
    for source in sorted((ROOT / 'package').glob('*.roc')):
        comments = '\n'.join(re.sub(r'^\s*## ?', '', line) for line in source.read_text().splitlines()
                             if re.match(r'^\s*##', line))
        for block in re.findall(r'^```roc\n(.*?)^```\s*$', comments, re.M | re.S):
            count += 1
            code = []
            for line in block.splitlines():
                if line.startswith('import '):
                    imports.add(line)
                else:
                    code.append(line)
            bodies.append(f'# Documentation example {count}: {source.name}\n' + '\n'.join(code))
    if not count:
        raise SystemExit('No documentation code examples found')
    work = ROOT / '.roc-time-tmp/doc-examples'
    work.mkdir(parents=True, exist_ok=True)
    entry = work / 'main.roc'
    entry.write_text('app [main!] { time: "../../package/main.roc" }\n'
                     + '\n'.join(sorted(imports)) + '\nmain! = |_| Ok({})\n\n'
                     + '\n\n'.join(bodies) + '\n')
    for command in ('check', 'test'):
        subprocess.run([roc, command, str(entry)], cwd=ROOT, check=True, timeout=120)
    print(f'PASS {count} documentation code examples from public module comments')


if __name__ == '__main__':
    main()
