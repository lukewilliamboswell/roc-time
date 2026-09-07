"""Print independent reviewed-fixture inputs; never rewrite expected Roc values."""
import hashlib
import io
import json
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

if sys.version_info[:3] != (3, 14, 3):
    raise SystemExit("Reference requires CPython 3.14.3")
wheel = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(wheel).hexdigest() != "1a403fada01ff9221ca8044d701868fa132215d84beb92242d9acd2147f667a8":
    raise SystemExit("Unexpected tzdata wheel")
archive = zipfile.ZipFile(io.BytesIO(wheel))
zones = {}
for name, digest in {
    "Europe/Paris": "cd588e779c5737d70e4e47158dafab7945b026b2bb34454cc47741815459b068",
    "America/New_York": "d7f2206b3a45989fc9ad63d558922532fa7352280d5f87176bf1db79cb1d1fa9",
}.items():
    data = archive.read("tzdata/zoneinfo/" + name)
    if hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit("Unexpected TZif data")
    zones[name] = ZoneInfo.from_file(io.BytesIO(data), key=name)
epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
for text in ("2026-03-28T09:30:00", "2026-03-29T09:30:00",
             "2026-10-24T09:30:00", "2026-10-25T09:30:00",
             "2026-10-25T02:30:00", "2026-03-29T02:30:00"):
    local = datetime.fromisoformat(text)
    candidates = {}
    for fold in (0, 1):
        utc = local.replace(tzinfo=zones["Europe/Paris"], fold=fold).astimezone(timezone.utc)
        if utc.astimezone(zones["Europe/Paris"]).replace(tzinfo=None) != local:
            continue
        delta = utc - epoch
        coordinate = (delta.days * 86400 + delta.seconds) * 1_000_000 + delta.microseconds
        candidates[coordinate] = {
            "microseconds": coordinate,
            "utc": utc.isoformat(),
            "new_york": utc.astimezone(zones["America/New_York"]).isoformat(),
        }
    print(json.dumps({"local": text, "candidates": [candidates[k] for k in sorted(candidates)]}))
