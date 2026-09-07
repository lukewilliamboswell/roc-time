# Work with dates and clock changes

A calendar date, a local date/time and a resolved timeline boundary answer different questions. Choose the operation that matches the caller’s meaning before choosing a timezone.

## Invoice terms: calendar arithmetic

“Due next month” is a calendar operation. Adding a fixed number of seconds does not express it. The [released invoice application](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/invoice) demonstrates calendar arithmetic with an explicit policy for dates missing from the destination month.

For 31 January plus one month, a caller must decide whether to reject the destination, clamp to the month’s last day or carry according to the operation’s documented policy. That choice belongs in your business rule. Clamped arithmetic is not reversible in general and is not a recurrence engine.

Gregorian and Julian dates use proleptic rules and astronomical years, including year zero. A calendar conversion preserves the civil day while changing its description; it does not assign midnight in a zone.

## Overnight staffing: interpret a local selection

The [released staffing application](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/staffing) interprets an overnight Melbourne shift across a clock change.

```sh
roc examples/staffing/main.roc
```

The application loads named data from the optional package and constructs immutable `ZoneRules`. No host timezone lookup occurs inside the library. Read the zone package metadata for its source data and validity horizon.

A selected set of civil labels may map to disconnected coverage, or to no coverage for skipped labels. Taking just its earliest and latest resolved points would lose that meaning.

## Appointments need a choice

A repeated clock label can identify more than one boundary. A skipped label can identify none. A resolver must report these outcomes; your application chooses the policy appropriate to an appointment.

Finite rules also have a validity boundary. A visible candidate is not enough if missing context prevents proving that all candidates were considered. An out-of-validity error is not an instruction to assume UTC.

## Parse and present civil labels

Use the civil text parsers for validated date and clock labels, and
`EnglishGregorian` for explicit English Gregorian presentation. Gregorian dates
also expose weekday, ordinal-day and ISO week-date queries. These operations do
not require zone interpretation; display does not prove that a local label exists
in a particular zone.

The [invoice report](https://github.com/lukewilliamboswell/roc-time/tree/main/tests/invoice_report)
and [named-zone appointment](https://github.com/lukewilliamboswell/roc-time/tree/main/tests/zoned_appointment)
scenarios exercise these APIs against local source. Run these test applications
from a checkout with its package-pinned compiler. For an application using a
released package, consult that release's API documentation and compiler pin.

## API reference

`Calendar.Arithmetic` · `Calendar.Date` · `LocalDateTime` · `ZoneRules`
