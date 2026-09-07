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
from roc_version import package_pin, read_pin
from generate_zone_oracle import WHEEL_SHA256, WHEEL_URL, EPOCH, seconds

START = seconds(dt.datetime(1800, 1, 1, tzinfo=dt.UTC))
END = seconds(dt.datetime(2200, 1, 1, tzinfo=dt.UTC))
PROFILE = "iana-2025b-wheel-2025.2-posix-1800-2200-v1"


def package_header(compiler):
    # Compiler requirements change independently of the pinned IANA data pack.
    return f'package [Database] {{ roc: "{compiler}" }}\n'


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
        rows = []
        expectations = {}
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
                expectations[target] = dict(count=len(transitions), checksum=sum((i + 1) * (t + v) for i, (t, v) in enumerate(transitions)))
                digest = hashlib.sha256(raw).hexdigest()
                # Stable canonical ordering and plain data keep Roc module identity
                # independent of the number of zones in a release.
                unique[target] = len(rows)
                rows.append("\t".join([target, digest, str(initial), str(minimum), str(maximum),
                                        ";".join(f"{t},{v}" for t, v in transitions) or "-"]))
            names[name] = target
        header = f"roc-time-tzdb-v1\t2025b\t{PROFILE}\t{START}\t{END}"
        (output / 'zones.txt').write_text(header + "\n" + "\n".join(rows) + "\n")
        (output / 'names.txt').write_text("".join(f"{name}\t{unique[target]}\n" for name, target in names.items()))
        implementation = Path(__file__).resolve().parents[1] / 'tzdb/Database.roc'
        (output / 'Database.roc').write_bytes(implementation.read_bytes())
        (output / 'main.roc').write_text(package_header(read_pin(implementation.parents[1] / 'package/main.roc')))
        for source, destination in [('LICENSE', 'LICENSE.txt'), ('licenses/LICENSE_APACHE', 'LICENSE_APACHE.txt')]:
            (output / destination).write_bytes(archive.read('tzdata-2025.2.dist-info/licenses/' + source))
    manifest = dict(profile=PROFILE, source_version="2025b", encoding="text-assets-v1", wheel_url=WHEEL_URL, wheel_sha256=WHEEL_SHA256,
                    generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    zi_sha256=hashlib.sha256(zi).hexdigest(), zone_names=len(names), canonical_zones=len(unique),
                    offset_comparisons=checks, start_second=START, end_second=END,
                    transition_expectations=expectations,
                    names=names,
                    files={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.iterdir()) if p.is_file() and p.name != 'main.roc'},
                    limitation="Offset-only finite profile; no abbreviation/DST-status API. Python footer expansion compared with C ZoneInfo using common pinned data; not an independent tzdb authority.")
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return names


def verify(output, names, roc):
    root = Path(__file__).resolve().parents[1]
    version = subprocess.check_output([roc, 'version'], text=True).strip()
    if version != 'Roc compiler version ' + package_pin(root):
        raise ValueError('Wrong Roc compiler')
    directory = output / 'verification'
    directory.mkdir()
    import os
    core = os.path.relpath(root / 'package/main.roc', directory)
    source = f'app [main!] {{ db: "../main.roc", time: "{core}" }}\nimport db.Database\nimport time.ZoneRules\nimport time.PosixBoundary\nimport time.FixedOffset\n'
    source += 'main! = |_args| {\n for name in ' + json.dumps(list(names)) + ' {\n data = Database.get(name)?\n rules = ZoneRules.from_database(data)?\n at = PosixBoundary.from_microseconds(data.start_second * 1000000)\n offset = ZoneRules.offset_at(rules, at)?\n if FixedOffset.to_seconds(offset) != data.initial_offset { return Err(WrongOffset) }\n }\n echo!("PASS generated database\\n")\n Ok({})\n}\n'
    expectations = json.loads((output / 'manifest.json').read_text())['transition_expectations']
    cases = ''.join(f' {json.dumps(name)} => {{ count: {value["count"]}.U64, checksum: {value["checksum"]}.I64 }}\n' for name, value in expectations.items())
    verification = ' expected = match data.canonical_name {\n' + cases + ' _ => return Err(UnexpectedCanonicalName)\n }\n var $checksum = 0.I64\n var $index = 1.I64\n for transition in data.transitions {\n $checksum = $checksum + $index * (transition.second + transition.offset.to_i64())\n $index = $index + 1\n }\n if data.transitions.len() != expected.count or $checksum != expected.checksum { return Err(WrongTransitions) }\n'
    source = source.replace(' rules = ZoneRules.from_database(data)?', verification + ' rules = ZoneRules.from_database(data)?')
    transition_checks = ' var $previous = data.initial_offset\n for transition in data.transitions {\n at_transition = PosixBoundary.from_microseconds(transition.second * 1000000)\n before = PosixBoundary.from_microseconds(transition.second * 1000000 - 1)\n actual = ZoneRules.offset_at(rules, at_transition)?\n prior = ZoneRules.offset_at(rules, before)?\n if FixedOffset.to_seconds(actual) != transition.offset or FixedOffset.to_seconds(prior) != $previous { return Err(WrongTransitionBoundary) }\n $previous = transition.offset\n }\n'
    source = source.replace(' at = PosixBoundary', transition_checks + ' at = PosixBoundary')

    manifest = json.loads((output / 'manifest.json').read_text())
    metadata_check = (f' if data.schema != 1 or data.axis != "posix-seconds-1970" or data.requested_name != name '
                      f'or data.source_version != {json.dumps(manifest["source_version"])} '
                      f'or data.profile != {json.dumps(manifest["profile"])} '
                      f'or data.start_second != {manifest["start_second"]} '
                      f'or data.end_second != {manifest["end_second"]} '
                      f'or data.future_handling != "expanded-through-validity" {{ return Err(WrongMetadata) }}\n')
    source = source.replace(' expected = match', metadata_check + ' expected = match')

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
