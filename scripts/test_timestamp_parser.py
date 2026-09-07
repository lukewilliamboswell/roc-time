#!/usr/bin/env python3
"""Assert runtime timestamp parsing avoids byte-list allocations on both backends."""
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
    output = ROOT / ".roc-time-tmp/timestamp-parser-resource"
    output.mkdir(parents=True, exist_ok=True)
    for mode in ("dev", "speed"):
        binary = output / mode
        subprocess.run([roc, "build", "tests/timestamp_parser_resource/main.roc",
                        f"--opt={mode}", f"--target={target}", f"--output={binary}"],
                       cwd=ROOT, check=True, timeout=180)
        for text in ("1970-01-01T00:00:01Z", "1970-01-01T00:00:01.0Z",
                     "1970-01-01T00:00:01.000000+00:00"):
            for ownership in ("direct", "aliases", "suffix"):
                result = subprocess.run([binary, text, ownership, "normal", text.replace("T", "t")], capture_output=True,
                                        text=True, timeout=5)
                if (result.returncode or result.stdout != "timestamp-parser=1000,boundary=1000000\n"
                        or not result.stderr.endswith(" work=0,0\n")):
                    raise RuntimeError(f"{mode}/{ownership}/{text}: {result.stdout}\n{result.stderr}")
        failed = subprocess.run([binary, "1970-01-01T00:00:01Z", "direct", "allocate", "1970-01-01t00:00:01Z"],
                                capture_output=True, text=True, timeout=5)
        if failed.returncode == 0 or "ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: allocation failure control did not fail")
        print(f"PASS timestamp parser {mode}: 9 runtime short/heap preparation cases, zero allocation, failing control")


if __name__ == "__main__":
    main()
