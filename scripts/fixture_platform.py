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
            if result.returncode or result.stdout != b"prefix=1,resume=2,limited=1,zero=1\n":
                raise RuntimeError(f"{mode}: recurrence prefix failed: {result.stderr!r}")
            match = re.search(rb" work=((?:\d+,){29}\d+)\n$", result.stderr)
            if match is None:
                raise RuntimeError(f"{mode}: missing recurrence resource observations")
            observations.append(tuple(int(value) for value in match[1].split(b",")))
        if observations[0] != observations[1]:
            raise RuntimeError(f"{mode}: prefix allocation traffic depends on horizon: {observations}")
        # Same operation, deliberately impossible traffic ceiling: verify the
        # resource assertion remains active, rather than only checking output.
        failed = subprocess.run([binary, "2000000000", "0"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: recurrence allocation negative control failed")
        print(f"PASS recurrence {mode}: short/vast horizon requested bytes {observations[0]}; negative control")


def verify_intervals(target: str) -> None:
    """Finite endpoint products stay implicit; query allocations are separate.

    Requested bytes cover normalization and cached projections, not live bytes.
    Inputs are generated before each measured scope; shared/sliced originals
    remain observable after consumption. A deadline also bounds hidden scans.
    """
    roc = os.environ.get("ROC", "roc")
    source = "tests/interval_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"interval-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for ownership in ("owned", "shared", "sliced"):
            observations = []
            for size in (64, 512, 4096):
                ceiling = 1024 * size + 8192
                result = subprocess.run([binary, str(size), str(ceiling), ownership],
                                        capture_output=True, timeout=5)
                expected = b"independent=definite,edge=possible,outside=impossible,paired-gap=impossible\n"
                if result.returncode or result.stdout != expected:
                    raise RuntimeError(f"{mode}/{ownership}/{size}: interval resource probe failed: {result.stderr!r}")
                match = re.search(rb" work=((?:\d+,){3}\d+)\n$", result.stderr)
                if match is None:
                    raise RuntimeError(f"{mode}/{ownership}: missing interval observations")
                counts = tuple(int(value) for value in match[1].split(b","))
                if counts[1] != 0 or counts[3] != 0:
                    raise RuntimeError(f"{mode}/{ownership}: interval queries allocated: {counts}")
                observations.append(counts)
            # A 64x input increase must not approach 4096x product storage.
            for index in (0, 2):
                if observations[-1][index] > 128 * max(1, observations[0][index]):
                    raise RuntimeError(f"{mode}/{ownership}: nonlinear interval traffic: {observations}")
            failed = subprocess.run([binary, "4096", "0", ownership], capture_output=True, timeout=5)
            if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
                raise RuntimeError(f"{mode}/{ownership}: interval negative control failed")
            print(f"PASS interval {mode}/{ownership}: sizes 64/512/4096 requested bytes {observations}; negative control")


def verify_interchange(target: str) -> None:
    """Separate parsing/output from one resolution and repeated stored reads.

    Transition storage is created before counters. Observations are allocation
    traffic, not live memory; this is no claim of constant-time zone resolution.
    """
    roc = os.environ.get("ROC", "roc")
    source = "tests/interchange_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"interchange-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for tags in (1, 32):
            observations = []
            for transitions in (2, 16384):
                result = subprocess.run([binary, str(transitions), str(tags), "4194304"],
                                        capture_output=True, timeout=5)
                if result.returncode or result.stdout != b"instant=1000000,presentation=1000000,exact=0..2000000\n":
                    raise RuntimeError(f"{mode}/{tags}/{transitions}: interchange probe failed: {result.stderr!r}")
                match = re.search(rb" work=((?:\d+,){10}\d+)\n$", result.stderr)
                if match is None:
                    raise RuntimeError(f"{mode}: missing interchange resource observations")
                counts = tuple(int(value) for value in match[1].split(b","))
                if counts[3] != 0 or counts[9] != 0:
                    raise RuntimeError(f"{mode}: stored snapshot reads or oversized rejection allocated: {counts}")
                observations.append(counts)
            if observations[0] != observations[1]:
                raise RuntimeError(f"{mode}: interchange traffic varies with retained rule size: {observations}")
            print(f"PASS interchange {mode}/{tags} tags: 2/16384 transitions requested bytes {observations[0]}; 100000 stored reads")
        failed = subprocess.run([binary, "16384", "32", "0"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: interchange negative control failed")
        print(f"PASS interchange {mode}: allocation negative control")


def verify_persistence(target: str) -> None:
    """Canonical member counts bound persistence, not coordinate distances."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/persistence_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"persistence-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for coordinates in ("small", "wide"):
            observations = []
            for count in (1, 32, 1024):
                result = subprocess.run([binary, str(count), "1048576", coordinates], capture_output=True, timeout=5)
                if result.returncode or result.stdout != b"coverage=preserved,span=preserved,1025=rejected\n":
                    raise RuntimeError(f"{mode}/{coordinates}/{count}: persistence resources failed: {result.stderr!r}")
                match = re.search(rb" work=((?:\d+,){6}\d+)\n$", result.stderr)
                if match is None:
                    raise RuntimeError(f"{mode}: missing persistence observations")
                counts = tuple(int(value) for value in match[1].split(b","))
                if counts[0] != 0 or counts[5] != 0:
                    raise RuntimeError(f"{mode}: persistence construction/member-limit rejection allocated: {counts}")
                observations.append(counts)
            print(f"PASS persistence {mode}/{coordinates}: members 1/32/1024 requested bytes {observations}")
        failed = subprocess.run([binary, "1024", "0", "wide"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: persistence ceiling negative control failed")
        print(f"PASS persistence {mode}: allocation negative control")


def verify_calendar_persistence(target: str) -> None:
    """Native calendar persistence preserves resolution without lowering."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/calendar_persistence_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"calendar-persistence-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for qualifications in (0, 8):
            observations = []
            for digits in range(1, 7):
                result = subprocess.run([binary, str(digits), str(qualifications), "65536", "2147483647"], capture_output=True, timeout=5)
                if result.returncode or result.stdout != b"calendar=preserved,qualifications=preserved,limits=rejected\n":
                    raise RuntimeError(f"{mode}/{qualifications}/{digits}: native calendar resources failed: {result.stderr!r}")
                match = re.search(rb" work=((?:\d+,){5}\d+)\n$", result.stderr)
                if match is None:
                    raise RuntimeError(f"{mode}: missing native calendar observations")
                observations.append(tuple(int(value) for value in match[1].split(b",")))
            print(f"PASS calendar persistence {mode}/{qualifications} qualifications: fraction widths1..6 requested bytes {observations}")
        failed = subprocess.run([binary, "6", "8", "0", "2147483647"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: native calendar ceiling negative control failed")
        print(f"PASS calendar persistence {mode}: allocation negative control")


def verify_explanation(target: str) -> None:
    """Bound fact reads and embedded text independently of retained inputs."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/explanation_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"explanation-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for text_size in (4, 524288):
            observations = []
            for transitions in (2, 16384):
                result = subprocess.run([binary, str(transitions), str(text_size), "65536"], capture_output=True, timeout=5)
                if result.returncode or result.stdout != b"render=bounded,instant=known,presentation=unsupported\n":
                    raise RuntimeError(f"{mode}/{text_size}/{transitions}: explanation resources failed: {result.stderr!r}")
                match = re.search(rb" work=((?:\d+,){6}\d+)\n$", result.stderr)
                if match is None:
                    raise RuntimeError(f"{mode}: missing explanation observations")
                counts = tuple(int(value) for value in match[1].split(b","))
                if counts[:3] != (0, 0, 0) or counts[6] != 0:
                    raise RuntimeError(f"{mode}: explanation construction/zero-budget reads allocated: {counts}")
                observations.append(counts)
            if observations[0] != observations[1]:
                raise RuntimeError(f"{mode}: rendering traffic depends on retained transitions: {observations}")
            print(f"PASS explanation {mode}/{text_size * 2} metadata bytes: 2/16384 transitions requested bytes {observations[0]}; 100000 paired fact reads")
        failed = subprocess.run([binary, "16384", "524288", "0"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: explanation ceiling negative control failed")
        print(f"PASS explanation {mode}: allocation negative control")


def verify_declaration_explanation(target: str) -> None:
    """Large nominal quantities remain facts, without end computation."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/declaration_explanation_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"declaration-explanation-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for kind in range(5):
            observations = []
            for days in (1, 9223372036854775807):
                for form in ("utc", "local"):
                    result = subprocess.run([binary, str(kind), str(days), form, "65536"], capture_output=True, timeout=5)
                    if result.returncode or result.stdout != b"facts=preserved,render=bounded,end=not-invented\n":
                        raise RuntimeError(f"{mode}/{kind}/{days}/{form}: declaration explanation failed: {result.stderr!r}")
                    match = re.search(rb" work=((?:\d+,){4}\d+)\n$", result.stderr)
                    if match is None:
                        raise RuntimeError(f"{mode}: missing declaration explanation observations")
                    counts = tuple(int(value) for value in match[1].split(b","))
                    if counts[:2] != (0, 0):
                        raise RuntimeError(f"{mode}: declaration fact/zero budget reads allocated: {counts}")
                    observations.append(counts)
            print(f"PASS declaration explanation {mode}/kind{kind}: day1/max UTC/local requested bytes {observations}; 100000 fact reads")
        failed = subprocess.run([binary, "4", "9223372036854775807", "local", "0"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: declaration explanation negative control failed")
        print(f"PASS declaration explanation {mode}: allocation negative control")

def verify_snapshot_persistence(target: str) -> None:
    """Persist full finite rule evidence and reject oversize input before encoding."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/snapshot_persistence_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"snapshot-persistence-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for count, metadata in ((0, 16), (2, 16), (1024, 16), (1025, 16), (16384, 16), (2, 4097)):
            rejected = count > 1024 or metadata > 4096
            result = subprocess.run([binary, str(count), str(metadata), "8388608"], capture_output=True, timeout=5)
            expected = b"rejected-before-encoding\n" if rejected else b"snapshot=restored,reads=stored\n"
            if result.returncode or result.stdout != expected:
                raise RuntimeError(f"{mode}/{count}/{metadata}: snapshot persistence failed: {result.stderr!r}")
            match = re.search(rb" work=([0-9,]+)\n$", result.stderr)
            if match is None:
                raise RuntimeError(f"{mode}: missing snapshot persistence observations")
            counts = tuple(int(value) for value in match[1].split(b","))
            if (rejected and counts != (0,)) or (not rejected and (len(counts) != 4 or counts[-1] != 0)):
                raise RuntimeError(f"{mode}: snapshot persistence resource assertions failed: {counts}")
            print(f"PASS snapshot persistence {mode}/{count} transitions/{metadata} metadata bytes: requested bytes {counts}")
        failed = subprocess.run([binary, "2", "16", "0"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: snapshot persistence negative control failed")
        print(f"PASS snapshot persistence {mode}: allocation negative control")

def verify_civil_persistence(target: str) -> None:
    """Repeated civil labels preserve policies and disconnected selection members."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/civil_persistence_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"civil-persistence-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for form in ("boundary", "selection"):
            for count in (0, 2, 64, 256, 512, 1023, 1024, 1025):
                rejected = count > 1024 or (form == "selection" and count >= 1024)
                result = subprocess.run([binary, str(count), form, "2097152"], capture_output=True, timeout=10)
                expected = b"civil=rejected-before-encoding\n" if rejected else b"civil=restored,coverage=preserved\n"
                if result.returncode or result.stdout != expected:
                    raise RuntimeError(f"{mode}/{count}/{form}: civil persistence failed: {result.stderr!r}")
                match = re.search(rb" work=([0-9,]+)\n$", result.stderr)
                if match is None:
                    raise RuntimeError(f"{mode}: missing civil persistence observations")
                counts = tuple(int(value) for value in match[1].split(b","))
                if (rejected and counts != (0,)) or (not rejected and (len(counts) != 6 or counts[3] != 0)):
                    raise RuntimeError(f"{mode}: civil persistence resource assertions failed: {counts}")
                print(f"PASS civil persistence {mode}/{form}/{count} transitions: requested bytes {counts}")
        failed = subprocess.run([binary, "2", "selection", "0"], capture_output=True, timeout=10)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: civil persistence negative control failed")
        print(f"PASS civil persistence {mode}: allocation negative control")

def verify_selection_explanation(target: str) -> None:
    """Fixed semantic fact budgets over retained coverage and civil providers."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/selection_explanation_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"selection-explanation-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for count in (2, 16384):
            for text_size in (4, 524288):
                for kind in ("coverage", "boundary", "selection", "batch"):
                    for ownership in ("owned", "shared", "sliced"):
                        result = subprocess.run([binary, str(count), str(text_size), kind, ownership, "65536"],
                                                capture_output=True, timeout=5)
                        if result.returncode or result.stdout != b"selection=facts-bounded,incompleteness-preserved\n":
                            raise RuntimeError(f"{mode}/{count}/{text_size}/{kind}/{ownership}: explanation failed: {result.stderr!r}")
                        match = re.search(rb" work=([0-9,]+)\n$", result.stderr)
                        if match is None:
                            raise RuntimeError("missing selection explanation allocation observations")
                        counts = tuple(int(value) for value in match[1].split(b","))
                        if len(counts) != 6 or counts[:3] != (0, 0, 0):
                            raise RuntimeError(f"selection explanation unexpected allocation: {counts}")
                        print(f"PASS selection explanation {mode}/{count}/{text_size}/{kind}/{ownership}: requested bytes {counts}")
        failed = subprocess.run([binary, "2", "4", "batch", "shared", "0"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: selection explanation negative control failed")
        print(f"PASS selection explanation {mode}: allocation negative control")

def verify_recurrence_explanation(target: str) -> None:
    """Bounded declaration facts independent of series and selector extent."""
    roc = os.environ.get("ROC", "roc")
    source = "tests/recurrence_explanation_resource/main.roc"
    subprocess.run([roc, "check", source], cwd=ROOT, check=True, timeout=120)
    for mode in ("dev", "speed"):
        binary = BUILD / f"recurrence-explanation-{mode}"
        subprocess.run([roc, "build", source, f"--opt={mode}", f"--target={target}",
                        f"--output={binary}", "--no-cache"], cwd=ROOT, check=True, timeout=120)
        for count in (2, 4096):
            for termination in ("forever", "count"):
                for kind in ("date", "timed", "rfc"):
                    result = subprocess.run([binary, str(count), termination, kind, "65536"], capture_output=True, timeout=5)
                    if result.returncode or result.stdout != b"recurrence=declaration,budget=bounded\n":
                        raise RuntimeError(f"{mode}/{count}/{termination}/{kind}: recurrence explanation failed: {result.stderr!r}")
                    match = re.search(rb" work=([0-9,]+)\n$", result.stderr)
                    if match is None:
                        raise RuntimeError("missing recurrence explanation allocation observations")
                    counts = tuple(int(value) for value in match[1].split(b","))
                    if len(counts) != 6 or counts[:3] != (0, 0, 0):
                        raise RuntimeError(f"recurrence explanation unexpected allocation: {counts}")
                    print(f"PASS recurrence explanation {mode}/{count}/{termination}/{kind}: requested bytes {counts}")
        failed = subprocess.run([binary, "2", "forever", "date", "0"], capture_output=True, timeout=5)
        if failed.returncode == 0 or b"ROC_ASSERT_FAILED" not in failed.stderr:
            raise RuntimeError(f"{mode}: recurrence explanation negative control failed")
        print(f"PASS recurrence explanation {mode}: allocation negative control")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="build and run instrumented temporal probes")
    options = parser.parse_args()
    selected_target = build_host()
    if options.verify:
        verify_probe(selected_target)
        verify_recurrence(selected_target)
        verify_intervals(selected_target)
        verify_interchange(selected_target)
        verify_persistence(selected_target)
        verify_calendar_persistence(selected_target)
        verify_explanation(selected_target)
        verify_declaration_explanation(selected_target)
        verify_snapshot_persistence(selected_target)
        verify_civil_persistence(selected_target)
        verify_selection_explanation(selected_target)
        verify_recurrence_explanation(selected_target)
    else:
        print(selected_target)
