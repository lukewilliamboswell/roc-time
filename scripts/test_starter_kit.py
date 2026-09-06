#!/usr/bin/env python3
"""Exercise an extracted starter kit from outside the repository working tree."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True
from starter_kit import build, validate_url
from test_bundle_examples import ROOT, ROC, start_server

STARTERS = ("booking_exchange", "archive_search", "staffing")


def invoke(kit, cache, command, starter, *, expected=None, diagnostic=None, roc=ROC):
    env = {**os.environ, "ROC": roc, "XDG_CACHE_HOME": str(cache)}
    result = subprocess.run([sys.executable, str(kit / "run.py"), command, starter],
                            cwd=Path(tempfile.gettempdir()).resolve(), env=env,
                            capture_output=True, text=True, timeout=120)
    if diagnostic is not None:
        if result.returncode == 0 or diagnostic not in result.stdout + result.stderr:
            raise RuntimeError(f"Expected {diagnostic!r}: {result.stdout}\n{result.stderr}")
    elif result.returncode or (expected is not None and result.stdout != expected):
        raise RuntimeError(f"Starter {command}/{starter} failed: {result.stdout}\n{result.stderr}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-path", type=Path, required=True)
    parser.add_argument("--zone-bundle-path", type=Path, required=True)
    args = parser.parse_args()
    for invalid in ("file:///tmp/a.tar.zst", "https://example.com\x7f/a.tar.zst",
                    "https://example.com\x00/a.tar.zst", "https://example.com/a.tar.zst\n"):
        try:
            validate_url(invalid)
        except ValueError:
            pass
        else:
            raise RuntimeError("invalid starter dependency URL accepted")
    core, zones = args.bundle_path.resolve(), args.zone_bundle_path.resolve()
    if not core.is_file() or not zones.is_file() or core.name == zones.name:
        parser.error("provide distinct existing core and zone archives")
    outside = Path(tempfile.gettempdir()).resolve()
    if outside == ROOT or ROOT in outside.parents:
        raise RuntimeError("temporary working directory must be outside the checkout")
    temporary = ROOT / ".roc-time-tmp"
    temporary.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="starter-kit-", dir=temporary) as directory:
        work = Path(directory)
        served = work / "served"
        served.mkdir()
        for source in (core, zones):
            shutil.copy2(source, served / source.name)
        requests = []
        server, base = start_server(served, requests)
        try:
            core_url, zone_url = f"{base}/{core.name}", f"{base}/{zones.name}"
            archive = build(work / "starter.zip", core_url, zone_url)
            duplicate = build(work / "duplicate.zip", core_url, zone_url)
            if archive.read_bytes() != duplicate.read_bytes():
                raise RuntimeError("starter archive is not reproducible")
            with zipfile.ZipFile(archive) as zipped:
                zipped.extractall(work / "extracted")
            kit = work / "extracted/roc-time-starter"
            metadata = json.loads((kit / "manifest.json").read_text())
            if metadata["compiler"] != (ROOT / ".roc-version").read_text().strip():
                raise RuntimeError("starter compiler pin differs from package")
            for starter in STARTERS:
                expected = (ROOT / f"tests/examples/{starter}.txt").read_text()
                invoke(kit, work / "cache", "check", starter)
                invoke(kit, work / "cache", "run", starter, expected=expected)
                invoke(kit, work / "cache", "build", starter)
                binary = kit / "build" / starter
                result = subprocess.run([str(binary)], cwd=outside, capture_output=True,
                                        text=True, timeout=10)
                if result.returncode or result.stdout != expected:
                    raise RuntimeError(f"Native starter mismatch: {starter}: {result.stdout}\n{result.stderr}")
            if not {f"/{core.name}", f"/{zones.name}"} <= set(requests):
                raise RuntimeError("starter did not acquire both exact archives from its fresh cache")
            print("PASS extracted starters: exact output, cold acquisition, interpreter/native, outside working directory")
            fake = work / "wrong-roc"
            fake.write_text("#!/usr/bin/env python3\nprint('Roc compiler version incompatible-test-compiler')\n")
            fake.chmod(0o755)
            invoke(kit, work / "wrong-cache", "check", "booking_exchange",
                   diagnostic="Wrong Roc compiler:", roc=str(fake))
            incomplete = work / "incomplete"
            shutil.copytree(kit, incomplete)
            (incomplete / "examples/booking_exchange/BookingExchange.roc").unlink()
            invoke(incomplete, work / "cache", "check", "booking_exchange",
                   diagnostic="BookingExchange.roc: FileNotFound")
            (served / "corrupt").mkdir()
            (served / "corrupt" / core.name).write_bytes(b"invalid archive\n")
            cases = (
                ("missing", f"{base}/missing/{core.name}", zone_url, "package download failed"),
                ("corrupt", f"{base}/corrupt/{core.name}", zone_url, "package download failed"),
                ("swapped", zone_url, core_url, "package module is private"),
            )
            for name, candidate_core, candidate_zones, diagnostic in cases:
                candidate = build(work / f"{name}.zip", candidate_core, candidate_zones)
                with zipfile.ZipFile(candidate) as zipped:
                    zipped.extractall(work / name)
                invoke(work / name / "roc-time-starter", work / f"{name}-cache",
                       "check", "booking_exchange", diagnostic=diagnostic)
            print("PASS starter failures: wrong compiler, missing companion, missing/corrupt/swapped archives")
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
