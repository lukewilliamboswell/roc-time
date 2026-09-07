"""Independent fixed UTC-coordinate checks; no timezone database or package code."""
from datetime import datetime, timezone

EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
CASES = {
    '2007-03-09T00:00:00': 1173398400000000,
    '2007-03-13T00:00:00': 1173744000000000,
    '2007-03-11T07:00:00': 1173596400000000,
    '2007-03-10T07:30:00': 1173511800000000,
    '2007-03-11T07:30:00': 1173598200000000,
    '2007-03-12T06:30:00': 1173681000000000,
    '2007-11-02T00:00:00': 1193961600000000,
    '2007-11-06T00:00:00': 1194307200000000,
    '2007-11-04T06:00:00': 1194156000000000,
    '2007-11-03T05:30:00': 1194067800000000,
    '2007-11-04T05:30:00': 1194154200000000,
    '2007-11-05T06:30:00': 1194244200000000,
}
for text, expected in CASES.items():
    elapsed = datetime.fromisoformat(text).replace(tzinfo=timezone.utc) - EPOCH
    actual = (elapsed.days * 86400 + elapsed.seconds) * 1000000
    if actual != expected:
        raise SystemExit(f'{text}: expected {expected}, independently computed {actual}')
print(f'PASS {len(CASES)} independently checked UTC coordinates')
