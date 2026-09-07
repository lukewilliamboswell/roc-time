# Everyday civil queries

Objective: let an invoice or appointment application group dates by weekday or
ISO week and obtain an ordinal day without implementing recurrence selectors.
Follow R02, R05, R14–R16 in
[design.md](../design.md). This is a bounded caller project, not a general locale
or calendar expansion.

The first vertical slice is an invoice report: accept validated invoice dates,
label each with its weekday and ordinal day, and group totals by the pair
`(week_year, week)`. Include 2020-12-31 and 2021-01-01 in the same 2020-W53
group, with 2021-01-04 starting 2021-W01. The date is the supplied accounting
date, so this example needs no clock or zone interpretation. Keep duplicate
invoice dates as separate records; calendar grouping does not deduplicate events.
Malformed date text fails through the existing checked parser before grouping.

## Dependencies and scope

Use native text codecs for input and EnglishGregorian for ordinary display in
the reporting example. These interfaces do not change the calendar-query laws.

Use validated date/clock fields and existing civil-day conversion. CalendarPattern
already has private weekday, year-day and generalized week-position calculations;
review these for a shared foundation rather than importing recurrence machinery
into scalar dates. Its week-position implementation constructs adjacent-year
dates, so it cannot simply become a full-range public accessor at provider limits.

## Deliverables and API decisions

1. Add Gregorian weekday, ordinal-day and ISO week-date accessors. Proposed names
   are `weekday`, `ordinal_day` and `iso_week_date`; settle their signatures and
   nominal weekday representation against existing CalendarPattern.Weekday and
   Roc static dispatch before exposing them. Ordinal days are 1..365/366. ISO
   weeks start Monday, and week 1 contains January 4; return the week-numbering
   year separately from the calendar year and document weekday numbering.
   Keep ISO week meaning distinct from recurrence's configurable week start.
2. Make all three queries total for a validated GregorianDate across the whole
   provider range. Use a proposed ISO result containing `week_year : I64`,
   `week : U8` and the same weekday type as the scalar query; ordinal output fits
   U16. An ISO week-numbering year can lie immediately outside the date provider:
   2147483647-12-30 belongs to week 1 of 2147483648. Return that year without
   constructing an out-of-provider date. The lower endpoint -2147483648-01-01
   is Tuesday of week 1 in its own year; do not invent a symmetric underflow case.
   Document ISO weekday numbering as Monday 1 through Sunday 7 wherever numeric
   access is supplied. These accessors take no options and need no new malformed
   option errors. Do not clip or silently switch the week year.
   Reuse or extract verified helpers only where this preserves dependency
   direction and existing recurrence semantics.
3. Implement the invoice report above using these public operations and existing
   parsing/presentation APIs. Pure logic remains in a type module and the app
   entrypoint handles presentation. Keep next-weekday arithmetic, inverse ISO
   constructors, custom week-start options and zoned day/month selection out of
   this slice; they need their own demonstrated caller. If a later report starts
   from resolved timestamps, project through explicitly selected zone rules
   before extracting the date.
4. Promote the staged [appointment-display application](../tests/appointment_display/main.roc)
   into the public example collection when a compatible release includes the
   required APIs. Pin its compiler and immutable package URL; include it in the
   released starter kit and preserve the local/bundle output checks.

## Independent evidence and completion

- Pin ordinary-year expectations generated independently with [Python datetime's
  date queries](https://docs.python.org/3/library/datetime.html#datetime.date.isocalendar):
  `weekday`, `timetuple().tm_yday` and `isocalendar`, recording Python revision,
  generator, supported intersection (years 1..9999) and provenance. Review corpus
  refreshes; do not use production output as expected data. Include a complete
  400-year Gregorian cycle where practical and explicit December/January week
  transitions, century leap exceptions and year 1/9999 edges.
- Supplement the external intersection with a deliberately different bounded
  seven-day walk and Gregorian-cycle model for zero, negative and provider-limit
  years. State the cycle-extension assumptions; Python does not verify these
  years directly. The 400-year cycle has 146097 days, divisible by seven; map
  years into a supported cycle and translate only the resulting week year for
  derived fixtures. Label these separately from direct Python results. Include
  the upper-limit week-year crossing and the lower-limit no-crossing case above,
  plus 0000-01-01 belonging to week 52 of year -1. Prefer a day-walking model for
  the exhaustive cycle so it differs from the production arithmetic formula.
- Extend narrow public roc-fuzz coverage for ordinal/month agreement, weekday
  successor modulo seven and independently modeled ISO-week grouping. Pair these
  laws with sourced fixtures, invalid date-input checks and exact report outputs;
  inverse/round-trip agreement alone is insufficient.
- Scalar queries must have constant bounded work and should need no heap output;
  formatting cost follows its bounded output. Verify those costs with the hosted
  resource tools before claiming allocations, and include failing controls.
- Preserve existing configurable recurrence week-start behavior with regression
  fixtures if any foundation is extracted. GregorianDate must not import
  CalendarPattern; a shared weekday representation must keep dependency direction
  and existing public recurrence callers intact. Validate equality, hashing and
  bounded semantic inspection for any newly introduced public nominal value.
- Run pinned checks, package tests, affected fuzz/oracle gates, and the example
  against local sources and its distributable bundle, then the integration gate.
  Update user-facing capabilities only for the supported profile. Remove this
  plan once these deliverables and acceptance evidence are complete.
