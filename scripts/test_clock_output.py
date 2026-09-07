"""Failure controls for live clock observation and record validation."""
import json
import unittest
from datetime import datetime, timezone

from test_bundle_examples import check_clock_output


class ClockOutputTests(unittest.TestCase):
    def setUp(self):
        self.record = {
            "checked_at": "2026-09-07T00:00:00.000000Z",
            "expires_at": "2030-01-01T00:00:00.000000Z",
            "expired": False,
        }
        delta = datetime(2026, 9, 7, tzinfo=timezone.utc) - datetime(1970, 1, 1, tzinfo=timezone.utc)
        now = delta.days * 86400 * 1_000_000_000
        self.window = (now, now + 100_000_000)

    def test_valid_live_record(self):
        check_clock_output(json.dumps(self.record), self.window)

    def test_rejects_wrong_status_stale_clock_and_bad_fields(self):
        for changes in (
            {"expired": True}, {"expired": 0},
            {"checked_at": "1970-01-01T00:00:00.000000Z"},
            {"checked_at": "2026-09-06T00:00:00.000000Z"},
            {"checked_at": "2026-09-07T00:00:00Z"},
            {"checked_at": "2026-02-30T00:00:00.000000Z"},
            {"expires_at": "2031-01-01T00:00:00.000000Z"},
            {"unexpected": "field"},
        ):
            with self.subTest(changes=changes), self.assertRaises(SystemExit):
                check_clock_output(json.dumps({**self.record, **changes}), self.window)
        for text in ("{broken", "{}", "[]", "null", json.dumps(self.record) + "extra"):
            with self.subTest(text=text), self.assertRaises(SystemExit):
                check_clock_output(text, self.window)


if __name__ == "__main__":
    unittest.main()
