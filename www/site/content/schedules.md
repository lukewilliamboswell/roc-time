# Generate and exchange schedules

A recurring reservation is a series with an anchor, a rule and exceptions. Querying a later window must preserve that series state; it must not start counting from one again.

## Start with a bounded reservation query

The [released equipment reservations application](https://github.com/lukewilliamboswell/roc-time/tree/0.1.0-rc3/examples/reservations) demonstrates identified recurring appointments. Use `DateRecurrence` for dates and the timed recurrence/schedule APIs when starts need clock and zone interpretation.

Separate three decisions:

1. **Definition:** which source labels belong to the series?
2. **Interpretation:** which immutable rules and gap/fold policies resolve them?
3. **Query:** which finite source-label window and work/output budgets will this request consume?

A schedule query selects starts. Its appointment durations can extend past the query end. If you need everything overlapping a reporting window, account for that caller meaning explicitly rather than treating a start query as an overlap query.

## Treat incomplete output honestly

`Complete` means the bounded request finished. `Limited` carries partial output and a cursor for resumption. Keep the returned cursor: recreating one from the next visible date can lose COUNT, exclusion and recurrence selection state.

A small output cap is not the same as a work cap. A rule may examine candidates that produce no matching occurrence. Do not retry a non-progressing limit forever; select a suitable budget or report that the request is incomplete.

## Importing iCalendar values in rc3

The released adapters accept declared profiles of extracted RFC 5545 DATE and DATE-TIME property values. This does **not** parse an entire ICS file, folded content lines or arbitrary property parameters.

In rc3 these modules are named `RfcDateRule`, `RfcTimedRule`, `RfcDateTime`, `RfcDuration` and `RfcPeriod`. Use those names with the released package. Unsupported forms are explicit errors.

COUNT belongs to the anchored rule; excluding one source does not replenish it. Adding a PERIOD can provide an occurrence with its own ending. Source labels matter even when a gap policy changes the resolved boundary.

## Development-only exchange and storage

The development branch renames the adapters with an `ICal` prefix and adds checked definition access and canonical extracted-property export. The [meeting exchange scenario](https://github.com/lukewilliamboswell/roc-time/tree/main/tests/meeting_exchange) demonstrates editing, exporting and reimporting a weekly meeting across a fixed zone transition.

`ScheduleDefinition` separates a reusable definition from its query cursor. These APIs are unreleased. Versioned schedule archive work is also being validated on the development branch; the released `Persistence` profile does not store schedule definitions. The [development archive application](https://github.com/lukewilliamboswell/roc-time/tree/main/tests/schedule_archive) demonstrates the intended application envelope and overlapping-window workflow; it requires the development checkout.

## API reference

[DateRecurrence](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/DateRecurrence/) · [TimedRecurrence](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/TimedRecurrence/) · [TimedSchedule](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/TimedSchedule/) · [RfcTimedRule in rc3](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/RfcTimedRule/)
