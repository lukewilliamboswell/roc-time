#!/usr/bin/env python3
"""Run the full local CI check: check, test, docs, bundle, and examples.

This is what `.github/workflows` runs, so a green run here should mean a green
run in CI.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CREATED_RE = re.compile(r"^Created:\s+(.+\.tar\.zst)\s*$", re.MULTILINE)


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
    bundle_dir = tmp_dir / "bundle"

    shutil.rmtree(tmp_dir, ignore_errors=True)
    docs_dir.mkdir(parents=True)
    bundle_dir.mkdir(parents=True)

    os.environ["ROC_TIME_TMPDIR"] = str(tmp_base)
    os.environ["ROC"] = ROC

    version = run([ROC, "version"], capture=True).stdout.strip()
    print(version, flush=True)
    pinned = (ROOT / ".roc-version").read_text().strip()
    if version != f"Roc compiler version {pinned}":
        raise SystemExit(f"Expected compiler {pinned}; set ROC to the pinned executable")

    heading("Checking package...")
    run([ROC, "check", "package/main.roc"])

    heading("Running package tests...")
    run([ROC, "test", "package/main.roc"])

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

    heading("Checking scripts and examples...")
    run([sys.executable, "scripts/release_bundles.py", "self-test"])
    run([sys.executable, "scripts/release_starter.py", "self-test"])
    for example in sorted((ROOT / "examples").rglob("main.roc")):
        run([ROC, "check", str(example.relative_to(ROOT))])

    heading("Generating package docs...")
    run([sys.executable, "scripts/docs.py", "0.0.0", "--docs-root", str(docs_dir)])

    heading("Verifying documentation code examples...")
    run([sys.executable, "scripts/test_doc_examples.py"])

    if sys.platform.startswith("win"):
        heading("Skipping package bundling on Windows.")
        return

    heading("Bundling package...")
    completed = run(
        [sys.executable, "scripts/bundle.py", "--output-dir", str(bundle_dir)],
        capture=True,
    )
    print(completed.stdout, end="")

    match = CREATED_RE.search(completed.stdout)
    if match is None:
        raise SystemExit("Error: could not extract bundle path from roc bundle output")

    core_bundle = match.group(1)
    heading("Bundling optional zone package...")
    zone_completed = run(
        [sys.executable, "scripts/bundle.py", "--package-dir", "tzdb/package", "--output-dir", str(bundle_dir)],
        capture=True,
    )
    print(zone_completed.stdout, end="")
    zone_match = CREATED_RE.search(zone_completed.stdout)
    if zone_match is None:
        raise SystemExit("Error: could not extract zone bundle path from roc bundle output")

    heading("Testing examples against exact core and zone bundles...")
    run([sys.executable, "scripts/test_bundle_examples.py", "--bundle-path", core_bundle,
         "--zone-bundle-path", zone_match.group(1)])
    run([sys.executable, "scripts/test_bundle_failures.py", "--bundle-path", core_bundle,
         "--zone-bundle-path", zone_match.group(1)])
    run([sys.executable, "scripts/test_starter_kit.py", "--bundle-path", core_bundle,
         "--zone-bundle-path", zone_match.group(1)])


if __name__ == "__main__":
    main()
