# Generate and exchange schedules

A recurring reservation is a series with an anchor, a rule and exceptions. Querying a later window must preserve that series state; it must not start counting from one again.

## Start with a bounded reservation query

The [released equipment reservations application](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/reservations) demonstrates identified recurring appointments. Use `DateRecurrence` for dates and the timed recurrence/schedule APIs when starts need clock and zone interpretation.

Separate three decisions:

1. **Definition:** which source labels belong to the series?
2. **Interpretation:** which immutable rules and gap/fold policies resolve them?
3. **Query:** which finite source-label window and work/output budgets will this request consume?

A schedule query selects starts. Its appointment durations can extend past the query end. If you need everything overlapping a reporting window, account for that caller meaning explicitly rather than treating a start query as an overlap query.

## Treat incomplete output honestly

`Complete` means the bounded request finished. `Limited` carries partial output and a cursor for resumption. Keep the returned cursor: recreating one from the next visible date can lose COUNT, exclusion and recurrence selection state.

A small output cap is not the same as a work cap. A rule may examine candidates that produce no matching occurrence. Do not retry a non-progressing limit forever; select a suitable budget or report that the request is incomplete.

## Importing iCalendar values

The released adapters accept declared profiles of extracted RFC 5545 DATE and DATE-TIME property values. This does **not** parse an entire ICS file, folded content lines or arbitrary property parameters.

Check your package’s API documentation for adapter names and accepted forms. Unsupported forms are explicit errors.

COUNT belongs to the anchored rule; excluding one source does not replenish it. Adding a PERIOD can provide an occurrence with its own ending. Source labels matter even when a gap policy changes the resolved boundary.

## Editing and exchanging definitions

The `ICal` adapters provide checked definition access and canonical extracted-property export. The [meeting exchange scenario](https://github.com/lukewilliamboswell/roc-time/tree/main/tests/meeting_exchange) demonstrates editing, exporting and reimporting a weekly meeting across a fixed zone transition.

`ScheduleDefinition` separates a reusable in-memory definition from its query cursor. Check your selected release for availability. Store supported schedule declarations using their standard property formats; supply interpretation context explicitly when loading them. Export does not promise to preserve every native calendar policy or embed a zone table. A standard adapter must reject unrepresentable meaning rather than silently discard it.

## API reference

`DateRecurrence` · `TimedRecurrence` · `TimedSchedule` · `ICalTimedRule`
