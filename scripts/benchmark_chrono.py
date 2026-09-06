#!/usr/bin/env python3
"""Narrow, validated in-process roc-time / chrono microbenchmarks."""
from roc_version import package_pin
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import fixture_platform

BASE = ROOT / "benchmarks/chrono"
BUILD = ROOT / ".roc-time-tmp/chrono-benchmark"
MODES = ("date_control", "date_to_day", "construct", "roundtrip", "add_days", "parse", "resolve", "format", "end_to_end")


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, check=True, timeout=180, **kwargs)


def oracle(text):
    value = dt.datetime.fromisoformat(text)
    delta = value.astimezone(dt.timezone.utc) - dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
    micros = (delta.days * 86400 + delta.seconds) * 1000000 + delta.microseconds
    return {"text": text, "day": (value.date() - dt.date(1970, 1, 1)).days,
            "microseconds": micros, "canonical": value.isoformat(timespec="microseconds")}


def expected_sum(corpus, mode, iterations):
    values = []
    for case in corpus:
        date = dt.datetime.fromisoformat(case["text"]).date()
        if mode == "add_days":
            date += dt.timedelta(days=17)
        if mode in ("date_control", "construct", "roundtrip", "add_days"):
            values.append(date.year * 10000 + date.month * 100 + date.day)
        elif mode == "date_to_day":
            shifted_day = case["day"] + 1000000
            if not 0 <= shifted_day < 2**64:
                raise ValueError("day-coordinate checksum outside unsigned range")
            values.append(shifted_day)
        elif mode in ("parse", "resolve"):
            values.append(case["microseconds"] % 1000000007)
        elif mode in ("format", "end_to_end"):
            values.append(sum(case["canonical"].encode("ascii")))
        else:
            raise ValueError(f"unknown workload: {mode}")
    cycles, tail = divmod(iterations, len(values))
    return cycles * sum(values) + sum(values[:tail])


