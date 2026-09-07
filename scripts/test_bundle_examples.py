#!/usr/bin/env python3
from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urlsplit


sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DEPENDENCY_RE = re.compile(r'(?m)^(\s*time:\s*)"[^"]+"')
SKIPPED_EXAMPLES: dict[str, str] = {}


def roc_command() -> str:
    roc = os.environ.get("ROC", "roc")
    if "/" in roc or "\\" in roc:
        return str(Path(roc).resolve())
    return roc


ROC = roc_command()
REHEARSAL_VERSION = "0.1.0-rc1"


def release_asset_name(source: Path, role: str) -> str:
    """Name raw roc bundle output while preserving supplied release filenames."""
    if re.fullmatch(r"[1-9A-HJ-NP-Za-km-z]+\.tar\.zst", source.name):
        prefix = "roc-time" if role == "core" else "roc-time-tzdb"
        return f"{prefix}-{source.name}"
    return source.name


def bare_asset_name(source: Path) -> str:
    match = re.search(r"([1-9A-HJ-NP-Za-km-z]+\.tar\.zst)$", source.name)
    if not match:
        raise ValueError(f"Archive has no trailing content hash: {source.name}")
    return match.group(1)


def run(cmd: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(cmd))
    completed = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if completed.returncode != 0:
        if completed.stdout:
            print(completed.stdout)
        if completed.stderr:
            print(completed.stderr, file=sys.stderr)
        raise SystemExit(f"command failed with exit code {completed.returncode}: {' '.join(cmd)}")

    return completed


def bundle_package(bundle_dir: Path, *, env: dict[str, str] | None = None) -> Path:
    completed = run([sys.executable, "scripts/bundle.py", "--output-dir", str(bundle_dir)], env=env)
    match = re.search(r"^Created:\s+(.+\.tar\.zst)\s*$", completed.stdout, re.MULTILINE)

    if match is None:
        raise SystemExit("Could not find bundle path in roc bundle output")

    bundle_path = Path(match.group(1))
    if not bundle_path.exists():
        raise SystemExit(f"Bundle was not created: {bundle_path}")

    return bundle_path


def start_server(directory: Path, requests: list[str] | None = None) -> tuple[http.server.ThreadingHTTPServer, str]:
    class Handler(http.server.SimpleHTTPRequestHandler):
        def send_response(self, code: int, message: str | None = None) -> None:
            if requests is not None and self.command == "GET" and code == 200:
                requests.append(unquote(urlsplit(self.path).path))
            super().send_response(code, message)

    handler = functools.partial(Handler, directory=str(directory))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{server.server_port}"


def copy_examples_with_bundle_url(examples_dir: Path, bundle_url: str, zone_url: str) -> list[Path]:
    from roc_version import package_pin
    from update_example_urls import copy_examples
    return copy_examples(examples_dir / "examples", bundle_url, zone_url,
                         compiler=package_pin(ROOT))


def copy_internal_examples(destination: Path, core: str, zones: str) -> list[Path]:
    """Stage unreleased caller evidence separately from published examples."""
    from roc_version import package_pin
    from update_example_urls import copy_examples
    entries = []
    for name in ("appointment_display", "zoned_appointment", "clock_deadline_checks", "invoice_report", "invoice_report_checks"):
        entries.extend(copy_examples(destination / name, core, zones,
                                    compiler=package_pin(ROOT),
                                    source=ROOT / "tests" / name))
    # The deterministic root drives the exact pure module used by the real
    # clock application. Never maintain a test-local copy of its implementation.
    shutil.copy2(ROOT / "examples/clock_deadline/Deadline.roc",
                 destination / "clock_deadline_checks/Deadline.roc")
    shutil.copy2(ROOT / "tests/invoice_report/InvoiceReport.roc",
                 destination / "invoice_report_checks/InvoiceReport.roc")
    return entries


def run_example_checks(examples: list[Path], *, env: dict[str, str] | None = None) -> None:
    for example in examples:
        run([ROC, "check", example.name, "--no-cache"], cwd=example.parent, env=env)


def run_example_apps(examples: list[Path], *, env: dict[str, str] | None = None, expected_dir: Path | None = None) -> None:
    for example in examples:
        before = time.time_ns()
        result = run([ROC, example.name, "--no-cache"], cwd=example.parent, env=env)
        check_output(example, result.stdout, expected_dir=expected_dir,
                     clock_window=(before, time.time_ns()))


