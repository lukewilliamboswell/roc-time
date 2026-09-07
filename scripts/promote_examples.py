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

# Public destination -> development application. Replacements use their existing
# public names; copying occurs only in an explicit release checkout promotion.
PROMOTION_SOURCES = {
    "invoice": "invoice_terms",
    "staffing": "overnight_staffing",
    "zoned_appointment": "zoned_appointment",
    "appointment_display": "appointment_display",
    "invoice_report": "invoice_report",
    "schedule_exchange": "schedule_exchange",
    "meeting_exchange": "meeting_exchange",
    "upcoming_meetings": "upcoming_meetings",
}
PROMOTED = tuple(PROMOTION_SOURCES)
ZONE_STARTERS = frozenset(("staffing", "zoned_appointment", "meeting_exchange", "upcoming_meetings"))


def application_source(root: Path, name: str) -> Path:
    public = root / "examples" / name
    staged = root / "tests" / PROMOTION_SOURCES.get(name, name)
    return staged if name in PROMOTION_SOURCES and staged.is_dir() else public


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
        destination = root / "examples" / name
        if destination.is_symlink() or any(p.is_symlink() for p in destination.rglob("*")):
            raise ValueError(f"symlink application destination: {destination}")
        pending.append((name, directory, paths))
    result = []
    for name, directory, paths in pending:
        destination = root / "examples" / name
        if destination != directory:
            # Prevent old companion modules surviving replacement or retries.
            if destination.is_symlink():
                raise ValueError(f"symlink application destination: {destination}")
            expected = {path.relative_to(directory) for path in paths}
            # Promotion owns Roc sources; preserve accompanying assets and notes.
            for old in destination.rglob("*.roc"):
                if old.relative_to(destination) not in expected:
                    old.unlink()
            for path in paths:
                target = destination / path.relative_to(directory)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        update_examples(destination, core, zones, compiler=compiler, migrate_api=True)
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
