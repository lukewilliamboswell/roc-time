#!/usr/bin/env python3
"""Verify domain errors and representation privacy against real package imports."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")


def check(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [ROC, "check", str(path), "--no-cache"], cwd=ROOT,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )


def main() -> None:
    # A positive control establishes that package loading works in this run.
    control = check(ROOT / "tests/compile_pass/main.roc")
    if control.returncode != 0:
        raise SystemExit(f"Positive control failed:\n{control.stdout}")
    cases = {
        "alternatives_as_coverage": ["first argument", "CalendarEvidence", "Coverage"],
        "local_as_posix": ["first argument", "LocalDateTime", "PosixBoundary"],
        "mixed_domain_order": ["PosixBoundary", "CivilDay", "trying to use it as"],
        "posix_as_calendar_delta": ["second argument", "PosixDelta", "CalendarDelta"],
        "civil_as_posix": ["first argument", "CivilDay", "PosixBoundary"],
        "delta_as_boundary": ["first argument", "PosixDelta", "PosixBoundary"],
        "raw_integer_as_boundary": ["first argument", "I64", "PosixBoundary"],
        "forge_events": ["annotation says", "EventCollection(U64)", "List(_a)"],
        "forge_span": ["annotation says", "PosixSpan", "{ end: PosixBoundary, start: PosixBoundary }"],
        "read_span_representation": ["not a record", "PosixSpan", "start field"],
        "read_pattern_representation": ["not a record", "CalendarPattern", "anchor field"],
        "read_recurrence_cursor": ["not a record", "Cursor", "count field"],
    }
    for name, fragments in cases.items():
        result = check(ROOT / "tests/compile_fail" / name / "main.roc")
        output = re.sub(r"\x1b\[[0-9;]*m", "", result.stdout)
        if result.returncode != 1 or not all(s in output for s in fragments):
            raise SystemExit(f"{name}: expected diagnostic missing:\n{output}")
        if "1 error and 0 warnings" not in output:
            raise SystemExit(f"{name}: unexpected additional diagnostics:\n{output}")
        print(f"PASS {name}: intended compile failure")


if __name__ == "__main__":
    main()
