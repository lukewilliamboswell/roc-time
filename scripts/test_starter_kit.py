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
from roc_version import package_pin
from test_bundle_examples import ROOT, ROC, REHEARSAL_VERSION, bare_asset_name, release_asset_name, start_server

STARTERS = ("booking_exchange", "archive_search", "staffing")


def invoke(kit, cache, command, starter, *, expected=None, diagnostic=None, roc=ROC):
    env = {**os.environ, "ROC": roc, "XDG_CACHE_HOME": str(cache)}
    result = subprocess.run([sys.executable, str(kit / "run.py"), command, starter],
                            cwd=Path(tempfile.gettempdir()).resolve(), env=env,
                            capture_output=True, text=True, timeout=120)
    if diagnostic is not None:
        # Roc wraps long paths in diagnostics, including within a filename.
        # Match the same specific diagnostic independently of display wrapping.
        observed = "".join((result.stdout + result.stderr).split())
        required = "".join(diagnostic.split())
        if result.returncode == 0 or required not in observed:
            raise RuntimeError(f"Expected {diagnostic!r}: {result.stdout}\n{result.stderr}")
    elif result.returncode or (expected is not None and result.stdout != expected):
        raise RuntimeError(f"Starter {command}/{starter} failed: {result.stdout}\n{result.stderr}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-path", type=Path, required=True)
    parser.add_argument("--zone-bundle-path", type=Path, required=True)
    parser.add_argument("--kit-path", type=Path, help="Validate and exercise a supplied release ZIP")
    parser.add_argument("--role-metadata", type=Path)
    parser.add_argument("--repo")
    parser.add_argument("--release-version")
    args = parser.parse_args()
    if args.kit_path and not all((args.role_metadata, args.repo, args.release_version)):
        parser.error("a supplied kit requires --role-metadata, --repo and --release-version")
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
        # Keep a version in the HTTP path: versionless URLs bypass package
        # version identity solving and concealed the original two-package clash.
        release_dir = served / REHEARSAL_VERSION
        release_dir.mkdir(parents=True)
        staged = []
        for role, source in (("core", core), ("zones", zones)):
            name = source.name if args.kit_path else release_asset_name(source, role)
            target = release_dir / name
            shutil.copy2(source, target)
            staged.append(target)
        core, zones = staged
        requests = []
        server, base = start_server(served, requests)
        try:
            core_url, zone_url = f"{base}/{REHEARSAL_VERSION}/{core.name}", f"{base}/{REHEARSAL_VERSION}/{zones.name}"
            archive = build(work / "starter.zip", core_url, zone_url)
            duplicate = build(work / "duplicate.zip", core_url, zone_url)
            if archive.read_bytes() != duplicate.read_bytes():
                raise RuntimeError("starter archive is not reproducible")
            from release_starter import prepare, validate
            if args.kit_path:
                candidate = args.kit_path.resolve()
                roles_path = args.role_metadata.resolve()
                repo, version = args.repo, args.release_version
            else:
                from release_bundles import metadata as release_metadata
                roles_path = work / "roles.json"
                roles_path.write_text(json.dumps(release_metadata([
                    {"name": "core", "artifact_file": core.name},
                    {"name": "zones", "artifact_file": zones.name}], release_dir)))
                repo, version = "roc-time/validation", REHEARSAL_VERSION
                candidate = prepare(repo, version, roles_path, release_dir, work / "candidate.zip")
            # Validate the original artifact before extraction. Its release URLs
            # cannot be fetched before publication; rebase only the extracted
            # copy's known dependency URLs onto the local server below.
            archive = validate(candidate, roles_path, release_dir, repo, version)
            with zipfile.ZipFile(archive) as zipped:
                zipped.extractall(work / "extracted")
            kit = work / "extracted/roc-time-starter"
            metadata = json.loads((kit / "manifest.json").read_text())
            if metadata["compiler"] != package_pin(ROOT):
                raise RuntimeError("starter compiler pin differs from package")
            from update_example_urls import update_examples
            update_examples(kit / "examples", core_url, zone_url)
            metadata["bundles"] = {"core": core_url, "zones": zone_url}
            (kit / "manifest.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
            for starter in STARTERS:
                expected = (ROOT / f"tests/examples/{starter}.txt").read_text()
                invoke(kit, work / "cache", "check", starter)
                # This is the documented first-use path: Roc directly, without
                # relying on the optional Python wrapper to rebind dependencies.
                direct = subprocess.run([ROC, "main.roc"],
                                        cwd=kit / "examples" / starter,
                                        env={**os.environ, "XDG_CACHE_HOME": str(work / "cache")},
                                        capture_output=True, text=True, timeout=120)
                if direct.returncode or direct.stdout != expected:
                    raise RuntimeError(f"Direct Roc starter failed: {starter}: {direct.stdout}\n{direct.stderr}")
                invoke(kit, work / "cache", "build", starter)
                binary = kit / "build" / starter
                result = subprocess.run([str(binary)], cwd=outside, capture_output=True,
                                        text=True, timeout=10)
                if result.returncode or result.stdout != expected:
                    raise RuntimeError(f"Native starter mismatch: {starter}: {result.stdout}\n{result.stderr}")
            if not {f"/{REHEARSAL_VERSION}/{core.name}", f"/{REHEARSAL_VERSION}/{zones.name}"} <= set(requests):
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
            collision_dir = served / "collision" / REHEARSAL_VERSION
            collision_dir.mkdir(parents=True)
            for source in (core, zones):
                shutil.copy2(source, collision_dir / bare_asset_name(source))
            collision_base = f"{base}/collision/{REHEARSAL_VERSION}"
            cases = (
                ("identity-collision", f"{collision_base}/{bare_asset_name(core)}",
                 f"{collision_base}/{bare_asset_name(zones)}", "same package version is being served with two different content hashes"),
                ("missing", f"{base}/missing/{core.name}", zone_url, "package download failed"),
                ("corrupt", f"{base}/corrupt/{core.name}", zone_url, "package download failed"),
                ("swapped", zone_url, core_url, "package module is private"),
            )
            for name, candidate_core, candidate_zones, diagnostic in cases:
                candidate = build(work / f"{name}.zip", candidate_core, candidate_zones)
                with zipfile.ZipFile(candidate) as zipped:
                    zipped.extractall(work / name)
                invoke(work / name / "roc-time-starter", work / f"{name}-cache",
                       "check", "staffing" if name == "identity-collision" else "booking_exchange", diagnostic=diagnostic)
            print("PASS starter failures: wrong compiler, missing companion, missing/corrupt/swapped archives, same-version package identity collision")
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
