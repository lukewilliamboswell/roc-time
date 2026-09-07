# Work with dates and clock changes

A calendar date, a local date/time and a resolved timeline boundary answer different questions. Choose the operation that matches the caller’s meaning before choosing a timezone.

## Invoice terms: calendar arithmetic

“Due next month” is a calendar operation. Adding a fixed number of seconds does not express it. The [released invoice application](https://github.com/lukewilliamboswell/roc-time/tree/0.1.0-rc3/examples/invoice) demonstrates calendar arithmetic with an explicit policy for dates missing from the destination month.

For 31 January plus one month, a caller must decide whether to reject the destination, clamp to the month’s last day or carry according to the operation’s documented policy. That choice belongs in your business rule. Clamped arithmetic is not reversible in general and is not a recurrence engine.

Gregorian and Julian dates use proleptic rules and astronomical years, including year zero. A calendar conversion preserves the civil day while changing its description; it does not assign midnight in a zone.

## Overnight staffing: interpret a local selection

The [released staffing application](https://github.com/lukewilliamboswell/roc-time/tree/0.1.0-rc3/examples/staffing) interprets an overnight Melbourne shift across a clock change.

```sh
roc examples/staffing/main.roc
```

The application loads named data from the optional package and constructs immutable `ZoneRules`. No host timezone lookup occurs inside the library. The release’s zone pack uses IANA 2025b data over the declared 1800–2200 horizon.

A selected set of civil labels may map to disconnected coverage, or to no coverage for skipped labels. Taking just its earliest and latest resolved points would lose that meaning.

## Appointments need a choice

A repeated clock label can identify more than one boundary. A skipped label can identify none. A resolver must report these outcomes; your application chooses the policy appropriate to an appointment.

Finite rules also have a validity boundary. A visible candidate is not enough if missing context prevents proving that all candidates were considered. An out-of-validity error is not an instruction to assume UTC.

## Development-only convenience APIs

The development branch adds civil text parsing, explicit English Gregorian presentation and Gregorian weekday, ordinal-day and ISO week-date queries. These are **not available from rc3**.

The working [invoice report](https://github.com/lukewilliamboswell/roc-time/tree/main/tests/invoice_report) and [named-zone appointment](https://github.com/lukewilliamboswell/roc-time/tree/main/tests/zoned_appointment) scenarios exercise those APIs with local development packages. They require a checkout and its pinned development compiler; do not copy their imports into an rc3 app.

## API reference

[CalendarArithmetic](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/CalendarArithmetic/) · [CalendarDate](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/CalendarDate/) · [LocalDateTime](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/LocalDateTime/) · [ZoneRules](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/ZoneRules/)
