#!/usr/bin/env python3
"""Replay independently authored DATE export fixtures without network data."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from roc_version import package_pin

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/date_export_checks"
ROC = os.environ.get("ROC", "roc")


def compare(output, case):
    if "error" in case:
        if output.strip() != case["error"]:
            raise ValueError(f"Wrong export error: {output!r} != {case['error']!r}")
    elif json.loads(output) != case["expected"]:
        raise ValueError(f"Wrong DATE export result for {case['input']}: {output!r}")


def run(command):
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True,
                            timeout=180)
    if result.returncode:
        raise SystemExit(f"Command failed: {command!r}\n{result.stdout}{result.stderr}")
    return result.stdout


def main():
    if run([ROC, "version"]).strip() != f"Roc compiler version {package_pin(ROOT)}":
        raise SystemExit("Set ROC to the compiler pinned by the package header")
    corpus = FIXTURES / "cases.jsonl"
    if hashlib.sha256(corpus.read_bytes()).hexdigest() != "a8144deb5fc5422ca6cabba7c17a31b7ad229ac29d0b05ed5dd28fb2a2c7647a":
        raise SystemExit("Unreviewed DATE export oracle change")
    cases = [json.loads(line) for line in corpus.read_text().splitlines()]
    for case in cases:
        if set(case) not in ({"input", "expected"}, {"input", "error"}):
            raise SystemExit("Malformed DATE export corpus")
    # Wrong semantic output and malformed/missing native output must fail the
    # same comparator used for replay, including optimized native execution.
    for output in ("", "null", "{}", "[]", "{broken", json.dumps({**cases[0]["expected"], "dates": []})):
        try:
            compare(output, cases[0])
        except (ValueError, TypeError):
            pass
        else:
            raise SystemExit("DATE export comparison failure control failed")
    try:
        compare("OutOfRange(\"wrong-field\")", cases[6])
    except ValueError:
        pass
    else:
        raise SystemExit("DATE export error failure control failed")
    temp = ROOT / ".roc-time-tmp"
    temp.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="date-export-", dir=temp) as directory:
        entry = str(FIXTURES / "main.roc")
        run([ROC, "check", entry])
        compare(run([ROC, entry, "--", "monthly"]), cases[0])
        for mode in ("dev", "speed"):
            binary = str(Path(directory) / mode)
            run([ROC, "build", entry, f"--opt={mode}", f"--output={binary}"])
            for case in cases:
                compare(run([binary, case["input"]]), case)
            try:
                compare(run([binary, "until"]), cases[0])
            except ValueError:
                pass
            else:
                raise SystemExit("Native DATE export failure control failed")
            print(f"PASS DATE export {mode}: {len(cases)} sourced/profile fixtures and failure controls")


if __name__ == "__main__":
    main()
