# Find the right API

Choose a module by the job you need to do. Module names below describe the current source. Open the API documentation linked from your [package release](https://github.com/lukewilliamboswell/roc-time/releases) for matching signatures and supported operations.

## Exact time and availability

| Task | Modules |
| --- | --- |
| Parse explicit-offset timestamps | `OffsetTimestamp` |
| Carry a timeline position or displacement | `PosixBoundary`, `PosixDelta` |
| Work with nonempty spans and interval text | `PosixSpan`, `ExactInterval` |
| Combine occupied time and find gaps | `Coverage` |
| Keep event identities | `EventCollection` |

## Calendar meaning and interpretation

| Task | Modules |
| --- | --- |
| Construct and convert civil dates | `GregorianDate`, `JulianDate`, `CalendarDate` |
| Preserve supplied precision | `CalendarValue`, `QualifiedCalendarValue` |
| Advance with an explicit calendar policy | `CalendarArithmetic`, `CalendarDelta` |
| Express clock labels and resolve them | `ClockTime`, `LocalDateTime`, `FixedOffset`, `ZoneRules` |

## Recurrence, import and storage

| Task | Modules |
| --- | --- |
| Generate calendar dates | `DateRecurrence`, `CalendarPattern` |
| Generate identified timed appointments | `TimedRecurrence`, `TimedSchedule` |
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
