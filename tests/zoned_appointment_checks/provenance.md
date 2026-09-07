# Named-zone appointment evidence

`AppointmentChecks.roc` uses CPython 3.14.3 `ZoneInfo.from_file` with the
unmodified TZif files from the pinned tzdata 2025.2 wheel (IANA 2025b).
This shares source rule data with the package, but independently computes
fold/UTC round trips and projection instead of Roc's segment-preimage resolver.
No host zone database, current clock or roc-time output supplies expectations.

- [Wheel source](https://files.pythonhosted.org/packages/5c/23/c7abc0ca0a1526a0774eca151daeb8de62ec457e77262b66b359c3c7679e/tzdata-2025.2-py2.py3-none-any.whl)
- Wheel SHA-256: `1a403fada01ff9221ca8044d701868fa132215d84beb92242d9acd2147f667a8`
- `tzdata/zoneinfo/Europe/Paris` SHA-256: `cd588e779c5737d70e4e47158dafab7945b026b2bb34454cc47741815459b068`
- `tzdata/zoneinfo/America/New_York` SHA-256: `d7f2206b3a45989fc9ad63d558922532fa7352280d5f87176bf1db79cb1d1fa9`
- Reference generator `reference.py` SHA-256: `5406e3832e9f9533517f4cd29137b14bcf3a2307a090ebd4ec826c7268daf05a`
- Applicable upstream notices: [tzdata license](../oracles/tzdata-LICENSE.txt)
  and [Apache notice](../oracles/tzdata-licenses-LICENSE_APACHE.txt).

Run `python3.14 tests/zoned_appointment_checks/reference.py /path/to/tzdata-2025.2.whl`
to print independent candidate/projection records for review. Normal replay runs
the typed Roc fixtures directly and does not regenerate or bless expectations.

| Paris local label | UTC candidate(s) | New York local label(s), offset −04:00 |
|---|---|---|
| 2026-03-28 09:30 | 2026-03-28 08:30Z | 2026-03-28 04:30 |
| 2026-03-29 09:30 | 2026-03-29 07:30Z | 2026-03-29 03:30 |
| 2026-10-24 09:30 | 2026-10-24 07:30Z | 2026-10-24 03:30 |
| 2026-10-25 09:30 | 2026-10-25 08:30Z | 2026-10-25 04:30 |
| 2026-10-25 02:30 | 2026-10-25 00:30Z; 01:30Z | 2026-10-24 20:30; 21:30 |
| 2026-03-29 02:30 | none: both UTC round trips change the local label | none |

The spring/fall calendar-day differences are respectively 82,800 and 90,000
POSIX coordinate seconds. Expected unknown-name and exclusive validity-horizon
errors are package contract checks, not claims made by Python's unbounded rules.
Coverage is limited to these modern dates and two-candidate folds; this evidence
does not establish arbitrary transition multiplicity, provider construction cost,
physical SI elapsed duration or other zones/calendars.
