#!/usr/bin/env python3
"""Run the checks that are still driven from Python.

scripts/check_all.roc is the repository gate. It checks the Roc tooling, the
packages, the examples and the release artifacts, and calls this harness for
compile-failure, static-dispatch, codec, resource, oracle, fuzz, measurement
and documentation checks. ROC selects the package compiler.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def roc_command() -> str:
    roc = os.environ.get("ROC", "roc")
    if "/" in roc or "\\" in roc:
        return str(Path(roc).resolve())
    return roc


ROC = roc_command()


def run(cmd: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(cmd), flush=True)
    completed = subprocess.run(
        cmd,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )

    if completed.returncode != 0:
        if capture and completed.stdout:
            print(completed.stdout)
        raise SystemExit(f"command failed with exit code {completed.returncode}: {' '.join(cmd)}")

    return completed


def heading(text: str) -> None:
    print(f"\n{text}", flush=True)


def main() -> None:
    tmp_base = Path(os.environ.get("ROC_TIME_TMPDIR", ROOT / ".roc-time-tmp"))
    tmp_dir = tmp_base / "roc-time-ci"
    docs_dir = tmp_dir / "docs"

    shutil.rmtree(tmp_dir, ignore_errors=True)
    docs_dir.mkdir(parents=True)

    os.environ["ROC_TIME_TMPDIR"] = str(tmp_base)
    os.environ["ROC"] = ROC

    run([ROC, "version"])

    heading("Checking domain and representation compile failures...")
    run([sys.executable, "scripts/test_compile_failures.py"])

    heading("Checking public static dispatch...")
    dispatch = "tests/static_dispatch/main.roc"
    run([ROC, "check", dispatch])
    run([ROC, dispatch])
    dispatch_binary = (tmp_dir / "static-dispatch").resolve()
    run([ROC, "build", dispatch, f"--output={dispatch_binary}"])
    run([str(dispatch_binary)])

    heading("Checking generic codecs and typed literals...")
    codecs = "tests/codecs/main.roc"
    run([ROC, "check", codecs])
    run([ROC, codecs])
    for mode in ("dev", "speed"):
        codec_binary = (tmp_dir / f"codecs-{mode}").resolve()
        run([ROC, "build", codecs, f"--opt={mode}", f"--output={codec_binary}"])
        run([str(codec_binary)])

    heading("Checking the Roc/Chrono benchmark harness (bounded correctness smoke)...")
    run([sys.executable, "scripts/benchmark_chrono.py", "--smoke", "--fetch"])
    heading("Checking timestamp parser allocation regressions...")
    run([sys.executable, "scripts/test_timestamp_parser.py"])
    heading("Checking coverage identity allocation regressions...")
    run([sys.executable, "scripts/test_coverage_identity.py"])

    heading("Checking independent Gregorian query expectations...")
    run([sys.executable, "scripts/test_civil_queries.py"])
    heading("Checking DATE recurrence export against independent expectations...")
    run([sys.executable, "scripts/test_date_export.py"])
    heading("Checking timed recurrence export against independent expectations...")
    run([sys.executable, "scripts/test_timed_export.py"])
    run([sys.executable, "tests/utc_cancellations_checks/reference.py"])
    heading("Checking named-zone appointment scenarios...")
    appointments = "tests/zoned_appointment_checks/main.roc"
    run([ROC, "check", appointments])
    run([ROC, appointments])
    for mode in ("dev", "speed"):
        appointment_binary = (tmp_dir / f"zoned-appointments-{mode}").resolve()
        run([ROC, "build", appointments, f"--opt={mode}", f"--output={appointment_binary}"])
        run([str(appointment_binary)])

    heading("Running bounded semantic fuzz checks and regression replay...")
    run([sys.executable, "scripts/fuzz.py", "--operation", "all"])

    heading("Verifying the instrumented fixture platform...")
    run([sys.executable, "scripts/fixture_platform.py", "--verify"])

    heading("Checking JSONL replay failure and concurrency controls...")
    run([sys.executable, "scripts/test_oracle_replay.py"])

    heading("Comparing public APIs with oracle expectations...")
    run([sys.executable, "scripts/oracles.py"])

    heading("Verifying the optional zone database...")
    run([sys.executable, "scripts/test_zone_database.py"])

    heading("Checking retained measurement tools with bounded real workloads...")
    run([sys.executable, "scripts/measure_gregorian.py", "--smoke"])
    run([sys.executable, "scripts/measure_zone_data.py", "--smoke"])
    generator_python = os.environ.get("ROC_TIME_GENERATOR_PYTHON", sys.executable)
    for encoding in ("columns", "tzif"):
        run([generator_python, "scripts/measure_zone_roc.py", "--smoke", "--encoding", encoding])
    run([sys.executable, "scripts/measure_zone_package.py", "--smoke"])

    heading("Checking documentation tooling...")
    run([sys.executable, "scripts/check_docs_history.py", "--self-test"])
    run([sys.executable, "scripts/test_docs.py"])
    run([sys.executable, "scripts/test_release_docs.py"])

    heading("Generating package docs...")
    run([sys.executable, "scripts/docs.py", "0.0.0", "--docs-root", str(docs_dir)])

    heading("Verifying documentation code examples...")
    run([sys.executable, "scripts/test_doc_examples.py"])


if __name__ == "__main__":
    main()
