#!/usr/bin/env python3
"""Replay independently generated calendar and zone expectations through public Roc APIs."""
from __future__ import annotations

import argparse
import sys
sys.dont_write_bytecode = True
import oracle_replay
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil
import signal
import subprocess
import tempfile
import time
import tomllib

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "tests/oracles"
DRIVER = ROOT / "tests/oracle_gregorian"
PROFILE = "gregorian-i32-years-civil-day-1970-v1"
GENERATOR_VERSION = 1
SEED = 20260905
MAX_CASES = 4096
MAX_OUTPUT = 1024 * 1024


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def refresh() -> None:
    # Explicit refresh only. Normal replay does not invoke a reference library.
    if platform.python_implementation() != "CPython" or platform.python_version() != "3.14.3":
        raise SystemExit("Refresh requires CPython 3.14.3; update the reviewed pin deliberately")
    epoch = dt.date(1970, 1, 1).toordinal()
    base = dt.date(2000, 1, 1).toordinal()
    cycle = [(dt.date.fromordinal(base + n).year - 2000,
              dt.date.fromordinal(base + n).month,
              dt.date.fromordinal(base + n).day) for n in range(146097)]
    offsets = {fields: n for n, fields in enumerate(cycle)}

    def forward(y: int, m: int, d: int) -> int:
        era, remainder = divmod(y - 2000, 400)
        return base - epoch + era * 146097 + offsets[remainder, m, d]

    def inverse(number: int) -> tuple[int, int, int]:
        era, offset = divmod(number - (base - epoch), 146097)
        y, m, d = cycle[offset]
        return 2000 + era * 400 + y, m, d

    # Establish table/direct agreement over the complete shared date domain.
    for ordinal in range(1, dt.date.max.toordinal() + 1):
        date = dt.date.fromordinal(ordinal)
        fields = date.year, date.month, date.day
        assert forward(*fields) == ordinal - epoch
        assert inverse(ordinal - epoch) == fields
    cases: list[dict] = []

    def add(operation: str, inputs: list[int], expected: list[str], evidence: str) -> None:
        cases.append({"id": str(len(cases)), "operation": operation,
                      "input": [str(n) for n in inputs], "expected": expected,
                      "evidence": evidence})

    def pair(fields: tuple[int, int, int], evidence: str) -> None:
        y, m, d = fields
        if evidence == "datetime":
            number = dt.date(y, m, d).toordinal() - epoch
            back = dt.date.fromordinal(number + epoch)
            expected_fields = back.year, back.month, back.day
        else:
            number = forward(y, m, d)
            expected_fields = inverse(number)
        add("forward", [y, m, d], ["ok", str(number)], evidence)
        add("inverse", [number], ["ok", *(str(n) for n in expected_fields)], evidence)

    for year in [-2147483648, -400, -100, -1, 0, 1, 1582, 1900, 1970, 2000, 2100, 9999, 2147483647]:
        for month, day in [(1, 1), (2, 28), (3, 1), (12, 31)]:
            pair((year, month, day), "datetime" if 1 <= year <= 9999 else "cycle-model")
    for fields in [(0, 2, 29), (2000, 2, 29), (1969, 12, 31), (1582, 10, 4), (1582, 10, 15)]:
        pair(fields, "datetime" if fields[0] >= 1 else "cycle-model")
    # Contract errors are distinct from external-library range errors.
    for fields, error in [((-2147483649, 1, 1), "OutOfRange"), ((2147483648, 1, 1), "OutOfRange"),
                          ((1900, 2, 29), "InvalidDay"), ((2000, 0, 1), "InvalidMonth"),
                          ((2000, 13, 1), "InvalidMonth"), ((2000, 1, 0), "InvalidDay"),
                          ((2000, 4, 31), "InvalidDay"), ((2000, 255, 255), "InvalidMonth")]:
        add("forward", list(fields), ["error", error], "contract")
    for number in [forward(-2147483648, 1, 1) - 1, forward(2147483647, 12, 31) + 1, -(2**63), 2**63 - 1]:
        add("inverse", [number], ["error", "OutOfRange"], "contract")
    rng = random.Random(SEED)
    while len(cases) < MAX_CASES:
        if len(cases) % 4 == 0:
            date = dt.date.fromordinal(rng.randint(1, dt.date.max.toordinal()))
            pair((date.year, date.month, date.day), "datetime")
        else:
            pair(inverse(rng.randint(forward(-2147483648, 1, 1), forward(2147483647, 12, 31))), "cycle-model")
    assert len(cases) == MAX_CASES
    DATA.mkdir(parents=True, exist_ok=True)
    corpus = write_cases(cases, DRIVER, "GregorianOracle")
    manifest = {
        "version": 2, "corpus_format": "jsonl-v1", "profile": PROFILE, "corpus_sha256": digest(corpus),
        "generator_version": GENERATOR_VERSION, "generator_sha256": digest(Path(__file__)),
        "smoke_case_count": 128, "smoke_sha256": digest(corpus.parent.parent / ("oracle_" + corpus.stem) / "SmokeCases.roc"),
        "reference": "CPython 3.14.3 datetime", "seed": SEED,
        "command": "python3 scripts/oracles.py --refresh", "case_count": len(cases),
        "overlap_dates_verified": dt.date.max.toordinal(),
        "sources": [
            "https://docs.python.org/3.14/library/datetime.html#date-objects",
            "https://docs.python.org/3.14/library/calendar.html",
            "https://github.com/python/cpython/blob/v3.14.3/Modules/_datetimemodule.c",
            "https://github.com/python/cpython/blob/v3.14.3/LICENSE"],
        "license": "Reference runtime: PSF License; generated numerical observations, no implementation code copied",
        "independence": "A January-based table enumerated with CPython datetime supplies both directions; production uses arithmetic rather than this table. Cycle extension outside years1..9999 is derived model evidence, not direct datetime support.",
    }
    (DATA / "gregorian-manifest.toml").write_text("\n".join(f"{key} = {json.dumps(value)}" for key, value in manifest.items()) + "\n")
    print(f"Refreshed {len(cases)} cases; verified {manifest['overlap_dates_verified']} shared-domain dates")


