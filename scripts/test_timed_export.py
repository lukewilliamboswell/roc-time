#!/usr/bin/env python3
"""Replay independent timed export fixtures, without network or host tzdata."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from roc_version import package_pin

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/timed_export_checks"
ROC = os.environ.get("ROC", "roc")


def compare(output, case):
    if "error" in case:
        if output.strip() != case["error"]:
            raise ValueError(f"Wrong error for {case['name']}: {output!r} != {case['error']!r}")
    elif json.loads(output) != case["expected"]:
        raise ValueError(f"Wrong timed export for {case['name']}: {output!r}")


def run(command):
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise SystemExit(f"Command failed: {command!r}\n{result.stdout}{result.stderr}")
    return result.stdout


def main():
    if run([ROC, "version"]).strip() != f"Roc compiler version {package_pin(ROOT)}":
        raise SystemExit("Set ROC to the compiler pinned by the package header")
    manifest = json.loads((FIXTURES / "integrity.json").read_text())
    for name, expected in manifest.items():
        if hashlib.sha256((FIXTURES / name).read_bytes()).hexdigest() != expected:
            raise SystemExit(f"Unreviewed timed oracle change: {name}")
    cases = [json.loads(line) for line in (FIXTURES / "cases.jsonl").read_text().splitlines()]
    for case in cases:
        if set(case) not in ({"name", "input", "expected"}, {"name", "input", "error"}):
            raise SystemExit("Malformed timed export corpus")
        if not isinstance(case["input"], list) or not all(isinstance(value, str) for value in case["input"]):
            raise SystemExit("Malformed fixture input")
    wrong = {**cases[0]["expected"], "occurrences": []}
    for output in ("", "null", "{}", "[]", "{broken", json.dumps(wrong)):
        try:
            compare(output, cases[0])
        except (ValueError, TypeError):
            pass
        else:
            raise SystemExit("Timed comparison failure control failed")
    temp = ROOT / ".roc-time-tmp"
    temp.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="timed-export-", dir=temp) as directory:
        entry = str(FIXTURES / "main.roc")
        run([ROC, "check", entry])
        compare(run([ROC, entry, "--", *cases[0]["input"]]), cases[0])
        for mode in ("dev", "speed"):
            binary = str(Path(directory) / mode)
            run([ROC, "build", entry, f"--opt={mode}", f"--output={binary}"])
            for case in cases:
                compare(run([binary, *case["input"]]), case)
            for actual, expected in [(cases[1], cases[0]), (cases[-1], cases[-2])]:
                try:
                    compare(run([binary, *actual["input"]]), expected)
                except ValueError:
                    pass
                else:
                    raise SystemExit("Native timed export failure control failed")
            print(f"PASS timed export {mode}: {len(cases)} sourced/profile fixtures and failure controls")


if __name__ == "__main__":
    main()
