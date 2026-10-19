# roc-time

[Read the manual](https://lukewilliamboswell.github.io/roc-time/) ·
[PDF](https://lukewilliamboswell.github.io/roc-time/roc-time.pdf) ·
[Releases](https://github.com/lukewilliamboswell/roc-time/releases)

**roc-time is a [Roc](https://www.roc-lang.org) library for dates, bookings and
schedules.** Find free time between bookings, calculate an invoice's due date,
or schedule a weekly meeting across clock changes. Dates, spans
and individual events have separate types, so you can keep the meaning your
application needs.

## What it looks like

A shop opens from 09:00 to 17:00 UTC. A booking arrives as 12:00–14:00 at
UTC+02:00, which occupies 10:00–12:00 UTC. Subtract it from opening hours:

```roc
import time.ExactInterval
import time.Coverage

opening = "2026-06-15T09:00:00Z/2026-06-15T17:00:00Z"
booking = "2026-06-15T12:00:00+02:00/2026-06-15T14:00:00+02:00"
busy = Coverage.from_spans([ExactInterval.span(booking)])
free_windows = Coverage.complement_within(busy, ExactInterval.span(opening))
```

The free windows are **09:00–10:00 and 12:00–17:00 UTC**. Each span includes its
start and excludes its end, so another booking can start at 12:00 without
overlapping the first one. `Coverage` keeps every free window.

This excerpt belongs in an application with a dependency named `time`. Roc
infers the interval types and validates these literals at compile time. For
text received at runtime, `ExactInterval.parse` returns an error for invalid
input. The [complete booking application](examples/booking_exchange/main.roc)
handles two bookings and prints the remaining windows.

## Try it

Download `roc-time-examples-<version>.zip` from a
[release](https://github.com/lukewilliamboswell/roc-time/releases), extract it,
and install the Roc nightly named in its release notes. From the extracted
folder:

```sh
roc version
roc examples/booking_exchange/main.roc
```

Keep each example's whole folder: `main.roc` imports its neighboring modules.
Roc downloads the package dependencies on first use; you don't need a Python
runner. A later nightly may also work; the release notes and nightly
compatibility checks record what has been tested.

For your own application, copy the `time` dependency from an archived example's
header. Named-zone applications also need the optional `zones` dependency shown
in the archived staffing example. The archive uses that release's immutable
package URLs; examples in this checkout use the local packages.

## Where to go next

- [First application](https://lukewilliamboswell.github.io/roc-time/getting-started.html#getting-started): run an example and change a booking.
- [Calendars and clock changes](https://lukewilliamboswell.github.io/roc-time/calendar-zones.html#calendar-zones): calculate due dates and overnight shifts.
- [Schedules](https://lukewilliamboswell.github.io/roc-time/schedules.html#schedules): recurring appointments, exceptions and query limits.
- [Example catalog](examples/README.md): complete applications for availability, archive dates, storage and more.
- [Supported profiles](https://lukewilliamboswell.github.io/roc-time/profiles.html#profiles): accepted formats and limits. Exact calculations use checked integer microseconds; wider standards support is described per module.
- [Contributing](CONTRIBUTING.md): setup, tests and the contribution workflow.

## Prior art

Inspired by [Kip Cole's Tempo](https://github.com/elixir-tempo/tempo), especially
calendar values at meaningful resolutions, calendar-aware durations and temporal
set algebra. Credit to Kip and Tempo's contributors for that foundation.
roc-time is an independent implementation, with its own API and types.
