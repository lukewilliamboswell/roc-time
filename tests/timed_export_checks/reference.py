#!/usr/bin/env python3
"""Independent small finite examples; never invokes roc-time to bless output.

RFC 5545 (September 2009), §§3.3.5, 3.3.6, 3.3.9, 3.3.10, 3.8.5.3
supplies interpretation, COUNT-before-EXDATE, inclusive UNTIL and PERIOD laws.
The tiny epoch transition fixtures are model-derived, not RFC/IANA data.
Canonical property ordering/default spelling is the declared roc-time profile,
not a claim that RFC 5545 mandates this spelling.
"""
import json
from datetime import datetime, timedelta
from pathlib import Path

EPOCH = datetime(1970, 1, 1)


def seconds(text):
    delta = datetime.strptime(text.rstrip("Z"), "%Y%m%dT%H%M%S") - EPOCH
    return delta.days * 86400 + delta.seconds


def coordinate(local, context):
    if context == "utc":
        return local
    if context == "fixed":
        return local - 7200
    if context == "gap":
        # At UTC 0 offset jumps 0→3600. Labels [0,3600) use the
        # before-gap offset, matching §3.3.5 explicit DATE-TIME semantics.
        return local if local < 3600 else local - 3600
    if context == "fold":
        # At UTC 0 offset jumps 3600→0. Duplicated [0,3600) uses first.
        return local - 3600 if local < 3600 else local
    raise ValueError(context)


def event(text, context, duration=3600, end=None, days=0):
    source = datetime.strptime(text.rstrip("Z"), "%Y%m%dT%H%M%S")
    local = seconds(text)
    start = coordinate(local, context)
    finish = coordinate(seconds(end), context) if end else (
        coordinate(local + days * 86400, context) + duration if days else start + duration)
    return {"source": source.isoformat(), "start": start * 1000000, "end": finish * 1000000}


def case(name, start, rule, canonical, labels, *, mode="Utc", context="utc",
         duration="PT1H", canonical_duration="PT3600S", inclusions=(), exclusions=(),
         periods=(), out_inclusions=(), out_exclusions=(), out_periods=(),
         lower="19691228T000000", upper="19700105T000000", endings=None):
    args = [start, rule, mode, duration, "|".join(inclusions) or "-",
            "|".join(exclusions) or "-", "|".join(periods) or "-", lower, upper, context]
    if canonical and "BYHOUR=" not in canonical:
        # Declared canonical profile emits effective selectors. RFC §3.3.10's
        # expansion/limitation table: high subdaily fields are unrestricted;
        # omitted lower fields inherit DTSTART.
        frequency = canonical.split(";", 1)[0].split("=")[1]
        clock = datetime.strptime(start.rstrip("Z"), "%Y%m%dT%H%M%S")
        hours = range(24) if frequency in ("HOURLY", "MINUTELY", "SECONDLY") else [clock.hour]
        minutes = range(60) if frequency in ("MINUTELY", "SECONDLY") else [clock.minute]
        seconds_list = range(60) if frequency == "SECONDLY" else [clock.second]
        fields = ";".join(f"{name}=" + ",".join(map(str, values)) for name, values in
                          [("BYHOUR", hours), ("BYMINUTE", minutes), ("BYSECOND", seconds_list)])
        canonical = canonical.replace(";WKST=", f";{fields};WKST=")
    occurrences = [event(label, context, **(endings or {}).get(label, {})) for label in labels]
    return {"name": name, "input": args, "expected": {
        "parts": {"start": start.upper(), "rule": canonical, "mode": mode,
                  "duration": canonical_duration, "inclusions": list(out_inclusions),
                  "exclusions": list(out_exclusions), "periods": list(out_periods)},
        "occurrences": occurrences}}


