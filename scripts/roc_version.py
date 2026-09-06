#!/usr/bin/env python3
"""Compiler requirements are declared in Roc root headers, not a second registry."""
import argparse
import sys
sys.dont_write_bytecode = True
from pathlib import Path
from compiler_pins import header_pin

ROOT = Path(__file__).resolve().parents[1]

def read_pin(path):
    result = header_pin(Path(path).read_text())
    if result is None:
        raise ValueError(f"Missing roc compiler header pin: {path}")
    return result[2]

def package_requirement(root=ROOT):
    root = Path(root)
    found = [header_pin((root / path).read_text())
             for path in ("package/main.roc", "tzdb/package/main.roc")]
    legacy = root / ".roc-version"
    if all(item is None for item in found):
        from compiler_pins import PIN
        pin = legacy.read_text().strip() if legacy.is_file() else ""
        if not PIN.fullmatch(pin):
            raise ValueError("Unpinned package headers require a valid legacy .roc-version")
        return pin, "legacy"
    if any(item is None for item in found) or legacy.exists():
        raise ValueError("Mixed compiler authorities: use both package headers or legacy .roc-version")
    pins = {item[2] for item in found}
    if len(pins) != 1:
        raise ValueError("Core and zones package compiler pins disagree")
    return pins.pop(), "header"


def package_pin(root=ROOT):
    return package_requirement(root)[0]


def replace_pin(source, pin):
    from compiler_pins import PIN
    if not PIN.fullmatch(pin):
        raise ValueError("Invalid compiler pin")
    result = header_pin(source)
    if result is None:
        raise ValueError("Missing roc compiler header pin")
    start, end, _ = result
    return source[:start] + pin + source[end:]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--entrypoint", type=Path)
    parser.add_argument("--format", choices=("pin", "authority"), default="pin")
    args = parser.parse_args()
    if args.entrypoint:
        if args.format != "pin":
            parser.error("--format authority requires a package --root")
        print(read_pin(args.entrypoint))
    else:
        requirement = package_requirement(args.root)
        print(requirement[0 if args.format == "pin" else 1])
