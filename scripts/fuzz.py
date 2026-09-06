#!/usr/bin/env python3
"""Pinned roc-fuzz builds, bounded campaigns, replay, and failure-lifecycle checks."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "tests"
DATA = SOURCES / "fuzz"
WORK = Path(os.environ.get("ROC_TIME_TMPDIR", ROOT / ".roc-time-tmp")).resolve() / "fuzz"
SEMANTIC = ("precision", "spans", "coverage", "gregorian", "arithmetic", "calendars", "clock", "offsets", "zones", "events", "patterns", "recurrence", "descriptions")
ROC = os.environ.get("ROC", "roc")
if "/" in ROC or "\\" in ROC:
    ROC = str(Path(ROC).resolve())


def command(args: list[str], *, cwd: Path = ROOT, expected: int = 0,
            timeout: int = 120, log: Path | None = None) -> str:
    print("+", " ".join(args), flush=True)
    proc = subprocess.Popen(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, start_new_session=True)
    try:
        output, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        output, _ = proc.communicate()
        if log is not None:
            log.write_text(output)
        raise SystemExit(f"Command exceeded {timeout}s: {' '.join(args)}\n{output}")
    if log is not None:
        log.write_text(output)
    if proc.returncode != expected:
        raise SystemExit(f"Expected exit {expected}, got {proc.returncode}:\n{output}")
    return output


def environment() -> str | None:
    host = (platform.system(), platform.machine().lower())
    target = {("Darwin", "arm64"): "arm64mac", ("Linux", "x86_64"): "x64musl"}.get(host)
    if target is None:
        print(f"UNVERIFIED: roc-fuzz does not support configured host {host}; no fuzz checks ran")
        return None
    expected = "Roc compiler version " + (ROOT / ".roc-version").read_text().strip()
    version = command([ROC, "version"]).strip()
    if version != expected:
        raise SystemExit(f"Expected {expected}, got {version}; select the compiler with ROC")
    WORK.mkdir(parents=True, exist_ok=True)
    dependency = json.loads((DATA / "dependency.json").read_text())
    print(f"{version}; LLVM speed backend with --fuzz; target={target}; roc-fuzz={dependency['version']} ({dependency['revision']})", flush=True)
    archive = WORK / "release.tar.zst"
    if not archive.exists():
        pending = WORK / "release.download"
        command(["curl", "-L", "--fail", "--retry", "2", dependency["url"], "-o", str(pending)])
        if hashlib.sha256(pending.read_bytes()).hexdigest() != dependency["sha256"]:
            raise SystemExit("roc-fuzz release SHA-256 mismatch")
        pending.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != dependency["sha256"]:
        raise SystemExit("Cached roc-fuzz release SHA-256 mismatch")
    # Targets use the content-addressed release URL directly. No local platform
    # path is substituted; Roc also performs its package integrity validation.
    for name in (*SEMANTIC, "lifecycle", "lifecycle_fixed"):
        source = SOURCES / name / "main.roc"
        urls = re.findall(r'\bfuzz\s*:\s*platform\s*"([^"]+)"', source.read_text())
        if urls != [dependency["url"]]:
            raise SystemExit(f"{source}: expected pinned roc-fuzz URL")
    return target


def build(name: str, target: str) -> Path:
    binary = WORK / name
    root = SOURCES / name / "main.roc"
    command([ROC, "check", str(root)])
    command([ROC, "build", "--fuzz", "--opt=speed", f"--target={target}", str(root), f"--output={binary}"],
            log=WORK / f"{name}-build.log")
    return binary


def replay(name: str, binary: Path) -> None:
    for raw in curated_inputs(name):
        output = command([str(binary), "replay", str(raw)], cwd=WORK,
                         timeout=10, log=WORK / f"{name}-replay-{raw.name}.log")
        if "Executed" not in output:
            raise SystemExit(f"Replay did not confirm execution:\n{output}")
    if name == "spans":
        for case in json.loads((DATA / "span_cases.json").read_text()):
            raw = DATA / "corpus/spans" / case["file"]
            shown = command([str(binary), "show", str(raw)], cwd=WORK, timeout=10)
            fields = {key: int(value) for key, value in re.findall(r'\b([abcd]): (-?\d+)', shown)}
            if fields != case["input"]:
                raise SystemExit(f"Named relation case {case['file']} changed meaning: {shown}")


def curated_inputs(name: str) -> list[Path]:
    directory = DATA / "corpus" / name
    inputs = sorted(path for path in directory.iterdir() if path.is_file())
    if not inputs:
        raise SystemExit(f"Missing curated inputs for {name}")
    if any(path.stat().st_size > 256 for path in inputs):
        raise SystemExit(f"Curated input exceeds the 256-byte campaign domain for {name}")
    return inputs


def campaign(name: str, binary: Path, args: argparse.Namespace) -> None:
    campaigns = WORK / "campaigns"
    campaigns.mkdir(exist_ok=True)
    session = Path(tempfile.mkdtemp(prefix=f"{name}-", dir=campaigns))
    corpus = session / "corpus"
    corpus.mkdir()
    for raw in curated_inputs(name):
        shutil.copyfile(raw, corpus / raw.name)
    metadata = {
        "compiler": (ROOT / ".roc-version").read_text().strip(),
        "platform": json.loads((DATA / "dependency.json").read_text()),
        "host": [platform.system(), platform.machine()],
        "backend": "LLVM speed --fuzz",
        "runs": args.runs, "seconds": args.seconds, "seed": args.seed,
        "max_input_bytes": 256, "rss_limit_mb": 256, "input_timeout_seconds": 2,
        "sources_sha256": {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in [*sorted((SOURCES / name).glob("*.roc")), *sorted((ROOT / "package").glob("*.roc"))]
        },
        "corpus_sha256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(corpus.iterdir())},
    }
    (session / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    output = command([str(binary), "run", str(corpus), f"--runs={args.runs}",
                      f"--time={args.seconds}", f"--seed={args.seed}", "--max-input-size=256",
                      "--memory-limit=256", "--timeout=2"], cwd=session,
                     timeout=args.seconds + 30, log=session / "run.log")
    if "inline 8-bit counters" not in output or "DONE" not in output:
        raise SystemExit(f"No coverage-guided completion evidence:\n{output}")
    print("\n".join(output.splitlines()[-3:]), flush=True)
    print(f"Campaign evidence: {session}", flush=True)


def lifecycle(target: str) -> None:
    bad = build("lifecycle", target)
    fixed = build("lifecycle_fixed", target)
    session = Path(tempfile.mkdtemp(prefix="lifecycle-", dir=WORK))
    corpus = session / "corpus"
    corpus.mkdir()
    (corpus / "trigger").write_bytes(b"before*after")
    output = command([str(bad), "run", str(corpus), "--runs=100", "--time=5", "--seed=1",
                      "--max-input-size=32", "--memory-limit=256", "--timeout=2"],
                     cwd=session, expected=77, timeout=15, log=session / "failure.log")
    if "intentional lifecycle defect" not in output:
        raise SystemExit("Lifecycle failed for an unrelated reason")
    artifacts = sorted((session / ".roc-fuzz").glob("crash-*"))
    if not artifacts:
        raise SystemExit("Lifecycle failure did not save a reproducer")
    raw = artifacts[0]
    shown = command([str(bad), "show", str(raw)], cwd=session, timeout=10)
    if "42" not in shown:
        raise SystemExit("Saved lifecycle input does not contain the defect trigger")
    command([str(bad), "replay", str(raw)], cwd=session, expected=77, timeout=10)
    # Use the ordinary passing-command path too: an actual target failure must
    # fail that gate, rather than being accepted just because it was anticipated.
    try:
        command([str(bad), "replay", str(raw)], cwd=session, timeout=10)
    except SystemExit as failure:
        message = str(failure)
        if not message.startswith("Expected exit 0, got 77:") or "intentional lifecycle defect" not in message:
            raise SystemExit(f"Unexpected failure-gate result: {message}")
    else:
        raise SystemExit("Ordinary passing-command gate accepted the intentional failure")
    minimized = session / "minimized"
    command([str(bad), "minimize", str(raw), str(minimized)], cwd=session,
            timeout=30, log=session / "minimize.log")
    if not minimized.exists() or minimized.read_bytes() != b"*":
        raise SystemExit(f"Expected a one-byte minimized lifecycle case; inspect {session}")
    command([str(bad), "show", str(minimized)], cwd=session, timeout=10)
    command([str(bad), "replay", str(minimized)], cwd=session, expected=77, timeout=10)
    command([str(fixed), "replay", str(minimized)], cwd=session, timeout=10)
    regression = DATA / "corpus/lifecycle_fixed/byte-42"
    command([str(fixed), "replay", str(regression)], cwd=session, timeout=10)
    print(f"PASS failure lifecycle: exit 77, saved/show/replay/minimize, fixed regression; evidence {session}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--operation", choices=["build", "replay", "run", "lifecycle", "all"], default="all")
    parser.add_argument("--targets", nargs="+", choices=SEMANTIC, default=list(SEMANTIC))
    parser.add_argument("--runs", type=int, default=10000)
    parser.add_argument("--seconds", type=int, default=5)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    if args.runs <= 0 or args.seconds <= 0 or args.seed <= 0:
        parser.error("runs, seconds, and seed must be positive; campaigns must be bounded")
    target = environment()
    if target is None:
        return
    if args.operation != "lifecycle":
        for name in args.targets:
            binary = build(name, target)
            if args.operation in ("replay", "all"):
                replay(name, binary)
            if args.operation in ("run", "all"):
                campaign(name, binary, args)
    if args.operation in ("lifecycle", "all"):
        lifecycle(target)


if __name__ == "__main__":
    main()
