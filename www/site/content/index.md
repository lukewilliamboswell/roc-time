# Time for real applications

Bookings occupy a window. An invoice falls due on a calendar date. A weekly meeting keeps its local clock time when the offset changes. **roc-time gives each of these a meaning you can work with.**

[Run a working application →](getting-started.html) · [Find the right API](api.html)

## Start with your task

| You need to… | Start here |
| --- | --- |
| Parse booking timestamps and find free space | [Booking and coverage](booking.html) |
| Calculate an invoice date or handle an overnight shift | [Calendars and zones](calendar-zones.html) |
| Generate recurring reservations without losing exceptions | [Schedules](schedules.html) |
| Decide whether an input format is supported | [Profiles and limits](profiles.html) |

The guides start from **0.1.0-rc3**, a published release candidate. The development branch contains newer APIs; those are called out separately. [Keep the compiler and package version together](versions.html).

## Why intervals, not just instants?

Two bookings can meet at 10:00 without overlapping. A span includes its start and excludes its end: `[09:00, 10:00)` is followed cleanly by `[10:00, 11:00)`.

`Coverage` keeps all the occupied or available pieces. Subtract a lunch booking from an opening window and both morning and afternoon remain. You do not need a fabricated “last microsecond of the morning.”

An event is still an identified event, even when it occupies the same time as another event. A month such as June 2026 still has month precision. The library keeps those distinctions until your application chooses to combine them.

## What it looks like

An opening window is 09:00–17:00 UTC. A booking arrives as 12:00–14:00 at UTC+02:00. After interpretation, that booking occupies 10:00–12:00 UTC; the remaining coverage is **09:00–10:00 and 12:00–17:00 UTC**.

The [complete booking application](https://github.com/lukewilliamboswell/roc-time/tree/0.1.0-rc3/examples/booking_exchange) parses inputs, subtracts bookings, saves availability and prints canonical timestamps. It is a multi-file Roc application you can run directly.

## Explicit choices, useful guarantees

- Exact coordinates use signed 64-bit microseconds and checked arithmetic.
- Local labels need an explicit offset or immutable zone rules.
- Recurrence work has finite budgets; an incomplete result says so and can be resumed.
- Parsing, display, explanation and persistence have separate purposes.

See [supported scope](profiles.html) before depending on a standards profile. This is an actively developing package, not a claim to every date/time format or calendar.

## Prior art

roc-time is inspired by [Kip Cole’s Tempo](https://github.com/elixir-tempo/tempo), especially its treatment of calendar precision, intervals and set algebra. Credit belongs to Kip and Tempo’s contributors for that foundation. roc-time is an independent Roc implementation, not an API-compatible port.
