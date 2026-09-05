#!/usr/bin/env python3
"""Measure pinned timezone archive/data bytes; not compiler or runtime memory."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import sys

sys.dont_write_bytecode = True

from generate_zone_oracle import WHEEL_SHA256


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
    parser.add_argument("wheel", type=Path)
    print(json.dumps(measure(parser.parse_args().wheel), indent=2))