def parse_samples(output, samples, expected):
    lines = output.splitlines()
    if len(lines) != samples:
        raise ValueError("wrong number of timing records")
    result = []
    for line in lines:
        elapsed, checksum = map(int, line.split(","))
        if elapsed <= 0 or checksum != expected:
            raise ValueError(f"invalid timing/checksum: {line}; expected {expected}")
        result.append(elapsed)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="download locked Cargo dependencies once")
    parser.add_argument("--smoke", action="store_true", help="1000 iterations, one warmup, three samples; not performance conclusions")
    parser.add_argument("--iterations", type=int, default=100000)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--samples", type=int, default=9)
    parser.add_argument("--roc-opt", choices=("dev", "speed"), default="speed")
    options = parser.parse_args()
    if options.smoke:
        options.iterations, options.warmups, options.samples = 1000, 1, 3
    if not (1 <= options.iterations <= 10000000 and 1 <= options.samples <= 50 and 0 <= options.warmups <= 10):
        parser.error("iterations 1..10000000, samples 1..50, warmups 0..10")
    roc = os.environ.get("ROC", "roc")
    roc_version = subprocess.check_output([roc, "version"], text=True).strip()
    if package_pin(ROOT) not in roc_version:
        raise RuntimeError(f"compiler does not match the package header: {roc_version}")
    BUILD.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "CARGO_HOME": str(ROOT / ".roc-time-tmp/chrono-cargo"),
           "CARGO_TARGET_DIR": str(BUILD / "cargo-target")}
    if options.fetch:
        run(["cargo", "fetch", "--locked", "--manifest-path", str(BASE / "Cargo.toml")], env=env)
    target = fixture_platform.build_host()
    # Reuse the fixture ABI but isolate libc-allocation host artifacts. The
    # default resource host remains DebugAllocator and is never overwritten.
    host_command = [os.environ.get("ZIG", "zig"), "build", "--build-file", str(ROOT / "tests/platform/build.zig"),
                    "--prefix", str(BUILD / "host"), "--cache-dir", str(BUILD / "host-cache"),
                    "--global-cache-dir", str(BUILD / "global-cache"),
                    "-Doptimize=ReleaseFast", "-Dbenchmark-allocator=true"]
    if target == "x64musl":
        host_command.append("-Dtarget=x86_64-linux-musl")
    run(host_command)
    destination = BUILD / "targets" / target
    destination.mkdir(parents=True, exist_ok=True)
    for artifact in (fixture_platform.BUILD / "targets" / target).iterdir():
        if artifact.is_file():
            shutil.copyfile(artifact, destination / artifact.name)
    shutil.copyfile(BUILD / "host/lib/libhost.a", destination / "libhost.a")
    rust_target = {"x64musl": "x86_64-unknown-linux-musl", "arm64mac": "aarch64-apple-darwin"}[target]
    run([roc, "check", str(BASE / "main.roc")])
    roc_binary = BUILD / f"roc-{options.roc_opt}"
    run([roc, "build", str(BASE / "main.roc"), f"--opt={options.roc_opt}",
         f"--target={target}", f"--output={roc_binary}", "--no-cache"])
    run(["cargo", "build", "--offline", "--locked", "--release", "--target", rust_target,
         "--manifest-path", str(BASE / "Cargo.toml")], env=env)
    rust_binary = BUILD / "cargo-target" / rust_target / "release/roc-time-chrono-benchmark"
    corpus_bytes = (BASE / "corpus.jsonl").read_bytes()
    corpus = [json.loads(line) for line in corpus_bytes.splitlines()]
    if not corpus or any(case != oracle(case["text"]) for case in corpus):
        raise ValueError("corpus disagrees with independent Python datetime oracle")
    inputs = [case["text"] for case in corpus]
    expected = "".join(f'{case["day"]}|{case["microseconds"]}|{case["canonical"]}\n' for case in corpus)
    binaries = [("roc-time", roc_binary), ("chrono", rust_binary)]
    for name, binary in binaries:
        observed = run([str(binary), "verify", "1", "0", "0", *inputs], capture_output=True, text=True)
        if observed.stdout != expected:
            raise ValueError(f"{name} differs from independent per-case oracle")
    # Always exercise rejection: matching output count alone is insufficient.
    try:
        parse_samples("10,2\n", 1, 1)
    except ValueError:
        pass
    else:
        raise AssertionError("checksum negative control failed")
    results = []
    # Alternate language order between workloads; never run timed jobs in parallel.
    for index, mode in enumerate(MODES):
        for name, binary in (binaries if index % 2 == 0 else binaries[::-1]):
            output = run([str(binary), mode, str(options.iterations), str(options.warmups),
                          str(options.samples), *inputs], capture_output=True, text=True)
            elapsed = parse_samples(output.stdout, options.samples, expected_sum(corpus, mode, options.iterations))
            row = {"library": name, "workload": mode, "nanoseconds": elapsed,
                   "median_ns_per_operation": statistics.median(elapsed) / options.iterations}
            results.append(row)
            print(f'{name:8s} {mode:12s} median {row["median_ns_per_operation"]:.2f} ns/op')
    report = {"scope": "microsecond Gregorian fixed-offset intersection; no general library ranking",
              "options": vars(options), "roc_version": roc_version,
              "rustc": subprocess.check_output(["rustc", "-Vv"], text=True),
              "cargo": subprocess.check_output(["cargo", "--version"], text=True).strip(),
              "zig": subprocess.check_output([os.environ.get("ZIG", "zig"), "version"], text=True).strip(),
              "machine": platform.platform(), "processor": platform.processor(),
              "roc_target": target, "rust_target": rust_target,
              "allocators": {"roc": "libc via fixture ABI with header/counters", "rust": "Rust System allocator (libc)"},
              "corpus_sha256": hashlib.sha256(corpus_bytes).hexdigest(),
              "cargo_lock_sha256": hashlib.sha256((BASE / "Cargo.lock").read_bytes()).hexdigest(),
              "git_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "working_tree": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
              "results": results}
    run_id = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    destination = BUILD / f'results-{options.roc_opt}-{run_id}-{os.getpid()}.json'
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Validated corpus, checksums and negative control; raw timings: {destination}")


if __name__ == "__main__":
    main()