def check_clock_output(actual: str, window: tuple[int, int]) -> None:
    """Real-clock smoke evidence; fixed temporal fixtures never read the clock."""
    try:
        record = json.loads(actual)
        if not isinstance(record, dict) or set(record) != {"checked_at", "expires_at", "expired"}:
            raise ValueError("unexpected record fields")
        epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
        points = {}
        for name in ("checked_at", "expires_at"):
            text = record[name]
            if not isinstance(text, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z", text):
                raise ValueError("expected exact UTC microsecond text")
            delta = datetime.fromisoformat(text[:-1] + "+00:00") - epoch
            points[name] = (delta.days * 86400 + delta.seconds) * 1_000_000 + delta.microseconds
        if record["expires_at"] != "2030-01-01T00:00:00.000000Z":
            raise ValueError("expiry changed")
        if type(record["expired"]) is not bool or record["expired"] != (points["checked_at"] >= points["expires_at"]):
            raise ValueError("expiry status disagrees with record boundaries")
        # Bracket the reading with wall-clock observations and a small tolerance.
        # This witnesses a current reading, not clock accuracy or stability;
        # wall-clock steps can widen the bracket in either direction.
        lower, upper = min(window) // 1000 - 1_000_000, max(window) // 1000 + 1_000_000
        if points["checked_at"] <= 0 or not lower <= points["checked_at"] <= upper:
            raise ValueError("reading is not near the actual host clock")
    except (ValueError, TypeError, OverflowError) as error:
        raise SystemExit(f"Invalid live clock record: {error}") from error


def check_output(example: Path, actual: str, *, expected_dir: Path | None = None,
                 clock_window: tuple[int, int] | None = None) -> None:
    if example.parent.name == "clock_deadline":
        if clock_window is None:
            raise SystemExit("Missing live clock observation window")
        check_clock_output(actual, clock_window)
        return
    expected = (expected_dir or ROOT / "tests" / "examples") / f"{example.parent.name}.txt"
    if example.parent.name in {"booking_exchange", "archive_search", "staffing", "appointment_display", "zoned_appointment", "clock_deadline_checks", "invoice_report", "invoice_report_checks"} and not expected.is_file():
        raise SystemExit(f"Missing required output fixture: {expected}")
    if expected.exists() and actual != expected.read_text(encoding="utf-8"):
        raise SystemExit(f"Unexpected output from {example.parent.name}:\n{actual}")


def build_and_run_examples(examples: list[Path], build_dir: Path, *, env: dict[str, str] | None = None,
                           optimization: str = "dev") -> None:
    build_dir.mkdir(parents=True, exist_ok=True)
    empty_cwd = build_dir / "empty-cwd"
    empty_cwd.mkdir()
    exe_suffix = ".exe" if os.name == "nt" else ""

    for example in examples:
        output = build_dir / f"{example.parent.name}{exe_suffix}"
        run([ROC, "build", example.name, f"--opt={optimization}", f"--output={output}", "--no-cache"], cwd=example.parent, env=env)
        before = time.time_ns()
        result = run([str(output)], cwd=empty_cwd, env=env)
        check_output(example, result.stdout, clock_window=(before, time.time_ns()))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-path", type=Path, help="Use an existing bundle instead of creating one")
    parser.add_argument("--zone-bundle-path", type=Path, help="Exact optional zone-data bundle paired with --bundle-path")
    parser.add_argument("--skip-build-run", action="store_true", help="Skip compiled example execution")
    args = parser.parse_args()
    if (args.bundle_path is None) != (args.zone_bundle_path is None):
        parser.error("--bundle-path and --zone-bundle-path must be supplied together")

    default_tmp = ROOT / ".roc-time-tmp"
    tmp_parent = Path(os.environ.get("ROC_TIME_TMPDIR", default_tmp)).resolve()
    tmp_parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="roc-time-bundle-", dir=tmp_parent) as tmp:
        tmp_dir = Path(tmp)
        served = tmp_dir / "served"
        bundle_dir = served / REHEARSAL_VERSION
        examples_dir = tmp_dir / "rewritten"
        build_dir = tmp_dir / "build"

        bundle_dir.mkdir(parents=True)
        examples_dir.mkdir()

        cache_dir = tmp_dir / "cache"
        cache_dir.mkdir()
        env = {**os.environ, "XDG_CACHE_HOME": str(cache_dir)}
        if args.bundle_path is None:
            bundle_path = bundle_package(bundle_dir, env=env)
            zone_result = run([sys.executable, "scripts/bundle.py", "--package-dir", str(ROOT / "tzdb/package"), "--output-dir", str(bundle_dir)], env=env)
            zone_match = re.search(r"^Created:\s+(.+\.tar\.zst)\s*$", zone_result.stdout, re.MULTILINE)
            if zone_match is None:
                raise SystemExit("Could not find zone bundle output")
            zone_bundle = Path(zone_match.group(1))
        else:
            source_bundle = args.bundle_path.resolve()
            source_zone = args.zone_bundle_path.resolve()
            for source in (source_bundle, source_zone):
                if not source.is_file():
                    raise SystemExit(f"Bundle does not exist: {source}")
            if source_bundle.name == source_zone.name:
                raise SystemExit("Core and zone bundles must have distinct artifact filenames")
            bundle_path = bundle_dir / source_bundle.name
            zone_bundle = bundle_dir / source_zone.name
            shutil.copy2(source_bundle, bundle_path)
            shutil.copy2(source_zone, zone_bundle)

        for role, source in (("core", bundle_path), ("zones", zone_bundle)):
            target = bundle_dir / release_asset_name(source, role)
            if target != source:
                shutil.copy2(source, target)
            if role == "core":
                bundle_path = target
            else:
                zone_bundle = target
        requests: list[str] = []
        server, base_url = start_server(served, requests)
        try:
            base_url = f"{base_url}/{REHEARSAL_VERSION}"
            bundle_url = f"{base_url}/{bundle_path.name}"
            examples = copy_examples_with_bundle_url(examples_dir, bundle_url, f"{base_url}/{zone_bundle.name}")

            print(f"Testing examples with bundled package: {bundle_url}")
            run_example_checks(examples, env=env)
            run_example_apps(examples, env=env)

            internal = copy_internal_examples(tmp_dir / "internal-scenarios", bundle_url, f"{base_url}/{zone_bundle.name}")
            print("Testing unreleased caller scenarios against the same core archive.")
            run_example_checks(internal, env=env)
            run_example_apps(internal, env=env)

            if not args.skip_build_run:
                build_and_run_examples(examples, build_dir, env=env)
                build_and_run_examples(internal, tmp_dir / "internal-build", env=env)
            missing = {f"/{REHEARSAL_VERSION}/{bundle_path.name}", f"/{REHEARSAL_VERSION}/{zone_bundle.name}"} - set(requests)
            if missing:
                raise SystemExit(f"Roc did not acquire both exact bundles from the isolated server: {sorted(missing)}")
            print("Verified cold acquisition of both core and zone archives.")
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
