#!/usr/bin/env python3
"""Generate a bounded, optional Roc zone-data package from pinned IANA inputs."""
import argparse
import bisect
import datetime as dt
import hashlib
import io
import json
from pathlib import Path
import platform
import sys
import subprocess
import zipfile
from zoneinfo import ZoneInfo
from zoneinfo._common import load_data
from zoneinfo._zoneinfo import _parse_tz_str, _TZStr

sys.dont_write_bytecode = True
from generate_zone_oracle import WHEEL_SHA256, WHEEL_URL, EPOCH, seconds

START = seconds(dt.datetime(1800, 1, 1, tzinfo=dt.UTC))
END = seconds(dt.datetime(2200, 1, 1, tzinfo=dt.UTC))
PROFILE = "iana-2025b-wheel-2025.2-posix-1800-2200-v1"


def table(raw):
    indices, times, offsets, _, _, footer = load_data(io.BytesIO(raw))
    if not footer:
        raise ValueError("Pinned profile requires an explicit future-rule footer")
    future = _parse_tz_str(footer.decode())
    changes = dict(zip(times, (offsets[i] for i in indices)))
    bounds = list(offsets)
    if isinstance(future, _TZStr):
        std = int(future.std.utcoff.total_seconds())
        dst = int(future.dst.utcoff.total_seconds())
        bounds.extend([std, dst])
        for year in range(1799, 2201):
            start, end = future.transitions(year)
            for t, offset in [(start - std, dst), (end - dst, std)]:
                if not times or t > times[-1]:
                    changes[t] = offset
    else:
        bounds.append(int(future.utcoff.total_seconds()))
    zone = ZoneInfo.from_file(io.BytesIO(raw))
    def reference(t):
        return int((EPOCH + dt.timedelta(seconds=t)).astimezone(zone).utcoffset().total_seconds())
    # All explicit history precedes footer-generated entries. TZif type zero
    # specifies the offset before the first transition (RFC 9636 section 3.2).
    initial = offsets[0] if times else reference(START)
    kept = []
    for t, offset in sorted(changes.items()):
        if t <= START:
            initial = offset
        elif t < END:
            kept.append((t, offset))
    ticks = [t for t, _ in kept]
    values = [initial] + [v for _, v in kept]
    probes = {START, END - 1}
    boundaries = [START] + ticks + [END]
    for a, b in zip(boundaries, boundaries[1:]):
        probes.update([a, b - 1, (a + b) // 2])
    # Monthly probes also exercise footer seasons independently of the generated
    # candidate list. This is differential evidence, not exhaustive proof.
    for year in range(1800, 2200):
        for month in range(1, 13):
            probes.add(seconds(dt.datetime(year, month, 15, tzinfo=dt.UTC)))
    for t in sorted(probes):
        actual = values[bisect.bisect_right(ticks, t)]
        expected = reference(t)
        if actual != expected:
            raise ValueError(f"Rule export mismatch at {t}: {actual} != {expected}")
    return initial, min(bounds), max(bounds), kept, len(probes)


def generate(wheel, output):
    if platform.python_implementation() != "CPython" or platform.python_version() != "3.14.3":
        raise SystemExit("Requires CPython 3.14.3 for pinned TZif/footer decoding")
    if hashlib.sha256(wheel.read_bytes()).hexdigest() != WHEEL_SHA256:
        raise SystemExit("Pinned wheel integrity mismatch")
    output.mkdir(parents=True, exist_ok=False)
    with zipfile.ZipFile(wheel) as archive:
        zi = archive.read("tzdata/zoneinfo/tzdata.zi")
        if not zi.startswith(b"# version 2025b\n"):
            raise ValueError("Wrong source version")
        links, canonical = {}, set()
        for line in zi.decode().splitlines():
            fields = line.split()
            if fields and fields[0] == "L": links[fields[2]] = fields[1]
            if fields and fields[0] == "Z": canonical.add(fields[1])
        def identity(name):
            seen = set()
            while name in links:
                if name in seen: raise ValueError("Alias cycle")
                seen.add(name)
                name = links[name]
            if name not in canonical: raise ValueError(f"No canonical identity: {name}")
            return name
        names, unique, checks = {}, {}, 0
        for entry in sorted(archive.namelist()):
            if not entry.startswith("tzdata/zoneinfo/") or entry.endswith("/"): continue
            raw = archive.read(entry)
            if not raw.startswith(b"TZif"): continue
            name = entry.removeprefix("tzdata/zoneinfo/")
            target = identity(name)
            if raw != archive.read("tzdata/zoneinfo/" + target):
                raise ValueError(f"Alias payload differs: {name}")
            if target not in unique:
                initial, minimum, maximum, transitions, count = table(raw)
                checks += count
                module = f"Zone{len(unique):03}"
                digest = hashlib.sha256(raw).hexdigest()
                transition_text = ', '.join(f'{{ second: {t}, offset: {v} }}' for t, v in transitions)
                data = f'''{{ schema: 1.U16, axis: "posix-seconds-1970", requested_name: requested, canonical_name: {json.dumps(target)}, source_version: "2025b", source_digest: "{digest}", profile: "{PROFILE}", future_handling: "expanded-through-validity", start_second: {START}.I64, end_second: {END}.I64, initial_offset: {initial}.I32, minimum_offset: {minimum}.I32, maximum_offset: {maximum}.I32, transitions: [{transition_text}] }}'''
                # The shared structural annotation keeps empty lists and numeric
                # literals stable without a dependency on nominal roc-time types.
                (output / f"{module}.roc").write_text(f'import DatabaseRecord\n{module} :: [].{{\n get : Str -> DatabaseRecord.Value\n get = |requested| {data}\n}}\n')
                unique[target] = module
            names[name] = unique[target]
        (output / 'DatabaseRecord.roc').write_text('''DatabaseRecord :: [].{
 Value : { schema : U16, axis : Str, requested_name : Str, canonical_name : Str, source_version : Str, source_digest : Str, profile : Str, future_handling : Str, start_second : I64, end_second : I64, initial_offset : I32, minimum_offset : I32, maximum_offset : I32, transitions : List({ second : I64, offset : I32 }) }
}
''')
        imports = ''.join(f'import {m}\n' for m in unique.values())
        cases = ''.join(f' {json.dumps(n)} => Ok({m}.get(name))\n' for n, m in names.items())
        (output / 'Database.roc').write_text(imports + 'Database :: [].{\n get = |name| match name {\n' + cases + ' _ => Err(UnknownZone(name))\n }\n}\n')
        (output / 'main.roc').write_text('package [Database] {}\n')
        for source, destination in [('LICENSE', 'LICENSE.txt'), ('licenses/LICENSE_APACHE', 'LICENSE_APACHE.txt')]:
            (output / destination).write_bytes(archive.read('tzdata-2025.2.dist-info/licenses/' + source))
    manifest = dict(profile=PROFILE, wheel_url=WHEEL_URL, wheel_sha256=WHEEL_SHA256,
                    generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    zi_sha256=hashlib.sha256(zi).hexdigest(), zone_names=len(names), canonical_zones=len(unique),
                    offset_comparisons=checks, start_second=START, end_second=END,
                    limitation="Offset-only finite profile; no abbreviation/DST-status API. Python footer expansion compared with C ZoneInfo using common pinned data; not an independent tzdb authority.")
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return names


def verify(output, names, roc):
    root = Path(__file__).resolve().parents[1]
    version = subprocess.check_output([roc, 'version'], text=True).strip()
    if version != 'Roc compiler version ' + (root / '.roc-version').read_text().strip():
        raise ValueError('Wrong Roc compiler')
    directory = output / 'verification'
    directory.mkdir()
    import os
    core = os.path.relpath(root / 'package/main.roc', directory)
    source = f'app [main!] {{ db: "../main.roc", time: "{core}" }}\nimport db.Database\nimport time.ZoneRules\nimport time.PosixBoundary\nimport time.FixedOffset\n'
    source += 'main! = |_args| {\n for name in ' + json.dumps(list(names)) + ' {\n data = Database.get(name)?\n rules = ZoneRules.from_database(data)?\n at = PosixBoundary.from_microseconds(data.start_second * 1000000)\n offset = ZoneRules.offset_at(rules, at)?\n if FixedOffset.to_seconds(offset) != data.initial_offset { return Err(WrongOffset) }\n }\n echo!("PASS generated database\\n")\n Ok({})\n}\n'
    (directory / 'main.roc').write_text(source)
    for command in [[roc, 'check', 'main.roc'], [roc, 'build', 'main.roc', '--output=verify']]:
        subprocess.run(command, cwd=directory, check=True, timeout=180)
    result = subprocess.run([str((directory / 'verify').resolve())], text=True, capture_output=True, check=True, timeout=180)
    if result.stdout != 'PASS generated database\n': raise ValueError(result.stdout)
    print(result.stdout.strip())


def summary(names, output):
    manifest = json.loads((output / 'manifest.json').read_text())
    checks = manifest['offset_comparisons']
    unique = range(manifest['canonical_zones'])
    print(f'Generated {len(names)} names, {len(unique)} canonical zones; {checks} offset comparisons; {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wheel', type=Path)
    parser.add_argument('output', type=Path, help='new directory for generated package')
    parser.add_argument('--verify-roc', help='pinned Roc executable; compile and run all names through the real adapter')
    args = parser.parse_args()
    names = generate(args.wheel, args.output)
    if args.verify_roc: verify(args.output, names, str(Path(args.verify_roc).resolve()))
    summary(names, args.output)
