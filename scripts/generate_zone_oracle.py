#!/usr/bin/env python3
"""Generate typed zone expectations from a pinned tzdata wheel, never the host DB."""
import argparse
import datetime as dt
import hashlib
import io
import json
from pathlib import Path
import platform
import zipfile
from zoneinfo import ZoneInfo
from zoneinfo._common import load_data

ROOT = Path(__file__).resolve().parents[1]
WHEEL_SHA256 = "1a403fada01ff9221ca8044d701868fa132215d84beb92242d9acd2147f667a8"
WHEEL_URL = "https://files.pythonhosted.org/packages/5c/23/c7abc0ca0a1526a0774eca151daeb8de62ec457e77262b66b359c3c7679e/tzdata-2025.2-py2.py3-none-any.whl"
EPOCH = dt.datetime(1970, 1, 1, tzinfo=dt.UTC)
SCENARIOS = [
    ("Australia/Lord_Howe", (2024, 4, 7)),
    ("Australia/Lord_Howe", (2024, 10, 6)),
    ("Pacific/Apia", (2011, 12, 30)),
]


def seconds(value):
    delta = value - EPOCH
    return delta.days * 86400 + delta.seconds


def micros(value):
    return seconds(value) * 1000000 + value.microsecond


def generate(wheel):
    if platform.python_implementation() != "CPython" or platform.python_version() != "3.14.3":
        raise SystemExit("Generation requires CPython 3.14.3")
    if hashlib.sha256(wheel.read_bytes()).hexdigest() != WHEEL_SHA256:
        raise SystemExit("Pinned tzdata wheel integrity mismatch")
    output = ROOT / "tests/oracle_zones"
    output.mkdir(exist_ok=True)
    fixtures, cases, hashes = [], [], {}
    json_cases, smoke_keys = [], set()
    with zipfile.ZipFile(wheel) as archive:
        assert 'IANA_VERSION = "2025b"' in archive.read("tzdata/__init__.py").decode()
        for zone_index, (name, fields) in enumerate(SCENARIOS):
            raw = archive.read("tzdata/zoneinfo/" + name)
            hashes[name] = hashlib.sha256(raw).hexdigest()
            zone = ZoneInfo.from_file(io.BytesIO(raw), key=name)
            _, explicit_times, offsets, _, _, footer = load_data(io.BytesIO(raw))
            # These pinned footer offsets are included in the complete TZif type
            # range. This bound is not inferred from only the short test window.
            expected_footer = (b"<+1030>-10:30<+11>-11,M10.1.0,M4.1.0" if name.startswith("Australia") else b"<+13>-13")
            assert footer == expected_footer
            assert min(offsets) <= (37800 if name.startswith("Australia") else 46800) <= max(offsets)
            assert min(offsets) <= (39600 if name.startswith("Australia") else 46800) <= max(offsets)
            center = dt.datetime(*fields, tzinfo=dt.UTC)
            lower, upper = seconds(center - dt.timedelta(days=5)), seconds(center + dt.timedelta(days=5))

            def offset_at(t):
                return int((EPOCH + dt.timedelta(seconds=t)).astimezone(zone).utcoffset().total_seconds())

            # Include explicit TZif transitions directly, and find any footer
            # transitions via hourly brackets followed by integer bisection.
            transitions = {t for t in explicit_times if lower < t < upper}
            previous = lower
            for sample in range(lower + 3600, upper + 1, 3600):
                if offset_at(previous) != offset_at(sample):
                    lo, hi = previous, sample
                    old = offset_at(lo)
                    while hi - lo > 1:
                        mid = (lo + hi) // 2
                        if offset_at(mid) == old:
                            lo = mid
                        else:
                            hi = mid
                    if lower < hi < upper:
                        transitions.add(hi)
                previous = sample
            changes = [(t, offset_at(t)) for t in sorted(transitions)]
            # Exhaustively verify the exported step table throughout this finite
            # 10-day fixture. No assumption about unseen sub-hour transitions.
            index, current = 0, offset_at(lower)
            for t in range(lower, upper):
                while index < len(changes) and changes[index][0] <= t:
                    current = changes[index][1]
                    index += 1
                assert current == offset_at(t), (name, t)
            trans_text = ", ".join(f"{{ at: {t * 1000000}, offset: {offset} }}" for t, offset in changes)
            fixtures.append(f'{{ name: "{name}", source_digest: "{hashes[name]}", lower: {lower * 1000000}, upper: {upper * 1000000}, initial: {offset_at(lower)}, minimum: {min(offsets)}, maximum: {max(offsets)}, transitions: [{trans_text}] }}')
            for day_offset in [-1, 0, 1]:
                day = dt.datetime(*fields) + dt.timedelta(days=day_offset)
                for minute in range(0, 1440, 15):
                    for fraction in [0, 1, 999999]:
                        local = day + dt.timedelta(minutes=minute, microseconds=fraction)
                        candidates = set()
                        for fold in [0, 1]:
                            utc = local.replace(tzinfo=zone, fold=fold).astimezone(dt.UTC)
                            # Neither fold flag alone proves that a local time
                            # exists: validate by a UTC -> local round trip.
                            if utc.astimezone(zone).replace(tzinfo=None) == local:
                                candidates.add(micros(utc))
                        expected = ", ".join(map(str, sorted(candidates)))
                        json_cases.append({"id": str(len(json_cases)), "operation": "resolve",
                                           "input": [str(n) for n in [zone_index, local.year, local.month, local.day, local.hour, local.minute, local.second, local.microsecond]],
                                           "expected": ["ok", *map(str, sorted(candidates))], "evidence": "pinned-zoneinfo-roundtrip"})
                        smoke_key = (zone_index, len(candidates), fraction)
                        if smoke_key not in smoke_keys:
                            smoke_keys.add(smoke_key)
                            cases.append(f'{{ id: {len(cases)}, zone: {zone_index}, date: {{ year: {local.year}, month: {local.month}, day: {local.day} }}, clock: {{ hour: {local.hour}, minute: {local.minute}, second: {local.second}, microsecond: {local.microsecond} }}, expected: [{expected}] }}')
        for name in ["LICENSE", "licenses/LICENSE_APACHE"]:
            text = archive.read("tzdata-2025.2.dist-info/licenses/" + name)
            (ROOT / "tests/oracles" / ("tzdata-" + name.replace("/", "-") + ".txt")).write_bytes(text)
    text = "import ZoneOracle\n\n# Generated by scripts/generate_zone_oracle.py; pinned tzdata 2025.2 / IANA 2025b.\nCases :: [].{\n\tfixtures : List(ZoneOracle.Fixture)\n\tfixtures = [\n" + "".join("\t\t" + row + ",\n" for row in fixtures) + "\t]\n\tinputs : List(ZoneOracle.Case)\n\tinputs = [\n" + "".join("\t\t" + row + ",\n" for row in cases) + "\t]\n}\n"
    (output / "Cases.roc").write_text(text)
    corpus = ROOT / "tests/oracles/zones.jsonl"
    corpus.write_text(''.join(json.dumps(case, separators=(",", ":")) + "\n" for case in json_cases))
    manifest = dict(version=2, corpus_format="jsonl-v1", profile="zones-tzdata-2025b-v2", case_count=len(json_cases),
                    corpus_sha256=hashlib.sha256(corpus.read_bytes()).hexdigest(),
                    smoke_sha256=hashlib.sha256(text.encode()).hexdigest(), smoke_case_count=len(cases),
                    generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    wheel_url=WHEEL_URL, wheel_sha256=WHEEL_SHA256,
                    reference="CPython 3.14.3 ZoneInfo.from_file; tzdata 2025.2 (IANA 2025b)",
                    independence="CPython fold/UTC-roundtrip candidates vs Roc segment preimages; common pinned rule data. Synthetic enumeration remains separate evidence.",
                    limitation="Selected modern transition windows only; Python fold models at most two occurrences. Synthetic tests cover triple folds.")
    lines = [f"{key} = {json.dumps(value)}" for key, value in manifest.items()]
    lines.extend(f"tzif_{i}_sha256 = {json.dumps(value)}" for i, value in enumerate(hashes.values()))
    (ROOT / "tests/oracles/zones-manifest.toml").write_text("\n".join(lines) + "\n")
    print(f"Generated {len(json_cases)} JSONL zone cases and {len(cases)} typed smoke cases; checked every second of three 10-day rule fixtures")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wheel", type=Path)
    generate(parser.parse_args().wheel)
