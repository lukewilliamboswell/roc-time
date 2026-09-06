#!/usr/bin/env python3
"""Exercise copied public examples against the development package sources."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from roc_version import package_pin
from test_bundle_examples import ROOT, run_example_apps, run_example_checks
from update_example_urls import copy_examples


def main() -> None:
    temporary = Path(os.environ.get("ROC_TIME_TMPDIR", ROOT / ".roc-time-tmp")).resolve()
    temporary.mkdir(parents=True, exist_ok=True)
    originals = {path: path.read_bytes() for path in (ROOT / "examples").rglob("*.roc")}
    with tempfile.TemporaryDirectory(prefix="local-examples-", dir=temporary) as directory:
        examples = copy_examples(
            Path(directory) / "examples",
            str(ROOT / "package/main.roc"), str(ROOT / "tzdb/package/main.roc"),
            compiler=package_pin(ROOT),
        )
        run_example_checks(examples)
        run_example_apps(examples)
    if any(path.read_bytes() != content for path, content in originals.items()):
        raise SystemExit("Development example tests changed tracked example sources")
    print("Verified copied examples against local packages; public sources unchanged.")


if __name__ == "__main__":
    main()
