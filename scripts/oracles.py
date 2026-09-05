#!/usr/bin/env python3
"""Replay independently generated Gregorian expectations through public Roc APIs."""
from __future__ import annotations

import argparse
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
import sys
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
    corpus = DRIVER / "Cases.roc"
    rows = []
    for case in cases:
        tag = "Forward" if case["operation"] == "forward" else "Inverse"
        inputs = ", ".join(case["input"])
        values = case["expected"]
        if values[0] == "error":
            expected = f"Failure({values[1]})"
        elif case["operation"] == "forward":
            expected = f"DayNumber({values[1]})"
        else:
            expected = f"DateFields({', '.join(values[1:])})"
        rows.append(f"\t\t{{ id: {case['id']}, input: {tag}({inputs}), expected: {expected} }}, # {case['evidence']}")
    corpus.write_text("# Generated by scripts/oracles.py --refresh; do not edit expectations by hand.\n"
                      "import GregorianOracle\nCases :: [].{\n"
                      "\tinputs : List(GregorianOracle.Case)\n\tinputs = [\n"
                      + "\n".join(rows) + "\n\t]\n}\n")
    manifest = {
        "version": 1, "profile": PROFILE, "corpus_sha256": digest(corpus),
        "generator_version": GENERATOR_VERSION, "generator_sha256": digest(Path(__file__)),
        "reference": "CPython 3.14.3 datetime", "seed": SEED,
        "command": "python3 scripts/oracles.py --refresh", "case_count": len(cases),
        "overlap_dates_verified": dt.date.max.toordinal(),
        "sources": [
            "https://docs.python.org/3.14/library/datetime.html#date-objects",
            "https://docs.python.org/3.14/library/calendar.html",
            "https://github.com/python/cpython/blob/v3.14.3/Modules/_datetimemodule.c",
            "https://github.com/python/cpython/blob/v3.14.3/LICENSE"],
        "license": "Reference runtime: PSF License; generated numerical observations, no implementation code copied",
        "independence": "Forward complete-year formula shared; inverse cycle decomposition differs from production search. Cycle extension outside years1..9999 is derived model evidence, not direct datetime support.",
    }
    (DATA / "gregorian-manifest.toml").write_text("\n".join(f"{key} = {json.dumps(value)}" for key, value in manifest.items()) + "\n")
    print(f"Refreshed {len(cases)} cases; verified {manifest['overlap_dates_verified']} shared-domain dates")


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


def replay() -> None:
    manifest = tomllib.loads((DATA / "gregorian-manifest.toml").read_text())
    if manifest["profile"] != PROFILE or manifest["version"] != 1:
        raise ValueError("Unsupported oracle profile")
    if manifest["corpus_sha256"] != digest(DRIVER / "Cases.roc"):
        raise ValueError("Generated oracle module integrity mismatch")
    count = manifest["case_count"]
    if not isinstance(count, int) or not 0 < count <= MAX_CASES:
        raise ValueError("Invalid generated oracle case count")
    roc = os.environ.get("ROC", "roc")
    if "/" in roc:
        roc = str(Path(roc).resolve())
    work = Path(os.environ.get("ROC_TIME_TMPDIR", ROOT / ".roc-time-tmp")).resolve() / "oracles"
    work.mkdir(parents=True, exist_ok=True)
    session = Path(tempfile.mkdtemp(prefix="gregorian-", dir=work))
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
    for source in DRIVER.glob("*.roc"):
        shutil.copyfile(source, session / source.name)
    root = session / "main.roc"
    root.write_text(root.read_text().replace('../../package/main.roc', os.path.relpath(ROOT / "package/main.roc", session)))
    started = time.monotonic()
    command([roc, "check", "main.roc"], session, "check")
    command([roc, "test", "main.roc"], session, "comparator-tests")
    binary = session / "oracle"
    command([roc, "build", "main.roc", f"--output={binary}"], session, "build")
    output = command([str(binary)], session, "run")
    if output != f"PASS {count} oracle cases\n":
        raise ValueError(f"Missing or malformed oracle completion: {output[:200]}")
    report = {"compiler": version, "host": platform.platform(), "backend": "native default roc build",
              "case_count": count, "seconds": time.monotonic() - started,
              "corpus_sha256": digest(DRIVER / "Cases.roc"),
              "driver_sha256": {p.name: digest(p) for p in DRIVER.glob('*.roc')},
              "package_sha256": {p.name: digest(p) for p in (ROOT / 'package').glob('*.roc')},
              "stage_timeout_seconds": 120, "stage_output_bytes": MAX_OUTPUT}
    (session / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS Gregorian oracle: {count} observations in {report['seconds']:.2f}s; evidence {session}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Explicitly regenerate reviewed external expectations")
    args = parser.parse_args()
    try:
        refresh() if args.refresh else replay()
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
