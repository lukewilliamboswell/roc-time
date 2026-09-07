#!/usr/bin/env python3
"""Offline replay of sourced civil queries and an exhaustive native day walk."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from roc_version import package_pin

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/civil_query_checks"
ROC = os.environ.get("ROC", "roc")


def parse_result(output):
    fields = output.strip().split(",")
    if len(fields) != 5 or any(not field.lstrip("-").isascii() or not field.lstrip("-").isdigit() for field in fields):
        raise ValueError(f"Malformed native query result: {output!r}")
    return [int(field) for field in fields]


def compare(output, expected):
    if parse_result(output) != expected:
        raise ValueError(f"Civil query mismatch: {output!r} != {expected}")


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True,
                          timeout=180, check=True, **kwargs).stdout


def main():
    if run([ROC, "version"]).strip() != f"Roc compiler version {package_pin(ROOT)}":
        raise SystemExit("Set ROC to the compiler pinned by the package header")
    for name, digest in {
        "reference.py": "dbe36a1f7fc7cf65f4554285adaee50e5d2119c114a58316f95796f47ad6ba44",
        "cases.jsonl": "5cd11c1503af724c9ffa6dff9277f0454d0a6d381cabd76cf8a2c91b96042ba0",
    }.items():
        if hashlib.sha256((FIXTURES / name).read_bytes()).hexdigest() != digest:
            raise SystemExit(f"Unreviewed civil query oracle change: {name}")
    cases = [json.loads(line) for line in (FIXTURES / "cases.jsonl").read_text().splitlines()]
    for case in cases:
        if set(case) != {"input", "origin", "reference_year", "expected"} or case["origin"] not in ("direct-python", "cycle-extension") or len(case["expected"]) != 5 or any(type(value) is not int for value in case["expected"]):
            raise SystemExit("Malformed civil query corpus")
    compare("6,1,1999,52,6\n", [6, 1, 1999, 52, 6])
    for output in ("", "null", "6,1,1999,52", "6,1,1999,52,6,7", "6,1,1999,52,x", "6,1,1999,53,6"):
        try:
            compare(output, [6, 1, 1999, 52, 6])
        except ValueError:
            pass
        else:
            raise SystemExit("Broken oracle failure control")
    temp = ROOT / ".roc-time-tmp"
    temp.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="civil-query-oracle-", dir=temp) as directory:
        entry = str(FIXTURES / "main.roc")
        run([ROC, "check", entry])
        # Interpreter smoke complements the exhaustive native runs.
        compare(run([ROC, entry, "--", cases[0]["input"]]), cases[0]["expected"])
        for mode in ("dev", "speed"):
            binary = str(Path(directory) / mode)
            run([ROC, "build", entry, f"--opt={mode}", f"--output={binary}"])
            def replay(case):
                return run([binary, case["input"]])
            with ThreadPoolExecutor(max_workers=4) as pool:
                for case, output in zip(cases, pool.map(replay, cases), strict=True):
                    compare(output, case["expected"])
            if run([binary, "cycle"]) != "PASS 146097 Gregorian days\n":
                raise SystemExit("Missing exhaustive cycle result")
            failure = subprocess.run([binary, "cycle", "wrong-week"], cwd=ROOT,
                                     text=True, capture_output=True, timeout=30)
            if failure.returncode == 0 or "Gregorian query differs from independent day walk" not in failure.stdout + failure.stderr:
                raise SystemExit("Optimized day-walk failure control was not observed")
            print(f"PASS civil queries {mode}: {len(cases)} sourced/derived fixtures, 146097-day independent walk, failure controls")


if __name__ == "__main__":
    main()
