# roc-time

A date and time library for [Roc](https://www.roc-lang.org). Parse timestamps,
find free booking windows, calculate calendar dates and generate schedules,
with explicit calendar and time-zone choices.

**[0.1.0-rc3 is available](https://github.com/lukewilliamboswell/roc-time/releases/tag/0.1.0-rc3).** This is a release candidate, not a stable API. You can build
working booking and calendar applications with it now. APIs may change, and the
compiler is pinned. Broader standards support is still being built.

## Why intervals?

A booking occupies time. To find availability, you need to subtract that occupied
time from an opening window and keep every gap that remains. `roc-time` represents
this with spans and `Coverage`: a collection that merges overlapping or touching
spans and supports union, intersection and difference.

Spans include their start and exclude their end: `[09:00, 10:00)` and
`[10:00, 11:00)` meet without overlapping. Adjacent bookings can share a boundary
without inventing an “end of hour” timestamp.

Calendar meaning matters too. An archive value such as `2026-06` retains month
precision; turning it into midnight on June 1 would lose that meaning. A local
day needs explicit zone rules before it can be placed on a timeline, and a clock
change can alter its coverage. Exact timestamps still represent instants, and
events retain their identity even when they occupy the same time.

## What it looks like

Find the free time around a booking supplied with a different UTC offset:

```roc
import time.ExactInterval
import time.Coverage

free_windows = || {
    opening = ExactInterval.parse("2026-06-15T09:00:00Z/2026-06-15T17:00:00Z")?
    booking = ExactInterval.parse("2026-06-15T12:00:00+02:00/2026-06-15T14:00:00+02:00")?
    busy = Coverage.from_spans([ExactInterval.span(booking)])
    Ok(Coverage.complement_within(busy, ExactInterval.span(opening)))
}
```

The result covers **09:00–10:00 and 12:00–17:00 UTC** on June 15. Parsing returns
structured errors for invalid or unsupported input. The complete
[booking exchange application](examples/booking_exchange/main.roc) also handles
multiple bookings, saves/restores availability and writes canonical timestamp
text. [Try it below](#try-it) with the published package.

## Will this help me?

### Tier 1: Use today

| I want to… | What works | Try it |
| --- | --- | --- |
| Find free booking windows | Parse exact timestamps with different offsets, subtract occupied time, save availability and write free windows back to text | [Booking exchange](examples/booking_exchange/main.roc) |
| Calculate dates | Gregorian/Julian conversion and calendar arithmetic with explicit month-end policies | [Invoice terms](examples/invoice/main.roc) |
| Handle clock changes | Resolve repeated/skipped local times and overnight selections using supplied rules or the optional zone database | [Overnight staffing](examples/staffing/main.roc) |
| Generate schedules | Date and timed recurrence, additions/exclusions, identified appointments and bounded queries that can resume | [Equipment reservations](examples/reservations/main.roc) |
| Retain the meaning of an imported date | Preserve year/month/day precision and uncertainty; explain and save supported descriptions and interpretations | [Archive search](examples/archive_search/main.roc) |

Exact calculations use signed 64-bit microseconds and half-open spans `[start, end)`.
Invalid inputs and exhausted work limits are explicit results. The core does not
choose your zone, read the clock or fetch data on your behalf.

### Tier 2: Use within these supported profiles

These features work, but check that your input fits their scope.

| Feature | Supported now | Main boundary |
| --- | --- | --- |
| Timestamp and booking text | Complete RFC offset timestamps, up to six fractional digits; exact start/end windows; canonical serialization | No leap-second or sub-microsecond input; this is not every ISO 8601 form |
| Native civil text (development source) | Gregorian date, clock and explicitly Gregorian local-datetime parsing and canonical output; date/clock literals and generic string codecs | Not in rc3; local labels have no zone or supplied-field resolution; at most six fractional digits |
| Everyday display (development source) | English Gregorian dates such as `7 Sep 2026` and local appointments such as `7 Sep 2026, 09:30` | Not in rc3; explicit minute/second/exact precision; hiding nonzero fields returns an error; no locale dataset |
| EDTF archive dates | Gregorian year, year-month or date, with whole-value `?`, `~` or `%`; development source also supports individual and year/month group qualifications | No EDTF interval endpoints, masks or sets yet; no invented uncertainty tolerance |
| IXDTF annotations | Zone/calendar annotations, critical flags and explicit offset/rule consistency checks | Calendar preferences are retained; presentation currently supports Gregorian only |
| RFC recurrence import | Extracted DTSTART, RRULE, RDATE, EXDATE, DURATION and PERIOD values in declared date/timed profiles | No complete ICS files, mixed UTC/local exceptions, or recurrence export/persistence yet |
| Calendar and zone data | Gregorian and Julian; optional IANA 2025b data for 1800–2200 | Additional calendars are planned; zone data is a separate package dependency |
| Explanation and persistence | Bounded plain-text explanations; versioned storage for supported descriptions, exact values, coverage and complete interpretation snapshots | No event/cursor persistence; snapshots have explicit size limits |

See [API documentation](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/),
[text profiles](package/EdtfDate.roc), [timestamp profiles](package/OffsetTimestamp.roc),
[recurrence profiles](package/RfcTimedRule.roc), [persistence limits](package/Persistence.roc)
and [zone-data scope](tzdb/README.md) for exact contracts.

### Tier 3: Next, in user-impact order

1. **Finish everyday date/time workflows.** Named-zone appointments,
   clock/expiry integration and application records.
   Add weekday, ordinal-day and ISO-week queries for reporting.
2. **Complete schedule interchange.** Recurrence export and persistence, followed
   by broader import where real calendar workflows need it. Complete ICS ingestion
   is not available today.
3. **Expand specialist support as callers need it.** Faithful archive interval
   endpoints, masks and sets; additional calendars; broader uncertainty reasoning
   and styled explanations. Each slice needs complete input/output and verified
   interpretation within its declared scope.

The ordering follows blocked user workflows. Additional internal refinements
should support one of those workflows or fix demonstrated correctness/performance
problems. The engineering tasks are in [the implementation plan](planning/implement-design.md);
[design.md](design.md) defines the enduring semantic contracts.

## Try it

Browse the [example applications](examples/README.md). Each folder contains a
complete application with a `main.roc` entrypoint and companion modules. Its header
declares the exact Roc compiler and published package URLs it needs.

Download the whole application folder, or clone this repository, then run Roc
directly with that compiler:

```sh
git clone https://github.com/lukewilliamboswell/roc-time.git
cd roc-time
roc version
roc examples/booking_exchange/main.roc
```

The examples require
[`nightly-2026-09-05-b195f5b`](https://github.com/roc-lang/nightlies/releases/tag/nightly-2026-09-05-b195f5b)
until a versioned stable Roc release is available. Use the compiler declared in
the example's header; the development package can require a newer compiler.

The [released starter kit](https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-starter.zip)
also contains complete applications. Follow the compiler requirements shipped
with that release, then run `roc examples/booking_exchange/main.roc` from the
extracted kit folder. The [release notes](https://github.com/lukewilliamboswell/roc-time/releases/tag/0.1.0-rc3)
include both package URLs and an import example. No Python runner is required.

That example reads bookings, computes available windows, saves/restores the result
and prints canonical timestamps. For historical-date input, run
`roc examples/archive_search/main.roc`. The [example catalog](examples/README.md)
contains the complete applications; [CONTRIBUTING.md](CONTRIBUTING.md) covers toolchain
setup and verification. Other targets, including Wasm, need separate validation;
see the [native verification scope](CONTRIBUTING.md#instrumented-fixture-platform).

For your own application, copy the `time` dependency URL and compiler requirement
from a released example's app header. Import modules as `time.Coverage`,
`time.EdtfDate`, and so on. Interchange value
types such as `EdtfDate` and `OffsetTimestamp` provide checked `parse` and canonical
`to_text` operations, validated quoted
literals and generic string codecs. Use `parse` for runtime interpolated text so
validation errors can be handled. Named-zone applications also need explicit
rules, such as those supplied by the [optional zone package](tzdb/README.md).

For development-source callers, [GregorianDate](package/GregorianDate.roc) and
[ClockTime](package/ClockTime.roc) accept inputs such as `2026-09-07` and `09:30`.
[LocalDateTime.parse_gregorian](package/LocalDateTime.roc) accepts
`2026-09-07T09:30`; `to_gregorian_text` writes `2026-09-07T09:30:00`.
These are local boundary labels. Resolve them with explicit zone rules when you
need a timeline position; use description types when supplied resolution matters.
The module examples and [application-record test](tests/codecs/CodecChecks.roc)
show these APIs using the development package. Published rc3 examples require
their released APIs until a new release includes this slice.

[EnglishGregorian](package/EnglishGregorian.roc) adds ordinary display with
explicit precision: `local_datetime(appointment, Minute)` produces
`7 Sep 2026, 09:30` for that local value. `Exact` retains all microseconds;
`Minute` and `Second` return `PrecisionLoss` if they would hide nonzero fields.
The [appointment-display application](tests/appointment_display/main.roc) uses
the development source and is checked against both local sources and the bundle.

## Prior art

Inspired by [Kip Cole's Tempo](https://github.com/elixir-tempo/tempo), especially
calendar values at meaningful resolutions, calendar-aware durations and temporal
set algebra. Credit to Kip and Tempo's contributors for that foundation.

`roc-time` develops those ideas through distinct Roc types for calendar
descriptions, exact boundaries, coverage and events. It is an independent
implementation with its own supported profiles, not an API-compatible Tempo port.
Tempo's [documentation](https://hexdocs.pm/ex_tempo/) is a useful introduction to
the broader interval-oriented approach.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, verification, oracle checks and
release tooling, and [AGENTS.md](AGENTS.md) for contributor methodology.
