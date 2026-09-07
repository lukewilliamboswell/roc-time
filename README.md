# roc-time

A date and time library for [Roc](https://www.roc-lang.org). Parse timestamps,
find free booking windows, calculate calendar dates and generate schedules,
with explicit calendar and time-zone choices.

**[0.1.0-rc3 is available](https://github.com/lukewilliamboswell/roc-time/releases/tag/0.1.0-rc3).**
You can build working booking and calendar applications with it now. This is a
release candidate: APIs may change, and applications pin their Roc compiler.

## Will this help me?

| I want to… | What works | Try it |
| --- | --- | --- |
| Find free booking windows | Parse offset timestamps, subtract occupied time and save availability | [Booking exchange](examples/booking_exchange/main.roc) |
| Check an expiry | Compare a platform-clock reading with an expiry and write a typed JSON record | [Clock deadline](examples/clock_deadline/main.roc) |
| Calculate dates | Gregorian/Julian conversion and calendar arithmetic with explicit month-end policies | [Invoice terms](examples/invoice/main.roc) |
| Handle clock changes | Resolve repeated/skipped local times and overnight selections using explicit zone rules | [Overnight staffing](examples/staffing/main.roc) |
| Generate schedules | Date and timed recurrence, additions/exclusions and bounded, resumable queries | [Equipment reservations](examples/reservations/main.roc) |
| Retain imported date meaning | Preserve date precision and uncertainty; explain and save supported interpretations | [Archive search](examples/archive_search/main.roc) |

## Why intervals, not just instants?

A booking occupies time. To find availability, subtract that occupied time from
an opening window and keep every gap that remains. `Coverage` merges overlapping
or touching spans and supports union, intersection and difference.

Spans include their start and exclude their end: `[09:00, 10:00)` and
`[10:00, 11:00)` meet without overlapping. Adjacent bookings can share a boundary
without inventing an “end of hour” timestamp.

Calendar meaning matters too. An archive value such as `2026-06` retains month
precision; turning it into midnight on June 1 would lose that meaning. A local
day needs explicit zone rules before it can be placed on a timeline. Exact
timestamps still represent instants, and events retain their separate identities.

## What it looks like

Find the free time around a booking supplied with a different UTC offset:

```roc
import time.ExactInterval
import time.Coverage

opening = "2026-06-15T09:00:00Z/2026-06-15T17:00:00Z"
booking = "2026-06-15T12:00:00+02:00/2026-06-15T14:00:00+02:00"
busy = Coverage.from_spans([ExactInterval.span(booking)])
free_windows = Coverage.complement_within(busy, ExactInterval.span(opening))
```

The result covers **09:00–10:00 and 12:00–17:00 UTC** on June 15. Roc infers the
interval types from usage and evaluates these top-level definitions at compile
time, rejecting invalid literals. For runtime input, `ExactInterval.parse` returns
structured errors. The complete
[booking exchange application](examples/booking_exchange/main.roc) handles
multiple bookings, saves/restores availability and writes canonical timestamps.

## Try it

Download the [released starter kit](https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-starter.zip)
and install the compiler declared in its application headers:
[`nightly-2026-09-05-b195f5b`](https://github.com/roc-lang/nightlies/releases/tag/nightly-2026-09-05-b195f5b).
From the extracted kit folder, run:

```sh
roc version
roc examples/booking_exchange/main.roc
```

No Python runner is required. Each example is a complete application with a
`main.roc` entrypoint and companion modules; keep its whole folder together.
The [example catalog](examples/README.md) contains more applications you can run
from a repository checkout using their pinned compiler and published packages.

For your own application, copy the `time` dependency and `roc` compiler fields
from a released example's header. Named-zone applications also use the
[optional zone-data package](tzdb/README.md). The
[release notes](https://github.com/lukewilliamboswell/roc-time/releases/tag/0.1.0-rc3)
include both package URLs, and the
[released API documentation](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/)
describes their supported operations.

## Supported scope

Exact calculations use signed 64-bit microseconds. Invalid inputs and exhausted
work limits are explicit results. The core does not choose your zone, read the
clock or fetch data on your behalf.

- **Text:** offset timestamps and exact intervals with canonical output; declared
  EDTF date and IXDTF annotation profiles. No leap-second or sub-microsecond input,
  and no claim to every ISO 8601 form.
- **Calendars and zones:** Gregorian and Julian calendars; optional IANA 2025b
  zone data for 1800–2200.
- **Schedules:** declared RFC 5545 DATE and DATE-TIME property import profiles.
  Complete ICS files, timed-rule export and durable schedule definitions are
  still future work.
- **Explanation and storage:** bounded explanations and versioned persistence
  for supported descriptions, exact values, coverage and interpretation snapshots.

The development branch is ahead of rc3, including everyday civil text/display,
reporting queries and date-only schedule export. Use the released documentation
for rc3; development APIs may require a newer compiler.

## What comes next?

First, make the everyday date and appointment improvements available in a
compatible release. Then complete schedule export and durable definitions.
Broader archive formats, calendars and reasoning follow concrete caller needs.

## Prior art

Inspired by [Kip Cole's Tempo](https://github.com/elixir-tempo/tempo), especially
calendar values at meaningful resolutions, calendar-aware durations and temporal
set algebra. Credit to Kip and Tempo's contributors for that foundation.

`roc-time` is an independent implementation with distinct Roc types for calendar
descriptions, boundaries, coverage and events. It is not an API-compatible Tempo
port. Tempo's [documentation](https://hexdocs.pm/ex_tempo/) introduces the broader
interval-oriented approach.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and verification.
