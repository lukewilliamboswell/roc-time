# Find the right API

Choose a module by the job you need to do. Module names below describe the current source. Open the API documentation linked from your [package release](https://github.com/lukewilliamboswell/roc-time/releases) for matching signatures and supported operations.

## Exact time and availability

For booking availability, start with `ExactInterval.parse`, project each booking
with `ExactInterval.span`, and build `Coverage`. Use `Coverage.complement_within`
with an explicit opening span to find free windows. Keep an `EventCollection`
when you also need booking identities: coverage merges occupied time and cannot
recover which booking contributed it.

For a single timestamp, start with `OffsetTimestamp.parse` and `to_text`.
Convert to a `PosixBoundary` when you need timeline computation.

| Task | Modules |
| --- | --- |
| Parse explicit-offset timestamps | `OffsetTimestamp` |
| Carry a timeline position or displacement | `PosixBoundary`, `PosixDelta` |
| Work with nonempty spans and interval text | `PosixSpan`, `ExactInterval` |
| Combine occupied time and find gaps | `Coverage` |
| Keep event identities | `EventCollection` |

## Calendar meaning and interpretation

Import `Calendar` for its related types: `Calendar.Date` is a validated civil
date, `Calendar.Delta` is a calendar displacement, and `Calendar.Value` preserves
supplied resolution. These remain distinct types with their own constructors and
operations. A month description cannot accidentally become a month displacement.
`Calendar.Arithmetic` applies calendar components with an explicit destination policy.

For invoice dates, start with `GregorianDate` and use `Calendar.Arithmetic` when
advancing a month. Choose the invalid-date policy explicitly: January 31 with
clamping and January 31 with rejection answer different business questions.
Use `Calendar.Value` when supplied precision, such as a whole month, is part of
the meaning rather than an exact date.

A `LocalDateTime` is a label awaiting interpretation. Use `FixedOffset` for a
known offset or `ZoneRules` for a named-zone appointment, with an explicit policy
for gaps and folds. Resolving a whole local-day selection is a separate operation:
its timeline coverage can be empty or disconnected.

| Task | Modules |
| --- | --- |
| Construct and convert civil dates | `GregorianDate`, `JulianDate`, `Calendar.Date` |
| Preserve supplied precision | `Calendar.Value`, `QualifiedCalendarValue` |
| Advance with an explicit calendar policy | `Calendar.Arithmetic`, `Calendar.Delta` |
| Express clock labels and resolve them | `ClockTime`, `LocalDateTime`, `FixedOffset`, `ZoneRules` |

## Recurrence, import and storage

For reusable timed appointments, construct a `ScheduleDefinition` with
`from_ical` or `from_native`, create a cursor for a source-start window, and call
`TimedSchedule.collect` with explicit work and output limits. Keep the returned
batch intact: `Limited` carries incomplete progress and resumption state, not a
complete list of appointments. See [scheduling](schedules.md) for the query model.

Start with `DateRecurrence` for date-only rules. The lower-level patterns and
`TimedRecurrence` are useful when composing selectors or working with starts
without appointment endings; ordinary scheduling need not begin there.

For advanced construction, `TimedSchedule.Endings` validates reusable ending
definitions before queries. The iCalendar adapters' `prepare` operations and
`TimedSchedule.from_prepared` expose this path explicitly. Prepared execution
inputs are not a storage format; use `ScheduleDefinition` when retaining the
original declaration and its interpretation context matters.

| Task | Modules |
| --- | --- |
| Generate calendar dates | `DateRecurrence`, `CalendarPattern` |
| Query reusable timed appointments | `ScheduleDefinition`, `TimedSchedule` |
| Compose timed recurrence starts | `TimedRecurrence` |
| Import extracted iCalendar values | `ICalDateRule`, `ICalTimedRule` |
| Preserve imported descriptions | `EdtfDate`, `Ixdtf` |
| Explain a supported value | `Explanation` |

[Choose a release and its API documentation →](https://github.com/lukewilliamboswell/roc-time/releases)

## Developing against main?

The [module source and documentation on main](https://github.com/lukewilliamboswell/roc-time/tree/main/package) describe the development API. Generate matching local API documentation with the package-pinned compiler:

```sh
roc docs package/main.roc --output=.roc-time-tmp/api-main
```

Use documentation matching the package in your application header. Source documentation may describe APIs not yet included in your chosen release.
