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
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

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
    corpus = DATA / "gregorian.json"
    corpus.write_text(json.dumps({"version": 1, "profile": PROFILE, "cases": cases}, indent=2) + "\n")
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
    (DATA / "gregorian-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Refreshed {len(cases)} cases; verified {manifest['overlap_dates_verified']} shared-domain dates")


def load_cases() -> list[dict]:
    manifest = json.loads((DATA / "gregorian-manifest.json").read_text())
    if manifest["corpus_sha256"] != digest(DATA / "gregorian.json"):
        raise ValueError("Gregorian corpus integrity mismatch")
    corpus = json.loads((DATA / "gregorian.json").read_text())
    if corpus["version"] != 1 or corpus["profile"] != PROFILE:
        raise ValueError("Unsupported oracle corpus profile")
    cases = corpus["cases"]
    if not 0 < len(cases) <= MAX_CASES or len(cases) != manifest["case_count"]:
        raise ValueError("Invalid oracle case count")
    for index, case in enumerate(cases):
        if case["id"] != str(index) or case["operation"] not in ("forward", "inverse"):
            raise ValueError(f"Invalid oracle case identity: {index}")
        expected_len = 3 if case["operation"] == "forward" else 1
        if len(case["input"]) != expected_len:
            raise ValueError(f"Invalid input arity: {index}")
        for field, value in enumerate(case["input"]):
            if not isinstance(value, str) or not re.fullmatch(r"-?(0|[1-9][0-9]*)", value):
                raise ValueError(f"Invalid numeric literal: {index}")
            lo, hi = (0, 255) if field > 0 else (-(2**63), 2**63 - 1)
            if not lo <= int(value) <= hi:
                raise ValueError(f"Input outside static type: {index}")
        expected = case["expected"]
        if not expected or expected[0] not in ("ok", "error"):
            raise ValueError(f"Invalid expectation: {index}")
        if expected[0] == "error":
            if len(expected) != 2 or expected[1] not in ("OutOfRange", "InvalidMonth", "InvalidDay"):
                raise ValueError(f"Invalid error expectation: {index}")
        else:
            arity = 2 if case["operation"] == "forward" else 4
            if len(expected) != arity or any(not isinstance(n, str) or not re.fullmatch(r"-?(0|[1-9][0-9]*)", n) for n in expected[1:]):
                raise ValueError(f"Invalid success expectation: {index}")
    return cases


def compare(cases: list[dict], output: str) -> None:
    expected = {case["id"]: case["expected"] for case in cases}
    seen = set()
    for line in output.splitlines():
        fields = line.split("|")
        identity = fields[0]
        if identity not in expected or identity in seen:
            raise ValueError(f"Unexpected or duplicate oracle result: {identity!r}")
        seen.add(identity)
        if fields[1:] != expected[identity]:
            raise ValueError(f"Oracle mismatch case {identity}: expected {expected[identity]}, got {fields[1:]}")
    if seen != expected.keys():
        raise ValueError(f"Missing oracle results: {sorted(expected.keys() - seen)[:8]}")


def self_check() -> None:
    cases = [{"id": "0", "expected": ["ok", "0"]}, {"id": "1", "expected": ["ok", "2000", "2", "29"]}]
    good = "0|ok|0\n1|ok|2000|2|29\n"
    compare(cases, good)
    for bad in [good.replace("0|ok|0", "0|ok|1"), good.splitlines()[0], good + good,
                "malformed", good.replace("|29", "|28"), ""]:
        try:
            compare(cases, bad)
        except ValueError:
            continue
        raise ValueError("Oracle comparator accepted deliberately corrupt results")


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
    self_check()
    cases = load_cases()
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
    literals = []
    for case in cases:
        tag = "Forward" if case["operation"] == "forward" else "Inverse"
        literals.append(f"{tag}({case['id']}, {', '.join(case['input'])})")
    (session / "Cases.roc").write_text("import GregorianOracle\nCases :: [].{\ninputs : List(GregorianOracle)\ninputs = [\n" + ",\n".join(literals) + "\n]\n}\n")
    started = time.monotonic()
    command([roc, "check", "main.roc"], session, "check")
    binary = session / "oracle"
    command([roc, "build", "main.roc", f"--output={binary}"], session, "build")
    compare(cases, command([str(binary)], session, "run"))
    report = {"compiler": version, "host": platform.platform(), "backend": "native default roc build",
              "case_count": len(cases), "seconds": time.monotonic() - started,
              "corpus_sha256": digest(DATA / "gregorian.json"),
              "driver_sha256": {p.name: digest(p) for p in DRIVER.glob('*.roc')},
              "package_sha256": {p.name: digest(p) for p in (ROOT / 'package').glob('*.roc')},
              "stage_timeout_seconds": 120, "stage_output_bytes": MAX_OUTPUT}
    (session / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS Gregorian oracle: {len(cases)} observations in {report['seconds']:.2f}s; evidence {session}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Explicitly regenerate reviewed external expectations")
    args = parser.parse_args()
    try:
        refresh() if args.refresh else replay()
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error)) from error
