#!/usr/bin/env python3
"""Run unchanged public examples with their declared compiler and dependencies."""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
from roc_version import read_pin
from test_bundle_examples import ROOT, ROC, run_example_apps, run_example_checks


def collection_pin(directory: Path) -> tuple[list[Path], str]:
    examples = sorted(directory.rglob("main.roc"))
    if not examples:
        raise ValueError(f"No example applications found: {directory}")
    pins = {read_pin(example) for example in examples}
    if len(pins) != 1:
        raise ValueError(f"Mixed example compiler pins: {', '.join(sorted(pins))}")
    return examples, pins.pop()


def require_compiler(expected: str, actual: str) -> None:
    if actual != f"Roc compiler version {expected}":
        raise ValueError(f"Wrong Roc compiler: expected {expected}; found {actual!r}")


def self_test() -> None:
    temporary = ROOT / ".roc-time-tmp"
    temporary.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="published-examples-test-", dir=temporary) as directory:
        root = Path(directory)
        pin = "nightly-2026-09-05-b195f5b"
        for name in ("first", "second"):
            (root / name).mkdir()
            (root / name / "main.roc").write_text(f'app [main!] {{ roc: "{pin}" }}\n')
        examples, found = collection_pin(root)
        if len(examples) != 2 or found != pin:
            raise RuntimeError("Matching compiler pins were not discovered")
        require_compiler(pin, f"Roc compiler version {pin}")
        try:
            require_compiler(pin, "Roc compiler version wrong")
        except ValueError as error:
            if "Wrong Roc compiler" not in str(error):
                raise
        else:
            raise RuntimeError("Wrong compiler was accepted")
        for content, diagnostic in (
            ('app [main!] {}\n', "Missing roc compiler header pin"),
            ('app [main!] { roc: "nightly-2026-09-06-d85e877" }\n', "Mixed example compiler pins"),
        ):
            (root / "second/main.roc").write_text(content)
            try:
                collection_pin(root)
            except ValueError as error:
                if diagnostic not in str(error):
                    raise
            else:
                raise RuntimeError(f"Expected {diagnostic}")
        empty = root / "empty"
        empty.mkdir()
        try:
            collection_pin(empty)
        except ValueError as error:
            if "No example applications" not in str(error):
                raise
        else:
            raise RuntimeError("Empty collection was accepted")
    print("PASS published examples: shared pin, wrong compiler, missing/mixed pins, empty collection")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--examples-dir", type=Path, default=ROOT / "examples")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--expected-dir", type=Path, help="Golden outputs belonging to this example snapshot")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    examples_dir = args.examples_dir.resolve()
    examples, pin = collection_pin(examples_dir)
    version = subprocess.run([ROC, "version"], check=True, capture_output=True,
                             text=True, timeout=30).stdout.strip()
    require_compiler(pin, version)
    originals = {path: path.read_bytes() for path in examples_dir.rglob("*.roc")}
    run_example_checks(examples)
    run_example_apps(examples, expected_dir=args.expected_dir.resolve() if args.expected_dir else None)
    if any(path.read_bytes() != content for path, content in originals.items()):
        raise RuntimeError("Published example verification modified source files")
    print(f"Verified {len(examples)} unchanged public examples with {pin}.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
