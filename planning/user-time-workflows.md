# Everyday appointments and deadlines

Objective: make two ordinary application workflows discoverable and executable
through existing public types. Follow [R01–R02, R05, R07–R09 and R14–R16](../design.md#acceptance-requirements).
This is a caller-evidence project, not a request for a universal zoned datetime
type, a new resolver or a core clock service.

## Named-zone appointment

Add a focused multi-file application that accepts a Gregorian local appointment,
an explicit source zone and an explicit occurrence policy; advances the local
date by one calendar day while retaining its clock label; and displays both
appointments in a second named zone. Make repeated-time alternatives visible
before selection. Gaps, missing names, finite rule validity and ambiguous
occurrences must remain actionable errors or explicit review results.

Reuse `LocalDateTime.parse_gregorian`, `ZoneRules.from_database`,
`ZoneRules.resolve_occurrence` and the existing classification API. Calendar
stepping composes `CalendarDate.as_gregorian`, `CalendarArithmetic.shift_day`
with `CalendarDelta.days(1)` and an explicit policy, then `LocalDateTime.new`
with the original `ClockTime`. Target-zone display composes
`ZoneRules.offset_at`, `FixedOffset.project` and canonical local text output.
Use `ResolvedBoundary` only when retaining the original interpretation is part
of the scenario. Do not reconstruct source meaning from displayed output.

Executable acceptance:

- Use pinned zone-data fixtures to show the same local hour across a spring
  transition while the two POSIX boundaries differ by 23 coordinate hours.
  A fall transition must separately demonstrate 25 coordinate hours.
- Show both boundaries of a repeated local label, and select explicitly.
  A missing occurrence and a rules horizon failure must differ from ambiguity.
- Project a chosen boundary into the second zone and independently check its
  expected date, clock and offset. Displaying it must not change the boundary.
- Pair the realistic example with narrow deterministic public-API tests using
  independently sourced transition expectations. Reuse existing transition
  corpora where their semantic intersection covers the scenario.
- Run the multi-file application against local packages and the exact core/zone
  bundles. Update recursive discovery, example index and release handling if a
  new example folder is introduced.

Published examples must retain working immutable dependencies until a release
containing the direct native text APIs can be used.

## Application deadline and record

Add a focused application root that obtains a wall-clock reading from an actual
pinned Roc platform and passes it to a pure deadline module. The pure module
accepts an explicitly unit-labelled POSIX coordinate, parses an expiry timestamp,
compares it with the supplied reading and serializes a record containing a typed
`OffsetTimestamp`. Demonstrate the exact-expiry boundary: valid strictly before
expiry, expired at and after it. State that wall-clock expiry is not a monotonic
timer or a physical elapsed-time measurement.

Use the actual published basic-cli `0.22.2` platform for the CLI application:
[immutable bundle](https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst),
source revision `23622ee334755e18118bfc885a20f53fa4a16d66`.
Its [Utc.now!](https://github.com/roc-lang/basic-cli/blob/23622ee334755e18118bfc885a20f53fa4a16d66/platform/Utc.roc#L8)
returns U128 POSIX epoch nanoseconds. The wrapper replaces `ClockBeforeEpoch`
with zero; the [host implementation](https://github.com/roc-lang/basic-cli/blob/23622ee334755e18118bfc885a20f53fa4a16d66/src/lib.rs#L1933)
identifies that failure path. A caller must not treat the fallback as a genuine
clock reading.

Restrict this CLI acquisition adapter explicitly to positive current-epoch
readings: reject zero as `UnavailableOrEpochClock`, checked-convert with
`U128.to_i128_try`, then apply the explicit precision policy through the core.
The adapter cannot distinguish a genuine epoch reading from the platform's
fallback. Keep signed readings supported in the pure deadline function and its
deterministic tests. Test the zero rejection separately from valid negative
inputs to that pure function; never claim the platform exposes a recoverable
clock error. No monotonic conversion or core platform dependency is needed.

Reuse `PosixBoundary.from_microseconds`, checked `from_nanoseconds` or
`from_nanoseconds_with_rounding`, and `OffsetTimestamp.from_boundary` plus its
generic string codecs. Choose precision reduction explicitly when the platform
provides finer-than-microsecond readings. Integer millisecond convenience is
justified only if the chosen caller supplies that unit; then centralize checked
conversion rather than copying overflowing multiplication into an example.

Executable acceptance:

- Run the actual platform effect in a smoke application; deterministic tests
  supply fixed readings to the same pure deadline module.
- Check negative epoch input, one-microsecond differences, exact expiry, checked
  overflow and rejected submicrosecond input. Explicit rounding tests must cover
  negative values and carry across a second boundary.
- Check the JSON record's independently expected timestamp string and decode
  failures, as well as a semantic round trip. Use six fractional digits when
  necessary for exact microseconds; preserve unsupported timestamp year ranges.
- Run local and distributable examples with the pinned compiler and meaningful
  fuzz/oracle evidence for any new conversion behavior. Existing checked
  constructors do not require a duplicate arithmetic implementation.

## Scope and completion

Implement the named-zone example first, then the platform-clock application with
the explicit acquisition boundary above.
Localized presentation, human relative phrases, timer/sleep services, a general
zoned wrapper and speculative unit helpers are deferred until a concrete caller
needs them. The broader design's outstanding obligations remain in
[implement-design.md](implement-design.md).

Remove each deliverable when its executable acceptance and user documentation
land; remove this plan when both workflows are established. Keep implementation
history and verification transcripts in commits, not this plan.