def cases():
    # The explicit labels below are the finite recurrence oracle. No RRULE
    # interpreter duplicates the native algorithm; calendar examples use direct
    # source facts and subdaily examples use elementary integer stepping.
    yield case("count-exclude-window", "19691231T090000Z", "COUNT=3;FREQ=DAILY",
               "FREQ=DAILY;INTERVAL=1;COUNT=3;WKST=MO",
               ["19700102T090000Z", "19700103T120000Z"],
               inclusions=["19700103T120000Z,19700103T120000Z"],
               exclusions=["19700101T090000Z", "19700101T090000Z"],
               out_inclusions=["19700103T120000Z"], out_exclusions=["19700101T090000Z"],
               lower="19700101T000000")
    yield case("floating-until", "19691231T090000", "UNTIL=19700102T090000;FREQ=DAILY",
               "FREQ=DAILY;INTERVAL=1;UNTIL=19700102T090000;WKST=MO",
               ["19691231T090000", "19700101T090000", "19700102T090000"], mode="Floating", context="fixed")
    yield case("count-overlap-window", "19691231T090000Z", "COUNT=3;FREQ=DAILY",
               "FREQ=DAILY;INTERVAL=1;COUNT=3;WKST=MO",
               ["19691231T090000Z", "19700102T090000Z"],
               inclusions=["19700103T120000Z,19700103T120000Z"],
               exclusions=["19700101T090000Z", "19700101T090000Z"],
               out_inclusions=["19700103T120000Z"], out_exclusions=["19700101T090000Z"],
               lower="19691231T000000", upper="19700103T000000")
    yield case("zoned-until", "19691231T090000", "FREQ=DAILY;UNTIL=19700102T080000Z",
               "FREQ=DAILY;INTERVAL=1;UNTIL=19700102T080000Z;WKST=MO",
               ["19691231T090000", "19700101T090000", "19700102T090000"], mode="Zoned", context="gap")
    for frequency, start, interval, labels in [
        ("SECONDLY", "19691231T235958Z", 2, ["19691231T235958Z", "19700101T000000Z", "19700101T000002Z"]),
        ("MINUTELY", "19691231T235900Z", 2, ["19691231T235900Z", "19700101T000100Z", "19700101T000300Z"]),
        ("HOURLY", "19691231T230000Z", 2, ["19691231T230000Z", "19700101T010000Z", "19700101T030000Z"]),
    ]:
        yield case(frequency.lower(), start, f"COUNT=3;INTERVAL={interval};FREQ={frequency}",
                   f"FREQ={frequency};INTERVAL={interval};COUNT=3;WKST=MO", labels)
    yield case("clock-selectors", "19700101T090005Z",
               "BYSECOND=35,5,35;BYHOUR=17,9,9;COUNT=5;BYMINUTE=30,0,30;FREQ=DAILY",
               "FREQ=DAILY;INTERVAL=1;COUNT=5;BYHOUR=9,17;BYMINUTE=0,30;BYSECOND=5,35;WKST=MO",
               ["19700101T090005Z", "19700101T090035Z", "19700101T093005Z", "19700101T093035Z", "19700101T170005Z"])
    yield case("hourly-setpos", "19700101T093035Z",
               "BYSETPOS=-1,-1;BYSECOND=35,5;BYMINUTE=30,0;COUNT=3;FREQ=HOURLY",
               "FREQ=HOURLY;INTERVAL=1;COUNT=3;BYHOUR=" + ",".join(map(str, range(24))) +
               ";BYMINUTE=0,30;BYSECOND=5,35;BYSETPOS=-1;WKST=MO",
               ["19700101T093035Z", "19700101T103035Z", "19700101T113035Z"])
    yield case("utc-until", "19700101T090000Z", "FREQ=DAILY;UNTIL=19700102T090000Z",
               "FREQ=DAILY;INTERVAL=1;UNTIL=19700102T090000Z;WKST=MO",
               ["19700101T090000Z", "19700102T090000Z"])
    yield case("weekly-periods", "19691225T090000", "COUNT=3;FREQ=WEEKLY;BYDAY=TH,TH",
               "FREQ=WEEKLY;INTERVAL=1;COUNT=3;BYDAY=TH;WKST=MO",
               ["19691225T090000", "19700102T090000", "19700108T090000"],
               mode="Zoned", context="gap", lower="19691224T000000", upper="19700110T000000",
               exclusions=["19700101T090000"], out_exclusions=["19700101T090000"],
               periods=["19700102T090000/PT2H", "19700108T090000/19700108T103000"],
               out_periods=["19700102T090000/PT7200S", "19700108T090000/19700108T103000"],
               endings={"19700102T090000": {"duration": 7200}, "19700108T090000": {"end": "19700108T103000"}})
    for context in ("gap", "fold"):
        yield case(f"{context}-explicit-period", "19691231T003000", "FREQ=DAILY;COUNT=1",
                   "FREQ=DAILY;INTERVAL=1;COUNT=1;WKST=MO",
                   ["19691231T003000", "19700101T003000"], mode="Zoned", context=context,
                   periods=["19700101T003000/19700101T023000"],
                   out_periods=["19700101T003000/19700101T023000"],
                   endings={"19700101T003000": {"end": "19700101T023000"}})
        yield case(f"{context}-calendar-day", "19691231T090000", "FREQ=DAILY;COUNT=2",
                   "FREQ=DAILY;INTERVAL=1;COUNT=2;WKST=MO",
                   ["19691231T090000", "19700101T090000"], mode="Zoned", context=context,
                   duration="P1D", canonical_duration="P1D",
                   endings={label: {"days": 1, "duration": 0} for label in ["19691231T090000", "19700101T090000"]})
    yield case("monthly", "19700131T090000Z", "COUNT=3;FREQ=MONTHLY",
               "FREQ=MONTHLY;INTERVAL=1;COUNT=3;WKST=MO",
               ["19700131T090000Z", "19700331T090000Z", "19700531T090000Z"],
               lower="19700101T000000", upper="19700601T000000")
    yield case("yearly", "19680229T090000Z", "COUNT=2;FREQ=YEARLY",
               "FREQ=YEARLY;INTERVAL=1;COUNT=2;WKST=MO", ["19680229T090000Z", "19720229T090000Z"],
               lower="19680101T000000", upper="19730101T000000")
    for suffix, termination in [("forever", ""), ("count-max", ";COUNT=2147483647")]:
        yield case(suffix, "19700101T090000Z", f"FREQ=DAILY{termination}",
                   f"FREQ=DAILY;INTERVAL=1{termination};WKST=MO", ["19700101T090000Z", "19700102T090000Z"],
                   upper="19700103T000000")
    # Wrong/missing mode-specific interpretation is explicit; round trips cannot
    # accidentally add UTC semantics to an unresolved local schedule.
    for mode, context, start in [("Utc", "fixed", "19700101T090000Z"),
                                 ("Floating", "utc", "19700101T090000"),
                                 ("Zoned", "utc", "19700101T090000")]:
        value = case(f"context-{mode}", start, "FREQ=DAILY;COUNT=1", "", [], mode=mode, context=context)
        value.pop("expected")
        value["error"] = "IncompatibleContext"
        yield value
    for name, error in [("fraction", 'PrecisionLoss("DTSTART")'),
                        ("year-zero", 'OutOfRange("DTSTART")'),
                        ("year-high", 'OutOfRange("DTSTART")'),
                        ("count", 'OutOfRange("COUNT")'),
                        ("size", 'TooLarge'),
                        ("over-cap", 'TooLarge'),
                        ("julian-exdate", 'Unsupported("non-Gregorian EXDATE")'),
                        ("until-fraction", 'PrecisionLoss("UNTIL")'),
                        ("rdate-fraction", 'PrecisionLoss("RDATE")'),
                        ("exdate-fraction", 'PrecisionLoss("EXDATE")')]:
        yield {"name": f"native-{name}", "input": [f"native-{name}"], "error": error}
    yield {"name": "native-exact-cap", "input": ["native-exact-cap"],
           "expected": {"bytes": 65536, "exclusions": 4091}}
    for mode, start, until, message in [
        ("Utc", "19700101T090000Z", "19700102T090000", "UTC or zoned DTSTART requires UTC UNTIL"),
        ("Zoned", "19700101T090000", "19700102T090000", "UTC or zoned DTSTART requires UTC UNTIL"),
        ("Floating", "19700101T090000", "19700102T090000Z", "floating DTSTART requires local UNTIL"),
    ]:
        yield {"name": f"until-domain-{mode}",
               "input": [start, f"FREQ=DAILY;UNTIL={until}", mode, "PT1H", "-", "-", "-", "19700101T000000", "19700103T000000", "utc"],
               "error": f'Incompatible("{message}")'}


if __name__ == "__main__":
    output = Path(__file__).with_name("cases.jsonl")
    output.write_text("".join(json.dumps(value, separators=(",", ":")) + "\n" for value in cases()))
