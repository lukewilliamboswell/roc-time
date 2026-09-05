# roc-time

A date and time package for [Roc](https://www.roc-lang.org).

> [!NOTE]
> This package is a work in progress. APIs may change as the capabilities below evolve.

## Documentation

Read [design.md](design.md) for the intended architecture, temporal model, and performance objectives.
It includes proposed Roc usages and explicit acceptance requirements.

See [lukewilliamboswell.github.io/roc-time/](https://lukewilliamboswell.github.io/roc-time/)

## Roadmap

The direction is a practical toolkit for dates, availability and schedules, with
explicit interpretation and bounded queries. Checked items are available today;
unchecked items are planned.

- [x] Exact microsecond boundaries, interval relations and coverage set operations.
- [x] Gregorian/Julian dates and explicit calendar arithmetic.
- [x] Gap/fold handling, local selections and an optional time-zone database.
- [x] Bounded, resumable date and timed schedules, identified appointments and a date-only RFC recurrence adapter.
- [ ] Broader RFC recurrence import, including timed rules and period-valued additions.
- [ ] Richer temporal descriptions: partial dates, uncertainty and bounded reasoning.
- [ ] ISO 8601 / EDTF / IXDTF parsing and serialization in explicitly supported profiles.
- [ ] Semantic explanations, versioned persistence and broader calendar support.

Usability, independent correctness checks and predictable resource use remain
part of every stage. See the [design](design.md) for the enduring contracts.

## Examples

Examples are small applications built around realistic caller tasks. Each has a
`main.roc` entrypoint and a pure type module containing its domain logic.

| Application | Demonstrates |
| --- | --- |
| [Room availability](examples/coverage/main.roc) | Retain booking identities, report conflicts and subtract occupied coverage from opening hours |
| [Archive date](examples/calendar_conversion/main.roc) | Convert an explicitly identified calendar while retaining the source description |
| [Invoice terms](examples/invoice/main.roc) | Calculate a civil due date with explicit month-end clamping |
| [Overnight staffing](examples/staffing/main.roc) | Budget a local overnight shift across a clock change using the optional zone database |
| [Voyage briefing](examples/voyage/main.roc) | Supply a ship's clock schedule and review a rules update while retaining the saved booking |
| [Equipment inspections](examples/inspections/main.roc) | Schedule four inspections on the last Tuesday every three months, with explicit evaluation limits |
| [Service calendar](examples/maintenance/main.roc) | Import date-only recurrence values and review rescheduled visits without restarting the original series count |
| [Dispatch deadlines](examples/dispatch_deadlines/main.roc) | Select the final pickup slot of each month’s final Monday, preserving local time across daylight saving and series count across queries |
| [Equipment loans](examples/equipment_loans/main.roc) | Keep monthly loans on the 31st, clamp return dates across clock changes, and add an extra one-week booking |
| [Recorder handoff](examples/sample_windows/main.roc) | Classify consecutive microsecond sample windows without losing exact boundaries |

Run them with the pinned compiler:

```sh
roc examples/coverage/main.roc
roc examples/sample_windows/main.roc
roc examples/invoice/main.roc
roc examples/calendar_conversion/main.roc
roc examples/staffing/main.roc
roc examples/voyage/main.roc
roc examples/inspections/main.roc
roc examples/maintenance/main.roc
roc examples/dispatch_deadlines/main.roc
roc examples/equipment_loans/main.roc
```

The availability example resolves dated bookings with explicit offsets before
subtracting their coverage. The recorder example uses resolved POSIX coordinates.
The invoice example uses civil dates without assuming a timezone. The service-calendar
example imports date-only recurrence values. Named-zone applications can add the
[optional zone database](tzdb/README.md); the core does not bundle it.

[RfcDateRule](package/RfcDateRule.roc) accepts extracted date-only recurrence
property values under its declared profile. It does not parse complete ICS
documents or timed rules; affected yearly rules require explicit fields where
omitted defaults remain unsupported.

[AllDayOccurrence](package/AllDayOccurrence.roc) resolves an identified calendar
date and civil-day duration against explicit zone rules, with resumable work
limits. Clock changes can alter its coordinate width; a skipped date retains
the occurrence's identity with empty coverage.
[AllDayRecurrence](package/AllDayRecurrence.roc) applies that interpretation to a
date series. Use bounded `collect` for a list, or `next`/`outcomes` for incremental
consumption; limits retain a cursor for resumption. Its query window selects
source dates, rather than clipping resolved coverage to a timeline window.

## Acknowledgements

The design of `roc-time` is inspired by [Kip Cole's Tempo](https://github.com/elixir-tempo/tempo),
especially its model of calendar values as intervals, calendar-aware durations,
and temporal set algebra. Thank you to Kip and Tempo's contributors for that foundation.
See the [Tempo documentation](https://hexdocs.pm/ex_tempo/) and our [design](design.md)
for the ideas being adapted to Roc.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, verification, oracle checks, and release tooling.
