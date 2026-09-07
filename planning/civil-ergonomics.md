# Everyday civil queries

Objective: let an invoice or appointment application group dates by weekday or
ISO week and obtain an ordinal day without implementing recurrence selectors.
Follow R02, R05, R14–R16 in
[design.md](../design.md). This is a bounded caller project, not a general locale
or calendar expansion.

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
2. Set the range contract explicitly. Weekday and ordinal access should cover the
   whole Gregorian provider range. An ISO week-numbering year can lie immediately
   outside that range: prefer an I64 year field that represents this result
   without constructing an out-of-provider date, or document a checked boundary
   error before implementation. Do not clip or silently switch the week year.
   Reuse or extract verified helpers only where this preserves dependency
   direction and existing recurrence semantics.
3. Add one realistic invoice/report or appointment-display example using these
   public operations. A resolved appointment must be projected through explicitly
   selected zone rules before display; the formatter itself performs no zone
   lookup, clock read or resolution. Pure logic remains in a type module and the
   app entrypoint handles presentation.
4. Promote the staged [appointment-display application](../tests/appointment_display/main.roc)
   into the public example collection when a compatible release includes the
   required APIs. Pin its compiler and immutable package URL; include it in the
   released starter kit and preserve the local/bundle output checks.

## Independent evidence and completion

- Pin ordinary-year expectations generated independently with Python datetime's
  `weekday`, `timetuple().tm_yday` and `isocalendar`, recording Python revision,
  generator, supported intersection (years 1..9999) and provenance. Review corpus
  refreshes; do not use production output as expected data. Include a complete
  400-year Gregorian cycle where practical and explicit December/January week
  transitions, century leap exceptions and year 1/9999 edges.
- Supplement the external intersection with a deliberately different bounded
  seven-day walk and Gregorian-cycle model for zero, negative and provider-limit
  years. State the cycle-extension assumptions; Python does not verify these
  years. Include the smallest adjacent-week-year counterexamples at both limits.
- Extend narrow public roc-fuzz coverage for ordinal/month agreement, weekday
  successor modulo seven and independently modeled ISO-week grouping. Pair these
  laws with sourced fixtures, malformed option errors and exact display outputs;
  inverse/round-trip agreement alone is insufficient.
- Scalar queries must have constant bounded work and should need no heap output;
  formatting cost follows its bounded output. Verify those costs with the hosted
  resource tools before claiming allocations, and include failing controls.
- Run pinned checks, package tests, affected fuzz/oracle gates, and the example
  against local sources and its distributable bundle, then the integration gate.
  Update user-facing capabilities only for the supported profile. Remove this
  plan once these deliverables and acceptance evidence are complete.
