#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
from pathlib import Path


sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DEPENDENCY_RE = re.compile(r'(?m)^(\s*time:\s*)"[^"]+"')


def update_examples(examples_dir: Path, bundle_url: str, zone_bundle_url: str | None = None, *, compiler: str | None = None) -> list[Path]:
    examples = sorted(examples_dir.rglob("main.roc"))
    if not examples:
        raise SystemExit(f"No Roc examples found in {examples_dir}")

    updated: list[Path] = []
    for example in examples:
        source = example.read_text(encoding="utf-8")
        rewritten, count = PACKAGE_DEPENDENCY_RE.subn(
            lambda match: f'{match.group(1)}"{bundle_url}"',
            source,
            count=1,
        )
        if count != 1:
            raise SystemExit(f"{example} does not declare the expected time package dependency")
        if zone_bundle_url is not None:
            rewritten = re.sub(r'(?m)^(\s*zones:\s*)"[^"]+"', lambda match: f'{match.group(1)}"{zone_bundle_url}"', rewritten)
        if compiler is not None:
            from roc_version import replace_pin
            rewritten = replace_pin(rewritten, compiler)
        if rewritten != source:
            example.write_text(rewritten, encoding="utf-8")
            updated.append(example)

    return updated


def copy_examples(destination: Path, core: str, zones: str, *, compiler: str, source: Path = ROOT / "examples") -> list[Path]:
    """Rebind complete applications in a disposable copy, never tracked sources."""
    shutil.copytree(source, destination)
    update_examples(destination, core, zones, compiler=compiler)
    return sorted(destination.rglob("main.roc"))


def self_test() -> None:
    from roc_version import read_pin
    temporary = ROOT / ".roc-time-tmp"
    temporary.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="example-copy-test-", dir=temporary) as directory:
        work = Path(directory)
        source = work / "source"
        (source / "sample").mkdir(parents=True)
        original = ('app [main!] {\n'
                    ' roc: "nightly-2026-09-05-b195f5b",\n'
                    ' time: "https://example.com/time.tar.zst",\n'
                    ' zones: "https://example.com/zones.tar.zst",\n'
                    '}\nimport Example\nmain! = |_args| { Ok({}) }\n')
        main = source / "sample/main.roc"
        main.write_text(original)
        companion = source / "sample/Example.roc"
        companion.write_text("Example := []\n")
        copied = copy_examples(work / "copied", "/local/package/main.roc",
                               "/local/tzdb/package/main.roc",
                               compiler="nightly-2026-09-06-d85e877", source=source)
        if (len(copied) != 1 or read_pin(copied[0]) != "nightly-2026-09-06-d85e877"
                or 'time: "/local/package/main.roc"' not in copied[0].read_text()
                or 'zones: "/local/tzdb/package/main.roc"' not in copied[0].read_text()
                or main.read_text() != original
                or (copied[0].parent / "Example.roc").read_bytes() != companion.read_bytes()):
            raise RuntimeError("Example copy did not preserve sources and rebind headers/dependencies")
        main.write_text(original.replace(' time:', ' absent:'))
        try:
            copy_examples(work / "invalid", "/local/core", "/local/zones",
                          compiler="nightly-2026-09-06-d85e877", source=source)
        except SystemExit as error:
            if "expected time package dependency" not in str(error):
                raise
        else:
            raise RuntimeError("Missing dependency declaration was accepted")
    print("PASS example copies: compiler/dependency rebind, companions, immutable sources, missing declaration")


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-url")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--zone-bundle-url", help="Optional independently versioned zone-data bundle")
    parser.add_argument("--examples-dir", type=Path, default=ROOT / "examples")
    parser.add_argument("--compiler", help="Rebind copied example app compiler headers")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if args.bundle_url is None:
        parser.error("--bundle-url is required")
    updated = update_examples(args.examples_dir, args.bundle_url, args.zone_bundle_url, compiler=args.compiler)
    if updated:
        print("Updated example URLs:")
        for path in updated:
            print(f"- {display_path(path)}")
    else:
        print("Example URLs are already up to date.")


if __name__ == "__main__":
    main()
