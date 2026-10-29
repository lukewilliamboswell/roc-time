"""Legacy metrics reader for test_zone_database.py.

Oracle replay and admission use Roc. Remove this unchanged protocol helper
when the remaining zone database verification driver is ported.
"""
import re

TRACE = re.compile(r"ROC_TRACE protocol=1 mark=([0-9]+) allocations=([0-9]+)\n\Z")
METRICS = re.compile(r"ROC_METRICS protocol=1 allocations=([0-9]+) requested_bytes=([0-9]+) deallocations=([0-9]+) work=([0-9,]*)\n\Z")


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
