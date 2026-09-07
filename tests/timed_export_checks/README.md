# Timed definition and export evidence

`scripts/test_timed_export.py` replays `cases.jsonl` through the actual public
`TimedRecurrence.definition/from_definition` and
`ICalTimedRule.definition/new/to_parts/parse` APIs. Each native executable receives
source inputs only. Expected output never enters the Roc operation under test.
The same corpus runs on native dev and speed builds, with an interpreter smoke
case and deliberately wrong, malformed and missing output controls.

Requirements: R01, R07, R11, R12, R14 and R16. Successful cases compare canonical
property text and independently expected source labels and microsecond spans.
Every case evaluates the original with small resumable work/output budgets and
the rebuilt/exported/imported rule with broad budgets. COUNT/window cases use
two overlapping windows and exclusions. Native-only values test checked precision,
year, count and byte limits. Wrong UTC/local UNTIL and interpretation contexts
must return the specific declared errors.

The byte boundary uses 4091 sixteen-byte UTC exclusions, a sixteen-byte start,
a sixty-byte canonical rule and four-byte `PT1S`: exactly 65536 bytes must
export and re-import. Changing the duration to `PT10S` produces 65537 bytes and
must return `TooLarge`. A Julian exclusion describing the Gregorian anchor's
same local position must survive native definition reconstruction with its
calendar intact, then be rejected by the Gregorian text profile. Fractional
`UntilBoundary` similarly must fail export without precision reduction.

## Independent expectations

`reference.py` contains finite, explicitly enumerated recurrence labels and an
independent integer offset model. It uses Python's Gregorian `datetime` only for
converting these labels into epoch seconds, without the host clock or timezone
database. The two synthetic snapshots change offset at POSIX second zero:

| Snapshot | Before | After | Repeated/missing label interpretation |
|---|---:|---:|---|
| gap | 0 | +3600 | explicit labels use the before-gap offset |
| fold | +3600 | 0 | explicit labels use the first occurrence |
| fixed | +7200 | +7200 | unique interpretation |

These are model-derived fixtures, **not** historical IANA transitions. Calendar
day endings re-resolve the next day's label; elapsed endings add coordinate
seconds; explicit PERIOD endings resolve the supplied ending label. The model
does not use the package's recurrence, zone lookup, date conversion or formatter.

Primary semantic sources are [RFC 5545, September 2009](https://www.rfc-editor.org/rfc/rfc5545.html):
§3.3.5 for DATE-TIME form and fold/gap interpretation; §3.3.6 for day versus
elapsed duration; §3.3.9 for PERIOD; §3.3.10 for inclusive UNTIL, COUNT and clock
expansion/limitation; §3.8.5.3 for recurrence sets and exclusions. The source is
Copyright © 2009 IETF Trust and the identified authors, subject to its stated
BCP 78 terms. This corpus and model are newly authored; no source implementation
or prose is copied. Canonical ordering, explicit effective clock fields, numeric
duration spelling and representability errors are roc-time profile expectations,
not RFC-mandated source spelling.

`integrity.json` pins the generator and reviewed JSONL bytes with SHA-256.
Ordinary replay neither regenerates nor downloads expectations. To propose an
expectation change, edit the independently justified model or explicit fixtures,
run `python3 tests/timed_export_checks/reference.py`, review the corpus diff and
then update its integrity hashes. Never obtain expected results from roc-time.

This evidence covers the selected finite intersections, all seven frequency
forms, explicit contexts and several transition/ending interactions. It does
not establish all RRULE combinations, full ICS documents, arbitrary historical
timezone correctness, persistence snapshot identity or allocation complexity.
Those require their own evidence; text mode `Zoned` alone carries no zone name
or snapshot identity.
