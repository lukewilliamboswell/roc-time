# roc-time

Dates, booking availability and schedules for [Roc](https://www.roc-lang.org),
with explicit calendar and time-zone choices.

**[0.1.0-rc2 is available](https://github.com/lukewilliamboswell/roc-time/releases/tag/0.1.0-rc2).** This is a release candidate, not a stable API. You can build
working booking and calendar applications with it now. APIs may change, and the
compiler is pinned. Broader standards support is still being built.

## Will this help me?

### Tier 1: Use today

| I want to… | What works | Try it |
| --- | --- | --- |
| Find free booking windows | Parse exact timestamps with different offsets, subtract occupied time, save availability and write free windows back to text | [Booking exchange](examples/booking_exchange/main.roc) |
| Calculate dates | Gregorian/Julian conversion and calendar arithmetic with explicit month-end policies | [Invoice terms](examples/invoice/main.roc) |
| Handle clock changes | Resolve repeated/skipped local times and overnight selections using supplied rules or the optional zone database | [Overnight staffing](examples/staffing/main.roc) |
| Generate schedules | Date and timed recurrence, additions/exclusions, identified appointments and bounded queries that can resume | [Equipment reservations](examples/reservations/main.roc) |
| Retain the meaning of an imported date | Preserve year/month/day precision and uncertainty; explain and save supported descriptions and interpretations | [Archive search](examples/archive_search/main.roc) |

Exact calculations use signed 64-bit microseconds and half-open spans `[start, end)`.
Invalid inputs and exhausted work limits are explicit results. The core does not
choose your zone, read the clock or fetch data on your behalf.

### Tier 2: Use within these supported profiles

These features work, but check that your input fits their scope.

| Feature | Supported now | Main boundary |
| --- | --- | --- |
| Timestamp and booking text | Complete RFC offset timestamps, up to six fractional digits; exact start/end windows; canonical serialization | No leap-second or sub-microsecond input; this is not every ISO 8601 form |
| EDTF archive dates | Gregorian year, year-month or date, with whole-value `?`, `~` or `%` | No EDTF interval endpoints, masks or sets yet; no invented uncertainty tolerance |
| IXDTF annotations | Zone/calendar annotations, critical flags and explicit offset/rule consistency checks | Calendar preferences are retained; presentation currently supports Gregorian only |
| RFC recurrence import | Extracted DTSTART, RRULE, RDATE, EXDATE, DURATION and PERIOD values in declared date/timed profiles | No complete ICS files, mixed UTC/local exceptions, or recurrence export/persistence yet |
| Calendar and zone data | Gregorian and Julian; optional IANA 2025b data for 1800–2200 | Additional calendars are planned; zone data is a separate package dependency |
| Explanation and persistence | Bounded plain-text explanations; versioned storage for supported descriptions, exact values, coverage and complete interpretation snapshots | No event/cursor persistence; snapshots have explicit size limits |

See [API documentation](https://lukewilliamboswell.github.io/roc-time/0.1.0-rc2/),
[text profiles](package/EdtfDate.roc), [timestamp profiles](package/OffsetTimestamp.roc),
[recurrence profiles](package/RfcTimedRule.roc), [persistence limits](package/Persistence.roc)
and [zone-data scope](tzdb/README.md) for exact contracts.

### Tier 3: Next, in user-impact order

1. **Fill archive input/output gaps.** Individually/group-qualified components,
   mixed-resolution interval endpoints, unknown/open bounds, then masks and sets.
   Each supported form needs faithful serialization and useful failure messages.
2. **Complete schedule interchange.** Recurrence export and persistence, followed
   by broader import where real calendar workflows need it. Complete ICS ingestion
   is not available today.
3. **Add calendars for concrete needs.** Choose providers from sourced caller
   scenarios, with independently verified conversions and explicit capabilities.
4. **Extend advanced interpretation and presentation.** Broader uncertainty
   reasoning, explanation of remaining evaluation results and styled rendering.

The ordering follows blocked user workflows. Additional internal refinements
should support one of those workflows or fix demonstrated correctness/performance
problems. The engineering tasks are in [the implementation plan](planning/implement-design.md);
[design.md](design.md) defines the enduring semantic contracts.

## Try it

Browse the [example applications](examples/README.md). Each folder contains a
complete application with a `main.roc` entrypoint and companion modules. Its header
declares the exact Roc compiler and published package URLs it needs.

Download the whole application folder, or clone this repository, then run Roc
directly with that compiler:

```sh
git clone https://github.com/lukewilliamboswell/roc-time.git
cd roc-time
roc version
roc examples/booking_exchange/main.roc
```

For this workflow pilot, the examples use
[`nightly-2026-09-05-b195f5b`](https://github.com/roc-lang/nightlies/releases/tag/nightly-2026-09-05-b195f5b)
as a stand-in for a future supported stable compiler. Development uses a separate
package-header pin; it can advance without changing the public examples.
No versioned stable Roc release is implied by this experiment.

The [released starter kit](https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc2/roc-time-starter.zip)
also contains complete applications. Follow the compiler requirements shipped
with that release, then run `roc examples/booking_exchange/main.roc` from the
extracted kit folder. The [release notes](https://github.com/lukewilliamboswell/roc-time/releases/tag/0.1.0-rc2)
include both package URLs and an import example. No Python runner is required.

That example reads bookings, computes available windows, saves/restores the result
and prints canonical timestamps. For historical-date input, run
`roc examples/archive_search/main.roc`. The [example catalog](examples/README.md)
contains the complete applications; [CONTRIBUTING.md](CONTRIBUTING.md) covers toolchain
setup and verification. Other targets, including Wasm, need separate validation;
see the [native verification scope](CONTRIBUTING.md#instrumented-fixture-platform).

To use the checkout from your own application, add a `time` dependency pointing
to `package/main.roc`. For example, with your app beside a `roc-time` checkout:

```roc
app [main!] {
    time: "./roc-time/package/main.roc",
}
```

Import modules as `time.Coverage`, `time.EdtfDate`, and so on. Interchange value
types such as `EdtfDate` and `OffsetTimestamp` provide checked `parse` and canonical
`to_text` operations, validated quoted
literals and generic string codecs. Use `parse` for runtime interpolated text so
validation errors can be handled. Named-zone applications also need explicit
rules, such as those supplied by the [optional zone package](tzdb/README.md).

## Acknowledgements

Inspired by [Kip Cole's Tempo](https://github.com/elixir-tempo/tempo), especially
calendar values at meaningful resolutions, calendar-aware durations and temporal
set algebra. Credit to Kip and Tempo's contributors for that foundation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, verification, oracle checks and
release tooling, and [AGENTS.md](AGENTS.md) for contributor methodology.
