#!/usr/bin/env python3
"""Bundle the package for distribution.

Prints the `roc bundle` output, which includes the `Created: <path>` line
naming the bundle that was produced.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def roc_command() -> str:
    roc = os.environ.get("ROC", "roc")
    if "/" in roc or "\\" in roc:
        return str(Path(roc).resolve())
    return roc


def package_files(package_dir: Path) -> list[str]:
    """`main.roc` first, then the remaining modules in a stable order."""
    main = package_dir / "main.roc"
    if not main.exists():
        raise SystemExit(f"No package entrypoint found at {main}")

    others = sorted(p.name for p in package_dir.glob("*.roc") if p.name != "main.roc")
    return ["main.roc", *others]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    args, extra = parser.parse_known_args()

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    package_dir = ROOT / "package"
    cmd = [
        roc_command(),
        "bundle",
        *package_files(package_dir),
        "--output-dir",
        str(output_dir.resolve()),
        *extra,
    ]

    print("+", " ".join(cmd), file=sys.stderr)
    completed = subprocess.run(cmd, cwd=package_dir)
    raise SystemExit(completed.returncode)


if __name__ == "__main__":
    main()
