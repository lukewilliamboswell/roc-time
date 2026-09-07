#!/usr/bin/env python3
"""Promote staged applications in a release checkout, after selecting its bundles.

Run before update_example_urls.py and test_published_examples.py in release-docs.
The source package's compiler must match the selected release compiler. This
copies complete Roc applications; it never publishes or changes another checkout.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import shutil
from roc_version import package_pin, read_pin
from update_example_urls import update_examples

PROMOTED = ("zoned_appointment", "appointment_display", "invoice_report", "schedule_exchange", "meeting_exchange")
ZONE_STARTERS = frozenset(("staffing", "zoned_appointment", "meeting_exchange"))


def application_source(root: Path, name: str) -> Path:
    public = root / "examples" / name
    return public if public.is_dir() else root / "tests" / name


def sources(directory: Path) -> list[Path]:
    if directory.is_symlink() or any(p.is_symlink() for p in directory.rglob("*")):
        raise ValueError(f"symlink application source: {directory}")
    result = sorted(directory.rglob("*.roc"))
    if not (directory / "main.roc").is_file() or len(result) < 2:
        raise ValueError(f"incomplete application: {directory}")
    return result


def promote(root: Path, compiler: str, core: str, zones: str) -> list[Path]:
    from starter_kit import validate_url
    validate_url(core)
    validate_url(zones)
    if core == zones:
        raise ValueError("core and zones must identify distinct archives")
    if package_pin(root) != compiler:
        raise ValueError("release compiler differs from source package")
    # Validate all inputs before creating any public application directories.
    pending = []
    for name in PROMOTED:
        directory = application_source(root, name)
        paths = sources(directory)
        if directory.parent.name == "tests":
            # The selected release compiler is authoritative; backported app
            # headers may still name development. Validate, then rebind below.
            read_pin(directory / "main.roc")
        pending.append((name, directory, paths))
    result = []
    for name, directory, paths in pending:
        destination = root / "examples" / name
        if destination != directory:
            for path in paths:
                target = destination / path.relative_to(directory)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        update_examples(destination, core, zones, compiler=compiler, migrate_ical=True)
        result.append(destination / "main.roc")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--bundle-url", required=True)
    parser.add_argument("--zone-bundle-url", required=True)
    args = parser.parse_args()
    for path in promote(args.source_root, args.compiler, args.bundle_url, args.zone_bundle_url):
        print(path)


if __name__ == "__main__":
    main()
