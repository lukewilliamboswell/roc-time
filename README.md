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
- [x] Bounded, resumable date and timed schedules, identified appointments and RFC date/timed value adapters.
- [ ] Broader RFC recurrence import and persistence.
- [x] Finite calendar descriptions, scoped qualifications and explicit finite-alternative point reasoning.
- [ ] Broader symbolic descriptions, uncertain endpoints and interval reasoning.
- [x] EDTF date-only and RFC offset-timestamp parsing with canonical serialization.
- [x] Exact booking interval text and bounded IXDTF annotations with explicit zone interpretation.
- [ ] Broader ISO 8601 / EDTF profiles and calendar presentation.
- [ ] Semantic explanations, versioned persistence and broader calendar support.

Usability, independent correctness checks and predictable resource use remain
part of every stage. See the [design](design.md) for the enduring contracts.

[EdtfDate](package/EdtfDate.roc) parses and canonically serializes Gregorian
year/month/day descriptions with whole-value `?`, `~` and `%` qualifications.
This date-only profile preserves supplied resolution and does not claim EDTF
Level 0 conformance. Qualified values require explicit evidence for reasoning.
[OffsetTimestamp](package/OffsetTimestamp.roc) handles complete RFC timestamps
with up to six fractional digits, retaining their supplied width and RFC 9557
offset assertions. It also formats computed POSIX boundaries with an explicit
offset and precision. [ExactInterval](package/ExactInterval.roc) composes two
complete timestamps into an exact half-open booking window. This native text
profile is distinct from EDTF's uncertain date endpoints.
[Ixdtf](package/Ixdtf.roc) preserves ordered annotations and critical flags, checks
offset assertions against explicit rules, and retains calendar preferences.
Only Gregorian presentation is currently supported. Module documentation states
exact input limits and error profiles.

The text-format types provide custom `parser_for` / `encoder_for` methods, so
generic encodings such as JSON store canonical strings and use the same checked
parsers. `from_quote` supports validated typed literals, for example an
`EdtfDate` assigned `"1984?"`. Temporal validation errors remain structured and
distinct from encoding errors. For runtime interpolated text, call `parse`
explicitly so invalid input can return an error. These codecs do not define the
versioned native persistence format.

[Persistence](package/Persistence.roc) stores these seven declaration types and
POSIX boundaries/deltas in a versioned JSON envelope with explicit semantic
profiles, axis and units. Decimal strings preserve full-range signed microseconds.
Unknown versions, incompatible metadata and duplicate fields return errors.
This profile preserves declarations and scalar values; calendar values, coverage
and interpretation snapshots require future persistence profiles.

## Examples

Examples are small applications built around realistic caller tasks. Each has a
`main.roc` entrypoint and a pure type module containing its domain logic.

| Application | Demonstrates |
| --- | --- |
| [Room availability](examples/coverage/main.roc) | Retain booking identities, report conflicts and subtract occupied coverage from opening hours |
| [Booking exchange](examples/booking_exchange/main.roc) | Read exact booking windows with different offsets and serialize free windows in UTC |
| [Annotation review](examples/annotation_review/main.roc) | Preserve IXDTF zone/calendar annotations and distinguish an offset conflict from unsupported presentation |
| [Archive persistence](examples/archive_persistence/main.roc) | Save and restore an uncertain catalogue date, a recording declaration and its exact POSIX boundary |
| [Archive date](examples/calendar_conversion/main.roc) | Convert an explicitly identified calendar while retaining the source description |
| [Invoice terms](examples/invoice/main.roc) | Calculate a civil due date with explicit month-end clamping |
| [Overnight staffing](examples/staffing/main.roc) | Budget a local overnight shift across a clock change using the optional zone database |
| [Voyage briefing](examples/voyage/main.roc) | Supply a ship's clock schedule and review a rules update while retaining the saved booking |
| [Equipment inspections](examples/inspections/main.roc) | Schedule four inspections on the last Tuesday every three months, with explicit evaluation limits |
| [Equipment reservations](examples/reservations/main.roc) | Import a timed RRULE and PERIOD additions with explicit return times or positive durations |
| [Service calendar](examples/maintenance/main.roc) | Import date-only recurrence values and review rescheduled visits without restarting the original series count |
| [Dispatch deadlines](examples/dispatch_deadlines/main.roc) | Select the final pickup slot of each month’s final Monday, preserving local time across daylight saving and series count across queries |
| [Equipment loans](examples/equipment_loans/main.roc) | Keep monthly loans on the 31st, clamp return dates across clock changes, and add an extra one-week booking |
| [Outage evidence](examples/outage_evidence/main.roc) | Compare paired outage reports with independent endpoint notes without inventing correlations |
| [Archive search](examples/archive_search/main.roc) | Import EDTF dates and offset timestamps; preserve search precision and unresolved qualifications |
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

