#!/usr/bin/env python3
"""Measure pinned timezone archive/data bytes; not compiler or runtime memory."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import sys

sys.dont_write_bytecode = True

from generate_zone_oracle import WHEEL_SHA256, WHEEL_URL

ROOT = Path(__file__).resolve().parents[1]

def smoke_wheel() -> Path:
    """Acquire the existing integrity-pinned fixture, with a bounded download."""
    from urllib.request import urlopen
    destination = ROOT / ".roc-time-tmp/measurement-smoke/tzdata.whl"
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if hashlib.sha256(destination.read_bytes()).hexdigest() != WHEEL_SHA256:
            raise SystemExit("Cached measurement wheel integrity mismatch")
        return destination
    with urlopen(WHEEL_URL, timeout=30) as response:
        data = response.read(1024 * 1024 + 1)
    if len(data) > 1024 * 1024 or hashlib.sha256(data).hexdigest() != WHEEL_SHA256:
        raise SystemExit("Downloaded measurement wheel integrity mismatch")
    destination.write_bytes(data)
    return destination



def measure(path: Path) -> dict:
    archive_bytes = path.read_bytes()
    digest = hashlib.sha256(archive_bytes).hexdigest()
    if digest != WHEEL_SHA256:
        raise SystemExit("Expected pinned tzdata 2025.2 wheel")
    with zipfile.ZipFile(path) as archive:
        entries = []
        for info in archive.infolist():
            if info.filename.startswith("tzdata/zoneinfo/") and not info.is_dir():
                data = archive.read(info)
                if data.startswith(b"TZif"):
                    entries.append((info, data))
    unique = {data for _, data in entries}
    selected = {name: next(len(data) for info, data in entries if info.filename == "tzdata/zoneinfo/" + name)
                for name in ["Australia/Melbourne", "America/New_York", "Europe/London", "Pacific/Apia"]}
    return {
        "source": "tzdata 2025.2 / IANA 2025b", "wheel_sha256": digest,
        "wheel_bytes": len(archive_bytes), "tzif_entry_count": len(entries),
        "tzif_uncompressed_bytes": sum(len(data) for _, data in entries),
        "tzif_zip_payload_bytes": sum(info.compress_size for info, _ in entries),
        "byte_distinct_payload_count": len(unique),
        "byte_distinct_payload_bytes": sum(map(len, unique)),
        "selected_tzif_bytes": selected,
        "limits": "ZIP entry payload sizes exclude archive metadata. Byte-distinct payload count is not canonical zone count. No Roc source, compiler, linked binary or runtime memory measurements.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wheel", type=Path, nargs="?")
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    if args.wheel is None and not args.smoke:
        parser.error("wheel is required outside smoke mode")
    result = measure(args.wheel or smoke_wheel())
    if args.smoke and not (result["tzif_entry_count"] >= 4 and result["byte_distinct_payload_count"] <= result["tzif_entry_count"] and all(result["selected_tzif_bytes"].values())):
        raise SystemExit("Zone data report invariants failed")
    print(json.dumps(result, indent=2))
