#!/usr/bin/env python3
"""Verify paired-bundle rejection paths against the exact candidate archives.

Run after test_bundle_examples.py has accepted this pair. No archives are built;
all attempted downloads use that harness's fresh cache and loopback server.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def reject(arguments: list[str], diagnostic: str) -> None:
    completed = subprocess.run(
        [sys.executable, str(ROOT / "scripts/test_bundle_examples.py"), "--skip-build-run", *arguments],
        cwd=ROOT, text=True, capture_output=True, timeout=120,
    )
    output = completed.stdout + completed.stderr
    if completed.returncode == 0 or diagnostic not in output:
        raise SystemExit(f"Expected rejection containing {diagnostic!r}; got {completed.returncode}:\n{output}")
    print(f"PASS rejected: {diagnostic}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-path", required=True, type=Path)
    parser.add_argument("--zone-bundle-path", required=True, type=Path)
    args = parser.parse_args()
    core, zones = args.bundle_path.resolve(), args.zone_bundle_path.resolve()
    if not core.is_file() or not zones.is_file() or core.name == zones.name:
        parser.error("supply two existing distinct candidate archives already accepted by the bundle harness")
    reject(["--bundle-path", str(core)], "must be supplied together")
    reject(["--zone-bundle-path", str(zones)], "must be supplied together")
    temporary = Path(os.environ.get("ROC_TIME_TMPDIR", ROOT / ".roc-time-tmp")).resolve()
    temporary.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bundle-failures-", dir=temporary) as directory:
        root = Path(directory)
        reject(["--bundle-path", str(core), "--zone-bundle-path", str(root / "missing.tar.zst")], "Bundle does not exist:")
        reject(["--bundle-path", str(zones), "--zone-bundle-path", str(core)], "package module is private")
        # Keep the valid content-addressed filename but corrupt the archive.
        # A warm global package cache must not hide this acquisition failure.
        malformed = root / core.name
        malformed.write_bytes(b"deliberately malformed release archive\n")
        reject(["--bundle-path", str(malformed), "--zone-bundle-path", str(zones)], "package download failed")


if __name__ == "__main__":
    main()
