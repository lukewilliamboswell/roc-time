#!/usr/bin/env python3
"""Build the test-only instrumented native host; outputs remain disposable."""
from __future__ import annotations
import argparse
import hashlib
import os
from pathlib import Path
import platform
import re
import shutil
import sys
sys.dont_write_bytecode = True
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".roc-time-tmp" / "fixture-platform"
REVISION = "d4db636a2f606edf5ae4803f84588f7a5207d53a"
LINK_INPUTS = {
    "crt1.o": "ffb51a69191a69fc34acaec1003fabe245d8841da7036d124d3445718415f9ea",
    "libc.a": "85f5eb2316bc6f86be7bd66008488c7d2eca290942b01ad2e86f02f8b5e8c90f",
}

def build_host() -> str:
    """Build once before parallel fixture compilation; return Roc target name."""
    target = {("Darwin", "arm64"): "arm64mac", ("Linux", "x86_64"): "x64musl"}.get((platform.system(), platform.machine()))
    if target is None:
        raise RuntimeError("Fixture host supports arm64mac and x64musl; this host is unverified")
    zig = os.environ.get("ZIG", "zig")
    version = subprocess.check_output([zig, "version"], text=True).strip()
    if version != "0.16.0":
        raise RuntimeError(f"Fixture host requires Zig 0.16.0, found {version}")
    BUILD.mkdir(parents=True, exist_ok=True)
    command = [zig, "build", "--build-file", str(ROOT / "tests/platform/build.zig"),
               "--prefix", str(BUILD / "build"), "--cache-dir", str(BUILD / "cache"),
               "--global-cache-dir", str(BUILD / "global-cache"), "-Doptimize=ReleaseFast"]
    if target == "x64musl":
        command.append("-Dtarget=x86_64-linux-musl")
    subprocess.run(command, cwd=ROOT, check=True, timeout=300)
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
    return target


def verify_probe(target: str) -> None:
    """Exercise counters, tracing and failure controls through real Roc code."""
    roc = os.environ.get("ROC", "roc")
    pin = (ROOT / ".roc-version").read_text().strip()
    version = subprocess.check_output([roc, "version"], text=True).strip()
    if version != f"Roc compiler version {pin}":
        raise RuntimeError(f"Set ROC to the pinned compiler: {pin}")
    source = "tests/platform_probe/main.roc"
    for action in ("check", "test"):
        subprocess.run([roc, action, source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"probe-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", "--debug", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for first, second, comparison in (("42", "43", 0), ("43", "42", 2), ("42", "42", 1),
                ("-9223372036854775808", "9223372036854775807", 0)):
            result = subprocess.run([binary, first, second], capture_output=True, timeout=10)
            if result.returncode or result.stdout != (first * 64).encode():
                raise RuntimeError(f"{mode}: resource probe failed: {result.stderr!r}")
            lines = result.stderr.decode().splitlines()
            if len(lines) != 3 or lines[:2] != [
                    "ROC_TRACE protocol=1 mark=1 allocations=1", "ROC_TRACE protocol=1 mark=2 allocations=1"]:
                raise RuntimeError(f"{mode}: unexpected trace: {lines}")
            match = re.fullmatch(r"ROC_METRICS protocol=1 allocations=(\d+) requested_bytes=(\d+) deallocations=(\d+) work=0,(\d+),(\d+)", lines[2])
            if match is None or int(match[4]) != comparison or int(match[5]) <= 0:
                raise RuntimeError(f"{mode}: malformed resource result: {lines[2]}")
        for argument, diagnostic in (("fail-assert", b"ROC_ASSERT_FAILED"), ("fail-expect", b"[ROC EXPECT]")):
            result = subprocess.run([binary, argument], capture_output=True, timeout=10)
            # The pinned LLVM backend omits expect. Always-on hosted assertions
            # protect optimized fixtures; dev independently verifies expect wiring.
            expected_failure = argument == "fail-assert" or mode == "dev"
            if expected_failure:
                if result.returncode == 0 or diagnostic not in result.stderr:
                    raise RuntimeError(f"{mode}: negative control failed: {argument}")
            elif result.returncode != 0:
                raise RuntimeError("Optimized expect behavior changed; review the fixture contract")
    print("PASS fixture host: dev/speed counters, traces, assertions and expect control")


def verify_recurrence(target: str) -> None:
    """Huge logical domains, bounded prefixes; deadlines catch hidden scans."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/recurrence_resource/main.roc"
    for action in ("check", "test"):
        subprocess.run([roc, action, source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"recurrence-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        observations = []
        for year in (2001, 2000000000):
            result = subprocess.run([binary, str(year), "4096"], capture_output=True, timeout=5)
            if result.returncode or result.stdout != b"prefix=1,resume=2\n":
                raise RuntimeError(f"{mode}: recurrence prefix failed: {result.stderr!r}")
            match = re.search(rb" work=(\d+),(\d+),(\d+)\n$", result.stderr)
            if match is None:
                raise RuntimeError(f"{mode}: missing recurrence resource observations")
            observations.append(tuple(int(value) for value in match.groups()))
        if observations[0] != observations[1]:
            raise RuntimeError(f"{mode}: prefix allocation traffic depends on horizon: {observations}")
        # Same operation, deliberately impossible traffic ceiling: verify the
        # resource assertion remains active, rather than only checking output.
        failed = subprocess.run([binary, "2000000000", "0"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: recurrence allocation negative control failed")
        print(f"PASS recurrence {mode}: short/vast horizon requested bytes {observations[0]}; negative control")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="build and run instrumented temporal probes")
    options = parser.parse_args()
    selected_target = build_host()
    if options.verify:
        verify_probe(selected_target)
        verify_recurrence(selected_target)
    else:
        print(selected_target)
