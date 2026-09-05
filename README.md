# roc-time

A date and time package for [Roc](https://www.roc-lang.org).

> [!NOTE]
> This package is a work in progress. Its initial kernel provides exact POSIX
> boundaries, coordinate displacements, nonempty half-open spans, and canonical
> coverage algebra, plus proleptic Gregorian civil-day conversion. Calendar
> arithmetic, zone interpretation, and the remaining design are still being implemented.

## Documentation

Read [design.md](design.md) for the intended architecture, temporal model, and performance objectives.
It includes proposed Roc usages and explicit acceptance requirements.

See [lukewilliamboswell.github.io/roc-time/](https://lukewilliamboswell.github.io/roc-time/)

## Examples

Examples are small applications built around realistic caller tasks. Each has a
`main.roc` entrypoint and a pure type module containing its domain logic.

| Application | Demonstrates |
| --- | --- |
| [Room availability](examples/coverage/main.roc) | Subtract overlapping bookings from opening hours and report the remaining windows |
| [Recorder handoff](examples/sample_windows/main.roc) | Classify consecutive microsecond sample windows without losing exact boundaries |

Run them with the pinned compiler:

```sh
roc examples/coverage/main.roc
roc examples/sample_windows/main.roc
```

The supplied timestamps are explicitly resolved POSIX coordinates. Calendar
parsing and display will be demonstrated as those capabilities land.

## Acknowledgements

The design of `roc-time` is inspired by [Kip Cole's Tempo](https://github.com/elixir-tempo/tempo),
especially its model of calendar values as intervals, calendar-aware durations,
and temporal set algebra. Thank you to Kip and Tempo's contributors for that foundation.
See the [Tempo documentation](https://hexdocs.pm/ex_tempo/) and our [design](design.md)
for the ideas being adapted to Roc.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, verification, oracle checks, and release tooling.
