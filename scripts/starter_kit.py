#!/usr/bin/env python3
"""Build a deterministic, independently runnable core/zones starter ZIP."""
from __future__ import annotations

import argparse
import ipaddress
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit
import zipfile

sys.dont_write_bytecode = True
from roc_version import package_pin, replace_pin

ROOT = Path(__file__).resolve().parents[1]
STARTERS = ("booking_exchange", "archive_search", "staffing")
PREFIX = "roc-time-starter"

# Kept here so the generator is the complete source of every generated file.
RUNNER = '''#!/usr/bin/env python3
"""Check/run/build one starter using the exact compiler pinned by this kit."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
STARTERS = ("booking_exchange", "archive_search", "staffing")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("check", "run", "build"))
    parser.add_argument("starter", choices=STARTERS)
    args = parser.parse_args()
    roc = os.environ.get("ROC", "roc")
    # A relative ROC override is relative to the invoking directory, just as
    # shell command paths are; entrypoints and output paths are kit-relative.
    if "/" in roc or "\\\\" in roc:
        roc = str(Path(roc).resolve())
    expected = (ROOT / ".roc-version").read_text().strip()
    try:
        version = subprocess.run([roc, "version"], text=True, capture_output=True, check=True, timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Cannot run Roc: {error}. Set ROC to the pinned compiler executable.")
    if version != f"Roc compiler version {expected}":
        raise SystemExit(f"Wrong Roc compiler: expected {expected}; found {version!r}. Set ROC to the pinned compiler executable.")
    entrypoint = ROOT / "examples" / args.starter / "main.roc"
    if not entrypoint.is_file():
        raise SystemExit(f"Missing starter entrypoint: {entrypoint}")
    if args.operation == "run":
        command = [roc, str(entrypoint)]
    elif args.operation == "check":
        command = [roc, "check", str(entrypoint), "--no-cache"]
    else:
        destination = ROOT / "build"
        destination.mkdir(exist_ok=True)
        command = [roc, "build", str(entrypoint), f"--output={destination / args.starter}"]
    raise SystemExit(subprocess.run(command).returncode)


if __name__ == "__main__":
    main()
'''


def validate_url(value: str) -> str:
    """Allow remote release URLs and local test servers, never Roc literals."""
    if not isinstance(value, str) or not value.isascii() or any(ord(char) <= 32 or ord(char) == 127 for char in value):
        raise ValueError("bundle URL must be a single ASCII URL")
    # Quotes/backslashes/interpolation punctuation cannot enter a Roc string.
    if any(char in value for char in '\\"\'${}<>`'):
        raise ValueError("unsafe bundle URL characters")
    parsed = urlsplit(value)
    if parsed.scheme not in ("https", "http") or not parsed.hostname or parsed.username is not None or parsed.password is not None or parsed.query or parsed.fragment:
        raise ValueError("bundle URL must be HTTPS (or loopback HTTP), without credentials/query/fragment")
    try:
        port = parsed.port
    except ValueError as error:
        raise ValueError("invalid bundle URL port") from error
    if port is not None and not 1 <= port <= 65535:
        raise ValueError("invalid bundle URL port")
    if parsed.scheme == "http":
        try:
            loopback = ipaddress.ip_address(parsed.hostname).is_loopback
        except ValueError:
            loopback = parsed.hostname == "localhost"
        if not loopback:
            raise ValueError("HTTP bundle URLs are restricted to loopback hosts")
    if not re.fullmatch(r"/(?:[A-Za-z0-9._~%+-]+/)*[A-Za-z0-9_-]+\.tar\.zst", parsed.path):
        raise ValueError("bundle URL must identify a .tar.zst archive")
    return value


