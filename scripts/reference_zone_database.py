#!/usr/bin/env python3
"""Retained independent CPython TZif/footer model from generate_zone_database.py.

The original producer is revision 11b51ce, SHA256
10f8018797368cda661fd260e8bcc8c9715265a324763db2783f02f06c2685ad.
This module emits reference data only; Roc writes and verifies packages.
"""
import bisect
import datetime as dt
import hashlib
import io
import json
from pathlib import Path
import platform
import sys
import zipfile
from zoneinfo import ZoneInfo
from zoneinfo._common import load_data
from zoneinfo._zoneinfo import _parse_tz_str, _TZStr

sys.dont_write_bytecode = True
# Distribution releases are independent of the historical oracle corpora.
# Never refresh generate_zone_oracle.py's pins as a side effect of shipping data.
WHEEL_VERSION = "2026.5"
SOURCE_VERSION = "2026e"
WHEEL_SHA256 = "b683bd1b6659ddcd810ff02ad09ba821d4bf1065072805063eb35c49617905ac"
WHEEL_URL = "https://files.pythonhosted.org/packages/94/21/1e5995a1c920cce14e4bffae20c665ec10e7ed03ab25e006cd741092b718/tzdata-2026.5-py2.py3-none-any.whl"
SOURCE_REVISION = "039ef27cc5f062a2055cb67435d6d71adbefd27d"
EPOCH = dt.datetime(1970, 1, 1, tzinfo=dt.UTC)


def seconds(value):
    delta = value - EPOCH
    return delta.days * 86400 + delta.seconds

START = seconds(dt.datetime(1800, 1, 1, tzinfo=dt.UTC))
END = seconds(dt.datetime(2200, 1, 1, tzinfo=dt.UTC))
PROFILE = f"iana-{SOURCE_VERSION}-wheel-{WHEEL_VERSION}-posix-1800-2200-v1"


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


def validate_integrity(raw):
    if hashlib.sha256(raw).hexdigest() != WHEEL_SHA256:
        raise ValueError("Pinned wheel integrity mismatch")


def validate_source(archive):
    zi = archive.read("tzdata/zoneinfo/tzdata.zi")
    if (not zi.startswith(f"# version {SOURCE_VERSION}\n".encode())
            or f'IANA_VERSION = "{SOURCE_VERSION}"' not in archive.read("tzdata/__init__.py").decode()):
        raise ValueError("Wrong source version")
    return zi


def reference(wheel):
    if platform.python_implementation() != "CPython" or platform.python_version() != "3.14.3":
        raise ValueError("Requires CPython 3.14.3 for pinned TZif/footer decoding")
    if wheel.stat().st_size > 1048576:
        raise ValueError("Pinned wheel integrity mismatch")
    validate_integrity(wheel.read_bytes())
    with zipfile.ZipFile(wheel) as archive:
        zi = validate_source(archive)
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
        identities = []
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
                unique[target] = len(rows)
                rows.append(dict(canonical_name=target, sha256=digest, initial=initial,
                                 minimum=minimum, maximum=maximum,
                                 transitions=[dict(second=t, offset=v) for t, v in transitions]))
            names[name] = target
            identities.append(dict(name=name, index=unique[target]))
        licenses = []
        for source, destination in [('LICENSE', 'LICENSE.txt'), ('licenses/LICENSE_APACHE', 'LICENSE_APACHE.txt')]:
            licenses.append(dict(name=destination, bytes=list(archive.read(f'tzdata-{WHEEL_VERSION}.dist-info/licenses/' + source))))
    metadata = dict(profile=PROFILE, source_version=SOURCE_VERSION, source_revision=SOURCE_REVISION,
                    encoding="text-assets-v1", wheel_url=WHEEL_URL, wheel_sha256=WHEEL_SHA256,
                    zi_sha256=hashlib.sha256(zi).hexdigest(), zone_names=len(names), canonical_zones=len(unique),
                    offset_comparisons=checks, start_second=START, end_second=END,
                    transition_expectations=expectations, names=names,
                    limitation="Offset-only finite profile; no abbreviation/DST-status API. Python footer expansion compared with C ZoneInfo using common pinned data; not an independent tzdb authority.")
    return dict(metadata=metadata, rows=rows, identities=identities, licenses=licenses)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('usage: reference_zone_database.py WHEEL')
    print(json.dumps(reference(Path(sys.argv[1])), separators=(',', ':')))
