# Find the right API

Choose a module by the job you need to do. Links below open the generated **0.1.0-rc3 reference**, so signatures match the package used in these guides.

## Exact time and availability

| Task | Modules |
| --- | --- |
| Parse explicit-offset timestamps | [OffsetTimestamp](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/OffsetTimestamp/) |
| Carry a timeline position or displacement | [PosixBoundary](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/PosixBoundary/), [PosixDelta](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/PosixDelta/) |
| Work with nonempty spans and interval text | [PosixSpan](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/PosixSpan/), [ExactInterval](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/ExactInterval/) |
| Combine occupied time and find gaps | [Coverage](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/Coverage/) |
| Keep event identities | [EventCollection](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/EventCollection/) |

## Calendar meaning and interpretation

| Task | Modules |
| --- | --- |
| Construct and convert civil dates | [GregorianDate](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/GregorianDate/), [JulianDate](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/JulianDate/), [CalendarDate](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/CalendarDate/) |
| Preserve supplied precision | [CalendarValue](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/CalendarValue/), [QualifiedCalendarValue](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/QualifiedCalendarValue/) |
| Advance with an explicit calendar policy | [CalendarArithmetic](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/CalendarArithmetic/), [CalendarDelta](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/CalendarDelta/) |
| Express clock labels and resolve them | [ClockTime](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/ClockTime/), [LocalDateTime](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/LocalDateTime/), [FixedOffset](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/FixedOffset/), [ZoneRules](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/ZoneRules/) |

## Recurrence, import and storage

| Task | Modules |
| --- | --- |
| Generate calendar dates | [DateRecurrence](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/DateRecurrence/), [CalendarPattern](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/CalendarPattern/) |
| Generate identified timed appointments | [TimedRecurrence](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/TimedRecurrence/), [TimedSchedule](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/TimedSchedule/) |
| Import extracted iCalendar values | [RfcDateRule](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/RfcDateRule/), [RfcTimedRule](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/RfcTimedRule/) |
| Preserve imported descriptions | [EdtfDate](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/EdtfDate/), [Ixdtf](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/Ixdtf/) |
| Explain a supported value | [Explanation](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/Explanation/) |

[Browse every released module →](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc3/)

## Developing against main?

The [module source and documentation on main](https://github.com/lukewilliamboswell/roc-time/tree/main/package) describe the development API. Generate matching local API documentation with the package-pinned compiler:

```sh
roc docs package/main.roc --output=.roc-time-tmp/api-main
```

Do not use rc3’s generated reference as documentation for a changed development API. In particular, the `ICal` names in main do not exist in rc3; its adapters still have the `Rfc` prefix.