def readme(compiler: str) -> str:
    return f'''# roc-time starters

This kit contains three complete applications and explicit core/zone package URLs.
It runs without a roc-time checkout. An internet connection is needed on first use
unless the referenced archives are already in the compiler's package cache.

## Install the pinned compiler

Use **{compiler}**, declared in each application’s `roc` header field. The kit’s
`.roc-version` is a generated copy for the optional wrapper. Download the matching release for
your operating system and CPU from the official Roc nightly releases:
https://github.com/roc-lang/nightlies/releases/tag/{compiler}

Unpack the compiler and put `roc` on PATH. Each application's header records
its compiler version and package dependencies.

```sh
cd roc-time-starter/examples/booking_exchange
roc main.roc
```

Run `roc main.roc` inside `archive_search` or `staffing` to try the other
applications, or `roc build main.roc` to create an executable. No Python setup
is needed to run these Roc applications.

An optional Python 3 wrapper supports `python3 run.py check booking_exchange`,
`python3 run.py run staffing`, and `python3 run.py build staffing` from the kit
root. It checks the compiler version and places builds under `build/`. Set
`ROC` to an executable path when using the wrapper with a compiler off PATH.

- `booking_exchange`: exchange explicit appointment timestamps and find availability.
- `archive_search`: preserve archive date precision and qualification while searching.
- `staffing`: resolve a Melbourne overnight shift using the supplied immutable zone
  bundle. Its spring-transition example is seven elapsed hours, not eight.

The `manifest.json` records the compiler and both bundle roles. Each application's
`main.roc` declares the actual release URLs; companion modules contain its domain
logic. The optional zones archive is required by staffing. Neither an unavailable
archive nor an unsupported compiler is silently replaced with checkout sources.
'''


def build(output: Path, bundle_url: str, zone_bundle_url: str) -> Path:
    bundle_url = validate_url(bundle_url)
    zone_bundle_url = validate_url(zone_bundle_url)
    if bundle_url == zone_bundle_url:
        raise ValueError("core and zones must identify distinct archives")
    compiler = package_pin(ROOT)
    if not re.fullmatch(r"nightly-\d{4}-\d{2}-\d{2}-[0-9a-f]+", compiler):
        raise ValueError("unexpected compiler pin")
    files = {
        "LICENSE": (ROOT / "LICENSE").read_bytes(),
        ".roc-version": (compiler + "\n").encode(),
        "README.md": readme(compiler).encode(),
        "run.py": RUNNER.encode(),
        "manifest.json": (json.dumps({"format": "roc-time-starter", "version": 1,
                                     "compiler": compiler, "bundles": {"core": bundle_url, "zones": zone_bundle_url},
                                     "starters": list(STARTERS)}, indent=2, sort_keys=True) + "\n").encode(),
    }
    for starter in STARTERS:
        directory = ROOT / "examples" / starter
        sources = sorted(directory.rglob("*.roc"))
        if not (directory / "main.roc").is_file() or len(sources) < 2:
            raise ValueError(f"incomplete starter folder: {starter}")
        for path in sources:
            if path.is_symlink():
                raise ValueError(f"symlink source is not permitted: {path}")
            source = path.read_text()
            if path.name == "main.roc":
                source = replace_pin(source, compiler)
                source, core_count = re.subn(r'(?m)^(\s*time:\s*)"[^"]+"', lambda match: f'{match[1]}"{bundle_url}"', source)
                source, zone_count = re.subn(r'(?m)^(\s*zones:\s*)"[^"]+"', lambda match: f'{match[1]}"{zone_bundle_url}"', source)
                if core_count != 1 or zone_count != (1 if starter == "staffing" else 0):
                    raise ValueError(f"unexpected package declarations: {path}")
            files[f"examples/{starter}/{path.relative_to(directory).as_posix()}"] = source.encode()
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in sorted(files.items()):
            item = zipfile.ZipInfo(f"{PREFIX}/{name}", date_time=(1980, 1, 1, 0, 0, 0))
            item.create_system = 3
            item.external_attr = (0o100755 if name == "run.py" else 0o100644) << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, content, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bundle-url", required=True)
    parser.add_argument("--zone-bundle-url", required=True)
    args = parser.parse_args()
    print(build(args.output, args.bundle_url, args.zone_bundle_url))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
