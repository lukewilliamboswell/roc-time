#!/usr/bin/env python3
"""Observe empty-operand coverage identities without copying canonical storage."""
from pathlib import Path
import os
import subprocess
import sys

sys.dont_write_bytecode = True
import fixture_platform
from roc_version import package_pin

ROOT = Path(__file__).resolve().parents[1]


def main():
    roc = os.environ.get("ROC", "roc")
    version = subprocess.check_output([roc, "version"], text=True).strip()
    if version != f"Roc compiler version {package_pin(ROOT)}":
        raise SystemExit("Use the package's pinned Roc compiler")
    target = fixture_platform.build_host()
    output = ROOT / ".roc-time-tmp/coverage-identity-resource"
    output.mkdir(parents=True, exist_ok=True)
    for mode in ("dev", "speed"):
        binary = output / mode
        subprocess.run([roc, "build", "tests/coverage_identity_resource/main.roc",
                        f"--opt={mode}", f"--target={target}", f"--output={binary}"],
                       cwd=ROOT, check=True, timeout=180)
        for count in (0, 1, 4096):
            for operation in ("union_right", "union_left", "difference_right"):
                result = subprocess.run([binary, str(count), operation, "normal"],
                                        capture_output=True, text=True, timeout=10)
                if (result.returncode or result.stdout != "coverage-identity=preserved\n"
                        or not result.stderr.endswith(" work=0,0\n")):
                    raise RuntimeError(f"{mode}/{count}/{operation}: {result.stdout}\n{result.stderr}")
        failed = subprocess.run([binary, "1", "union_right", "allocate"],
                                capture_output=True, text=True, timeout=10)
        if failed.returncode == 0 or "ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: allocation failure control did not fail")
        print(f"PASS coverage identity {mode}: 9 empty/small/large cases, retained aliases, zero allocation, failing control")


if __name__ == "__main__":
    main()