def refresh_julian() -> None:
    # Adapted from Howard Hinnant, 2021-09-01, Julian calendar section at
    # https://howardhinnant.github.io/date_algorithms.html . Formulas explicitly
    # donated to the public domain in the source's Summary. March-based eras
    # differ from production January counting and bounded inverse search.
    def forward(y: int, m: int, d: int) -> int:
        y -= m <= 2
        era, yoe = divmod(y, 4)
        doy = (153 * (m - 3 if m > 2 else m + 9) + 2) // 5 + d - 1
        return era * 1461 + yoe * 365 + doy - 719470

    def inverse(number: int) -> tuple[int, int, int]:
        era, doe = divmod(number + 719470, 1461)
        yoe = (doe - doe // 1460) // 365
        y = yoe + era * 4
        doy = doe - 365 * yoe
        mp = (5 * doy + 2) // 153
        d = doy - (153 * mp + 2) // 5 + 1
        m = mp + (3 if mp < 10 else -9)
        return y + (m <= 2), m, d

    assert forward(1582, 10, 5) == (dt.date(1582, 10, 15) - dt.date(1970, 1, 1)).days
    cases = []
    def add(op, inputs, expected, evidence):
        cases.append({"id": str(len(cases)), "operation": op,
                      "input": [str(n) for n in inputs], "expected": expected, "evidence": evidence})
    def pair(fields):
        number = forward(*fields)
        assert inverse(number) == fields
        add("forward", fields, ["ok", str(number)], "hinnant-julian")
        add("inverse", [number], ["ok", *(str(n) for n in fields)], "hinnant-julian")
    for year in [-2147483648, -400, -4, -1, 0, 1, 1582, 1900, 1969, 1970, 2000, 2147483647]:
        for month, day in [(1, 1), (2, 28), (3, 1), (12, 31)]:
            pair((year, month, day))
    for fields in [(0, 2, 29), (1900, 2, 29), (1582, 10, 5), (1969, 12, 19)]:
        pair(fields)
    for fields, error in [((1901, 2, 29), "InvalidDay"), ((0, 0, 1), "InvalidMonth"),
                          ((0, 1, 0), "InvalidDay"), ((2147483648, 1, 1), "OutOfRange")]:
        add("forward", fields, ["error", error], "contract")
    for number in [-784369121963, 784367682902, -(2**63), 2**63 - 1]:
        add("inverse", [number], ["error", "OutOfRange"], "contract")
    rng = random.Random(SEED)
    while len(cases) < MAX_CASES:
        pair(inverse(rng.randint(-784369121962, 784367682901)))
    corpus = write_cases(cases, ROOT / "tests/oracle_julian", "JulianOracle")
    manifest = {
        "version": 2, "corpus_format": "jsonl-v1", "profile": PROFILE.replace("gregorian", "julian"),
        "case_count": len(cases), "corpus_sha256": digest(corpus),
        "generator_version": GENERATOR_VERSION, "generator_sha256": digest(Path(__file__)),
        "smoke_case_count": 128, "smoke_sha256": digest(corpus.parent.parent / ("oracle_" + corpus.stem) / "SmokeCases.roc"),
        "reference": "Howard Hinnant date algorithms 2021-09-01, Julian section",
        "sources": ["https://howardhinnant.github.io/date_algorithms.html",
                    "https://aa.usno.navy.mil/faq/calendars"],
        "license": "Hinnant formulas donated to public domain; attribution retained in generator",
        "seed": SEED, "command": "python3 scripts/oracles.py --refresh",
        "runtime": platform.python_implementation() + " " + platform.python_version(),
        "independence": "March-based four-year era formulas vs production January-based counting and binary search. Shared proleptic conventions; independently sourced reform equivalence anchors epoch.",
    }
    (DATA / "julian-manifest.toml").write_text("\n".join(f"{key} = {json.dumps(value)}" for key, value in manifest.items()) + "\n")
    print(f"Refreshed {len(cases)} Julian observations from attributed reference formulas")


def write_cases(cases: list[dict], driver: Path, oracle: str) -> Path:
    corpus = DATA / (driver.name.removeprefix("oracle_") + ".jsonl")
    corpus.write_text("".join(json.dumps(case, sort_keys=True, separators=(",", ":")) + "\n" for case in cases))
    # A bounded interpreter sample retains endpoint/error-path coverage without
    # compiling the full, independently replayable corpus into either fixture.
    rows = []
    for case in cases[:128]:
        operation = "Forward" if case["operation"] == "forward" else "Inverse"
        values = case["expected"]
        tag = "Failure" if values[0] == "error" else ("DayNumber" if operation == "Forward" else "DateFields")
        rows.append(f"        {{ id: {case['id']}, input: {operation}({', '.join(case['input'])}), expected: {tag}({', '.join(values[1:])}) }},")
    (driver / "SmokeCases.roc").write_text("# Generated interpreter sample; full expectations live in tests/oracles/*.jsonl.\n"
        + f"import {oracle}\nSmokeCases :: [].{{\n    inputs : List({oracle}.Case)\n    inputs = [\n" + "\n".join(rows) + "\n    ]\n}\n")
    return corpus


def command(args: list[str], cwd: Path, label: str) -> str:
    # Disk-backed bounded output avoids unbounded communicate() memory retention.
    stdout = cwd / f"{label}.stdout"
    stderr = cwd / f"{label}.stderr"
    with stdout.open("wb") as out, stderr.open("wb") as err:
        proc = subprocess.Popen(args, cwd=cwd, stdout=out, stderr=err, start_new_session=True)
        deadline = time.monotonic() + 120
        try:
            while proc.poll() is None:
                if time.monotonic() > deadline or stdout.stat().st_size + stderr.stat().st_size > MAX_OUTPUT:
                    raise ValueError(f"Oracle {label} exceeded time/output budget")
                time.sleep(0.02)
        except BaseException:
            if os.name == "posix":
                os.killpg(proc.pid, signal.SIGKILL)
            else:
                proc.kill()
            proc.wait()
            raise
    if proc.returncode != 0:
        raise ValueError(f"Oracle {label} failed ({proc.returncode}); inspect {stderr}: {stderr.read_text()[:2000]}")
    if stdout.stat().st_size + stderr.stat().st_size > MAX_OUTPUT:
        raise ValueError(f"Oracle {label} exceeded output budget")
    return stdout.read_text()


def replay(name: str, workers: int = 4) -> None:
    driver = ROOT / f"tests/oracle_{name}"
    manifest = tomllib.loads((DATA / f"{name}-manifest.toml").read_text())
    expected_profile = {"zones": "zones-tzdata-2025b-v2", "calendar_pattern": "gregorian-calendar-patterns-v1", "rfc_date": "rfc5545-date-values-v1", "rfc_timed": "rfc5545-timed-values-v1"}.get(name, PROFILE.replace("gregorian", name))
    if manifest["profile"] != expected_profile or manifest["version"] != 2 or manifest["corpus_format"] != "jsonl-v1":
        raise ValueError("Unsupported oracle profile")
    corpus = DATA / f"{name}.jsonl"
    if manifest["corpus_sha256"] != digest(corpus):
        raise ValueError("Oracle JSONL integrity mismatch")
    smoke_path = driver / ("Cases.roc" if name == "zones" else "SmokeCases.roc")
    if manifest["smoke_sha256"] != digest(smoke_path):
        raise ValueError("Oracle interpreter sample integrity mismatch")
    count = manifest["case_count"]
    cases = oracle_replay.load_cases(corpus, count)
    if name == "zones":
        oracle_replay.validate_zone_cases(cases)
    elif name == "calendar_pattern":
        oracle_replay.validate_pattern_cases(cases)
        if manifest['generator_sha256'] != digest(ROOT / 'scripts/generate_pattern_oracle.py'):
            raise ValueError('Pattern generator changed: refresh the reviewed corpus')
        gaps = DATA / 'calendar_pattern-reference-gaps.jsonl'
        if manifest['reference_gap_sha256'] != digest(gaps) or len(gaps.read_text().splitlines()) != manifest['reference_gap_count']:
            raise ValueError('Pattern reference-gap evidence changed')
    elif name == "rfc_date":
        oracle_replay.validate_rfc_date_cases(cases)
        if manifest['generator_sha256'] != digest(ROOT / 'scripts/generate_rfc_date_oracle.py'):
            raise ValueError('RFC date generator changed: refresh the reviewed corpus')
    elif name == "rfc_timed":
        oracle_replay.validate_rfc_timed_cases(cases)
        if manifest['generator_sha256'] != digest(ROOT / 'scripts/generate_rfc_timed_oracle.py'):
            raise ValueError('RFC timed generator changed: refresh the reviewed corpus')
    else:
        oracle_replay.validate_calendar_cases(cases)
    roc = os.environ.get("ROC", "roc")
    if "/" in roc:
        roc = str(Path(roc).resolve())
    work = Path(os.environ.get("ROC_TIME_TMPDIR", ROOT / ".roc-time-tmp")).resolve() / "oracles"
    work.mkdir(parents=True, exist_ok=True)
    session = Path(tempfile.mkdtemp(prefix=f"{name}-", dir=work))
    oracle_replay.self_check(session)
    try:
        command([sys.executable, "-c", "raise SystemExit(7)"], session, "failure-control")
    except ValueError as error:
        if "failed (7)" not in str(error):
            raise
    else:
        raise ValueError("Oracle command gate accepted a failing driver")
    version = command([roc, "version"], session, "version").strip()
    if version != "Roc compiler version " + (ROOT / ".roc-version").read_text().strip():
        raise ValueError(f"Wrong oracle compiler: {version}")
    for source in driver.rglob("*.roc"):
        destination = session / source.relative_to(driver)
        destination.parent.mkdir(parents=True, exist_ok=True)
        text = source.read_text()
        # Rewrite only declared external package roots; internal relative module
        # imports retain their directory layout.
        import re
        text = re.sub(r'"(?:\.\./)+package/main\.roc"', json.dumps(os.path.relpath(ROOT / "package/main.roc", destination.parent)), text)
        text = re.sub(r'"(?:\.\./)+platform/main\.roc"', json.dumps(os.path.relpath(ROOT / "tests/platform/main.roc", destination.parent)), text)
        destination.write_text(text)
    started = time.monotonic()
    command([roc, "check", "main.roc"], session, "check")
    command([roc, "test", "main.roc"], session, "comparator-tests")
    interpreted = command([roc, "main.roc"], session, "interpret")
    smoke_output = f"PASS {manifest['smoke_case_count']} oracle cases\n"
    if interpreted != smoke_output:
        raise ValueError(f"Missing or malformed interpreted oracle smoke: {interpreted[:200]}")
    binary = session / "oracle"
    command([roc, "check", "native/main.roc"], session, "native-check")
    command([roc, "build", "native/main.roc", "--debug", f"--output={binary}"], session, "build")
    oracle_replay.fixture_controls(binary, cases[0], session)
    results = oracle_replay.replay_cases(binary, cases, session, workers)
    report = {"compiler": version, "host": platform.platform(), "backend": "native default optimization with --debug; fixed interpreter smoke",
              "case_count": count, "workers": workers, "seconds": time.monotonic() - started,
              "corpus_sha256": digest(corpus),
              "driver_sha256": {str(p.relative_to(driver)): digest(p) for p in driver.rglob('*.roc')},
              "package_sha256": {p.name: digest(p) for p in (ROOT / 'package').glob('*.roc')},
              "stage_timeout_seconds": 120, "stage_output_bytes": MAX_OUTPUT,
              "case_timeout_seconds": oracle_replay.CASE_TIMEOUT, "case_output_bytes": oracle_replay.CASE_OUTPUT_BYTES,
              "allocation_count_range": [min(r["allocations"] for r in results), max(r["allocations"] for r in results)],
              "resource_scope": "whole fixture including argv parsing and observation formatting; not isolated temporal operation"}
    (session / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS {name} oracle: {count} JSONL observations in {report['seconds']:.2f}s; evidence {session}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Explicitly regenerate reviewed calendar expectations (zones use generate_zone_oracle.py)")
    parser.add_argument("--workers", type=int, default=4, help="Bounded native case workers (1..16)")
    parser.add_argument("--oracle", choices=("gregorian", "julian", "zones", "calendar_pattern", "rfc_date", "rfc_timed"), help="Replay one corpus")
    args = parser.parse_args()
    try:
        if args.refresh:
            refresh()
            refresh_julian()
        else:
            import fixture_platform
            fixture_platform.build_host()
            for name in ((args.oracle,) if args.oracle else ("gregorian", "julian", "zones", "calendar_pattern", "rfc_date", "rfc_timed")):
                replay(name, args.workers)
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
