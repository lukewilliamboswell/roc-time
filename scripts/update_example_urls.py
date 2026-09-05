#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DEPENDENCY_RE = re.compile(r'(?m)^(\s*time:\s*)"[^"]+"')


def update_examples(examples_dir: Path, bundle_url: str, zone_bundle_url: str | None = None) -> list[Path]:
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
        if rewritten != source:
            example.write_text(rewritten, encoding="utf-8")
            updated.append(example)

    return updated


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-url", required=True)
    parser.add_argument("--zone-bundle-url", help="Optional independently versioned zone-data bundle")
    parser.add_argument("--examples-dir", type=Path, default=ROOT / "examples")
    args = parser.parse_args()

    updated = update_examples(args.examples_dir, args.bundle_url, args.zone_bundle_url)
    if updated:
        print("Updated example URLs:")
        for path in updated:
            print(f"- {display_path(path)}")
    else:
        print("Example URLs are already up to date.")


if __name__ == "__main__":
    main()
