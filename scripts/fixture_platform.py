#!/usr/bin/env python3
"""Legacy host preparation for the remaining Python oracle/benchmark drivers.

Resource verification lives in check_fixture_platform.roc. Remove this helper
when those consumers use src/FixtureHost.roc directly. Outputs are disposable.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import platform
import shutil
import sys
sys.dont_write_bytecode = True
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".roc-time-tmp" / "fixture-platform"
# Roc requires platform link inputs inside the platform directory; these are
# ignored copies of the artifacts staged and verified under BUILD.
TARGETS = ROOT / "tests" / "platform" / "targets"
REVISION = "d4db636a2f606edf5ae4803f84588f7a5207d53a"
LINK_INPUTS = {
    "crt1.o": "ffb51a69191a69fc34acaec1003fabe245d8841da7036d124d3445718415f9ea",
    "libc.a": "85f5eb2316bc6f86be7bd66008488c7d2eca290942b01ad2e86f02f8b5e8c90f",
}

def zig_env(global_cache: Path) -> dict[str, str]:
    """Zig 0.17 takes its global cache directory only from the environment."""
    return {**os.environ, "ZIG_GLOBAL_CACHE_DIR": str(global_cache)}

def build_host() -> str:
    """Build once before parallel fixture compilation; return Roc target name."""
    target = {("Darwin", "arm64"): "arm64mac", ("Linux", "x86_64"): "x64musl"}.get((platform.system(), platform.machine()))
    if target is None:
        raise RuntimeError("Fixture host supports arm64mac and x64musl; this host is unverified")
    zig = os.environ.get("ZIG", "zig")
    version = subprocess.check_output([zig, "version"], text=True).strip()
    if version != "0.17.0":
        raise RuntimeError(f"Fixture host requires Zig 0.17.0, found {version}")
    BUILD.mkdir(parents=True, exist_ok=True)
    command = [zig, "build", "--build-file", str(ROOT / "tests/platform/build.zig"),
               "--prefix", str(BUILD / "build"), "--cache-dir", str(BUILD / "cache"), "-Doptimize=ReleaseFast"]
    if target == "x64musl":
        command.append("-Dtarget=x86_64-linux-musl")
    subprocess.run(command, cwd=ROOT, check=True, timeout=300, env=zig_env(BUILD / "global-cache"))
    destination = BUILD / "targets" / target
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(BUILD / "build/lib/libhost.a", destination / "libhost.a")
    if target == "x64musl":
        for name, digest in LINK_INPUTS.items():
            path = destination / name
            if not path.exists():
                url = f"https://raw.githubusercontent.com/lukewilliamboswell/roc-platform-template-zig/{REVISION}/platform/targets/x64musl/{name}"
                with urllib.request.urlopen(url, timeout=60) as response:
                    content = response.read(16 * 1024 * 1024)
                if hashlib.sha256(content).hexdigest() != digest:
                    raise RuntimeError(f"Bad downloaded fixture link input: {name}")
                path.write_bytes(content)
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f"Bad cached fixture link input: {path}")
    shutil.copytree(destination, TARGETS / target, dirs_exist_ok=True)
    return target
