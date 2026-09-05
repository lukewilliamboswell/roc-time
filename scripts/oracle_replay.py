"""Bounded JSONL oracle replay. Expectations never enter the compiled fixture.

The Python host validates records, passes only input argv to a single prebuilt
binary, and compares exact observations in corpus order despite parallel work.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from collections import deque
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time

MAX_CASES = 4096
MAX_CORPUS_BYTES = 4 * 1024 * 1024
CASE_TIMEOUT = 5
CASE_OUTPUT_BYTES = 16384
MAX_WORKERS = 16
TRACE = re.compile(r"ROC_TRACE protocol=1 mark=([0-9]+) allocations=([0-9]+)\n\Z")
INTEGER = re.compile(r"(?:0|-?[1-9][0-9]*)\Z")
METRICS = re.compile(r"ROC_METRICS protocol=1 allocations=([0-9]+) requested_bytes=([0-9]+) deallocations=([0-9]+) work=([0-9,]*)\n\Z")


def load_cases(path: Path, count: int) -> list[dict]:
    if type(count) is not int or not 0 < count <= MAX_CASES:
        raise ValueError("Invalid oracle case count")
    if path.stat().st_size > MAX_CORPUS_BYTES:
        raise ValueError("Oracle corpus exceeds byte budget")
    cases = []
    for line in path.read_text().splitlines():
        if len(line) > CASE_OUTPUT_BYTES:
            raise ValueError("Oracle case exceeds byte budget")
        case = json.loads(line, object_pairs_hook=unique_fields)
        if not isinstance(case, dict) or set(case) != {"id", "operation", "input", "expected", "evidence"}:
            raise ValueError("Invalid oracle record fields")
        if case["id"] != str(len(cases)):
            raise ValueError("Missing, duplicate or out-of-order oracle identity")
        if not isinstance(case["operation"], str) or not re.fullmatch(r"[a-z][a-z_]*", case["operation"]):
            raise ValueError("Invalid oracle operation")
        for field in ("input", "expected"):
            values = case[field]
            if not isinstance(values, list) or not 0 < len(values) <= 32 or any(
                not isinstance(v, str) or not v or len(v) > 256 or any(c in v for c in "\t\r\n\x00") for v in values
            ):
                raise ValueError(f"Invalid oracle {field}")
        if not isinstance(case["evidence"], str) or not case["evidence"]:
            raise ValueError("Missing oracle provenance class")
        cases.append(case)
        if len(cases) > count:
            raise ValueError("Unexpected oracle cases")
    if len(cases) != count:
        raise ValueError("Missing oracle cases")
    return cases


def unique_fields(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON field: {key}")
        result[key] = value
    return result


def validate_calendar_cases(cases: list[dict]) -> None:
    for case in cases:
        op, inputs, expected = case["operation"], case["input"], case["expected"]
        if op not in ("forward", "inverse") or len(inputs) != (3 if op == "forward" else 1):
            raise ValueError("Invalid calendar oracle operation/arity")
        if any(not INTEGER.fullmatch(n) for n in inputs):
            raise ValueError("Noncanonical calendar integer input")
        if not -(2**63) <= int(inputs[0]) < 2**63 or any(not 0 <= int(n) <= 255 for n in inputs[1:]):
            raise ValueError("Calendar oracle input outside transport domain")
        if expected[0] == "error":
            if len(expected) != 2 or expected[1] not in ("OutOfRange", "InvalidMonth", "InvalidDay"):
                raise ValueError("Unknown calendar expected failure")
        elif expected[0] == "ok":
            if len(expected) != (2 if op == "forward" else 4) or any(not INTEGER.fullmatch(n) for n in expected[1:]):
                raise ValueError("Invalid calendar expected observation")
        else:
            raise ValueError("Unknown calendar expected outcome")


def validate_zone_cases(cases: list[dict]) -> None:
    for case in cases:
        inputs, expected = case["input"], case["expected"]
        if case["operation"] != "resolve" or len(inputs) != 8 or any(not INTEGER.fullmatch(n) for n in inputs):
            raise ValueError("Invalid zone oracle input")
        values = list(map(int, inputs))
        if not 0 <= values[0] <= 2 or not -(2**63) <= values[1] < 2**63 or any(
            not 0 <= n <= 255 for n in values[2:7]
        ) or not 0 <= values[7] < 2**32:
            raise ValueError("Zone oracle input outside transport domain")
        if expected[0] != "ok" or len(expected) > 3 or any(not INTEGER.fullmatch(n) for n in expected[1:]):
            raise ValueError("Invalid zone oracle expected outcome")
        candidates = list(map(int, expected[1:]))
        if any(not -(2**63) <= n < 2**63 for n in candidates) or candidates != sorted(set(candidates)):
            raise ValueError("Invalid zone oracle candidates")


def compare(case: dict, output: str) -> None:
    expected = "\t".join([case["id"], *case["expected"]]) + "\n"
    if output != expected:
        raise ValueError(f"Oracle case {case['id']} mismatch: expected {expected!r}, observed {output!r}")


def parse_metrics(stderr: str) -> dict:
    lines = stderr.splitlines(keepends=True)
    match = METRICS.fullmatch(lines[-1]) if lines else None
    if not match:
        raise ValueError(f"Missing or malformed fixture metrics: {stderr[:300]!r}")
    traces = []
    for line in lines[:-1]:
        trace = TRACE.fullmatch(line)
        if not trace:
            raise ValueError(f"Malformed fixture trace: {line[:300]!r}")
        traces.append({"mark": int(trace[1]), "allocations": int(trace[2])})
    return dict(zip(("allocations", "requested_bytes", "deallocations"), map(int, match.groups()[:3])),
                work=[int(n) for n in match[4].split(",") if n], traces=traces)


def run_case(binary: Path, case: dict, session: Path) -> dict:
    command = [str(binary), case["id"], case["operation"], *case["input"]]
    started = time.monotonic()
    # Temporary disk files bound retained Python memory; retain inputs and output
    # on failure, not thousands of successful per-process transcript files.
    with tempfile.TemporaryFile(dir=session) as stdout, tempfile.TemporaryFile(dir=session) as stderr:
        proc = subprocess.Popen(command, cwd=session, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            while proc.poll() is None:
                if time.monotonic() - started > CASE_TIMEOUT:
                    raise ValueError("Oracle case exceeded time budget")
                if os.fstat(stdout.fileno()).st_size + os.fstat(stderr.fileno()).st_size > CASE_OUTPUT_BYTES:
                    raise ValueError("Oracle case exceeded output budget")
                time.sleep(0.002)
            if os.fstat(stdout.fileno()).st_size + os.fstat(stderr.fileno()).st_size > CASE_OUTPUT_BYTES:
                raise ValueError("Oracle case exceeded output budget")
            stdout.seek(0)
            stderr.seek(0)
            output, errors = stdout.read(CASE_OUTPUT_BYTES).decode(), stderr.read(CASE_OUTPUT_BYTES).decode()
            if proc.returncode:
                raise ValueError(f"Oracle fixture exited {proc.returncode}: {errors[:300]}")
            compare(case, output)
            metrics = parse_metrics(errors)
            if metrics["work"] != [1]:
                raise ValueError("Oracle fixture did not report exactly one completed operation")
            return {"id": case["id"], "observation": output[:-1].split("\t")[1:], "seconds": time.monotonic() - started, **metrics}
        except BaseException as error:
            if proc.poll() is None:
                try:
                    if os.name == "posix":
                        os.killpg(proc.pid, signal.SIGKILL)
                    else:
                        proc.kill()
                except ProcessLookupError:
                    pass  # The child exited between poll and termination.
                proc.wait()
            stdout.seek(0)
            stderr.seek(0)
            artifact = session / f"failure-{case['id']}.json"
            artifact.write_text(json.dumps({"case": case, "command": command, "error": str(error),
                "stdout": stdout.read(CASE_OUTPUT_BYTES).decode(errors="replace"),
                "stderr": stderr.read(CASE_OUTPUT_BYTES).decode(errors="replace")}, indent=2) + "\n")
            raise ValueError(f"Oracle case {case['id']} failed; inspect {artifact}: {error}") from error


def replay_cases(binary: Path, cases: list[dict], session: Path, workers: int) -> list[dict]:
    if type(workers) is not int or not 1 <= workers <= MAX_WORKERS:
        raise ValueError(f"Oracle workers must be between 1 and {MAX_WORKERS}")
    # At most workers pending/running tasks. map preserves corpus order; a fast
    # later failure cannot obscure an earlier failing identity.
    with ThreadPoolExecutor(max_workers=workers) as pool:
        pending = deque()
        remaining = iter(cases)
        for _ in range(workers):
            case = next(remaining, None)
            if case is not None:
                pending.append(pool.submit(run_case, binary, case, session))
        results = []
        while pending:
            results.append(pending.popleft().result())
            case = next(remaining, None)
            if case is not None:
                pending.append(pool.submit(run_case, binary, case, session))
    if [r["id"] for r in results] != [c["id"] for c in cases]:
        raise ValueError("Oracle result identity/count mismatch")
    (session / "results.jsonl").write_text("".join(json.dumps(r, sort_keys=True) + "\n" for r in results))
    return results


def self_check(session: Path) -> None:
    case = {"id": "0", "operation": "forward", "input": ["1970", "1", "1"],
            "expected": ["ok", "0"], "evidence": "harness-control"}
    compare(case, "0\tok\t0\n")
    for wrong in ("0\tok\t1\n", "", "0\tok\t0\n0\tok\t0\n", "1\tok\t0\n", "not an observation\n"):
        try:
            compare(case, wrong)
        except ValueError:
            pass
        else:
            raise ValueError("Oracle comparator accepted negative control")
    path = session / "invalid-corpus-control.jsonl"
    for data in ("", json.dumps(case) + "\n" + json.dumps(case) + "\n", '{"id":"0","id":"1"}\n', 'null\n'):
        path.write_text(data)
        try:
            load_cases(path, 1)
        except ValueError:
            pass
        else:
            raise ValueError("Oracle loader accepted negative control")
    path.unlink()
    for invalid in ("", "ROC_METRICS protocol=2 allocations=0 requested_bytes=0 deallocations=0 work=1\n"):
        try:
            parse_metrics(invalid)
        except ValueError:
            pass
        else:
            raise ValueError("Oracle metrics parser accepted negative control")


def fixture_controls(binary: Path, case: dict, session: Path) -> None:
    """Prove native output actually reaches comparison; never bless expectations."""
    control_dir = session / "controls"
    (control_dir / "wrong").mkdir(parents=True)
    (control_dir / "malformed").mkdir()
    wrong = {**case, "expected": ["deliberately-wrong"]}
    try:
        run_case(binary, wrong, control_dir / "wrong")
    except ValueError as error:
        if "mismatch" not in str(error):
            raise
    else:
        raise ValueError("Native oracle pipeline accepted wrong expectation")
    invalid = {**case, "operation": "invalid_operation"}
    try:
        run_case(binary, invalid, control_dir / "malformed")
    except ValueError as error:
        if "fixture exited" not in str(error):
            raise
    else:
        raise ValueError("Native oracle fixture accepted malformed input")