[CalendarValue](package/CalendarValue.roc) preserves year, month, day, hour,
minute, second and 1–6-digit fractional resolution for Gregorian/Julian values.
Explicit lowering computes civil bounds and uses the shared bounded zone
selection cursor, preserving empty gaps and disconnected folds. This native
finite profile does not yet model symbolic long years.
[QualifiedCalendarValue](package/QualifiedCalendarValue.roc) attaches whole-value
or supplied-component uncertainty/approximation without inventing a tolerance.
Qualified selections return `NeedsModel` until the caller supplies a model.
[CalendarEvidence](package/CalendarEvidence.roc) validates explicit finite
alternatives and answers bounded POSIX point-membership queries as definite,
possible or impossible. It preserves unqualified fields and does not merge
alternatives into certain coverage.
[IntervalEvidence](package/IntervalEvidence.roc) distinguishes paired resolved
interval choices from independent finite endpoint sets. Its point queries and
explicit possible/definite coverage projections avoid Cartesian-product storage.
Civil endpoint knowledge, unbounded models and general interval reasoning
remain unfinished.

[RfcDateRule](package/RfcDateRule.roc) accepts extracted date-only recurrence
property values under its declared profile. It does not parse complete ICS
documents or timed rules; affected yearly rules require explicit fields where
omitted defaults remain unsupported.

[RfcTimedRule](package/RfcTimedRule.roc) accepts extracted DTSTART, RRULE,
RDATE, EXDATE, positive DURATION and PERIOD values. UTC, floating and zoned
modes validate DTSTART/UNTIL forms before building native bounded schedules.
Local modes require explicit zone rules when scheduling. Complete ICS input,
TZID lookup and mixed UTC/local exception forms remain unsupported.

[TimedRecurrence](package/TimedRecurrence.roc) supports inclusive POSIX-boundary
cutoffs in addition to source-label UNTIL values. Cutoffs filter complete
BYSETPOS selections and preserve explicit additions beyond the rule’s end.

[TimedSchedule](package/TimedSchedule.roc) supports source-specific explicit
endpoints as well as duration overrides. Local endpoints share the schedule’s
zone-work budget; resolved endpoints require no further zone interpretation.

[RfcPeriod](package/RfcPeriod.roc) parses individual PERIOD values and adds them
to native schedules with explicit UTC or local context. Start/end and positive
duration forms share the ordinary occurrence engine and work budgets.

[RfcDateTime](package/RfcDateTime.roc) validates extracted local and UTC
DATE-TIME values, retaining the UTC marker. Local values require explicit
interpretation context; leap seconds remain unsupported on the POSIX profile.

[RfcDuration](package/RfcDuration.roc) parses positive event/period duration
values and lowers them into the shared timed appointment engine. Calendar days
remain distinct from coordinate hours across clock changes. Negative alarm
durations are outside this adapter’s profile; use `RfcPeriod` for PERIOD values.

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
