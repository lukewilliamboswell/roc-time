# Gregorian query evidence

R02, R05 and R16 cover the calendar-domain queries. `reference.py` uses
CPython **3.12.3**, source tag
[v3.12.3](https://github.com/python/cpython/blob/v3.12.3/Modules/_datetimemodule.c),
to observe `date.weekday()`, `date.timetuple().tm_yday` and
[`date.isocalendar()`](https://docs.python.org/3.12/library/datetime.html#datetime.date.isocalendar).
The reference runtime is PSF licensed; no implementation code is copied.
The generator and JSONL SHA-256 hashes are pinned in the replay harness.
Regeneration is an explicit reviewed operation:
`python3 tests/civil_query_checks/reference.py > tests/civil_query_checks/cases.jsonl`.

The corpus contains 118 direct observations and 84 cycle-derived fixtures.
Direct observations cover selected dates in years 1..9999: January/December
week boundaries, leap days, century exceptions and the reference's range edges.
Records marked `cycle-extension` are **derived model evidence**, not Python
support for astronomical zero, negative years or I32 provider endpoints.
Their assumption is the proleptic Gregorian 400-year cycle: 146097 days is
divisible by seven. Map the year into 2000..2399, preserve month/day, and
translate only the returned week year by the multiple of 400. The upper-limit
fixtures explicitly allow ISO week year 2147483648.

The separate native oracle walks every day of 2000..2399 in January-based
month tables, advances a weekday counter, and advances ISO weeks only on
Mondays. Week 1 resets on Mondays December 29..January 4. Its initial state
(2000-01-01 = Saturday of 1999-W52, ordinal 1) is also in the Python corpus.
This model does not call production civil-day conversion or use its week
arithmetic formula. Month lengths and the Gregorian leap rule are shared
calendar assumptions. It tests all 146097 dates of one complete cycle;
it does not exhaust the I32 range or establish resource bounds.

`ROC=/path/to/pinned/roc python3 scripts/test_civil_queries.py` performs offline
replay, one interpreter smoke, and native dev/speed builds. Native operations
receive dates, never expected results. Four bounded workers preserve corpus
order for comparison. Wrong/malformed output controls exercise the comparison,
and a runtime wrong-week control must trigger the native assertion in each
optimization mode. Assertions use `crash`, not removable optimized `expect`.
