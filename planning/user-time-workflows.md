# Everyday appointments and deadlines

Objective: complete the application-clock workflow and publish the staged caller
applications. Follow [R01–R02, R05, R07–R09 and R14–R16](../design.md#acceptance-requirements).
This is a caller-evidence project, not a request for a universal zoned datetime
type, a new resolver or a core clock service.

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

Implement the platform-clock application with the explicit acquisition boundary
above. When a compatible release includes the required APIs, promote the staged
[named-zone appointment application](../tests/zoned_appointment/main.roc) into
the public example collection with pinned compiler and core/zone URLs. Include it
in the starter kit and retain its independent fixture and exact-output gates.
Keep current public examples runnable until that release is available.
Localized presentation, human relative phrases, timer/sleep services, a general
zoned wrapper and speculative unit helpers are deferred until a concrete caller
needs them. The broader design's outstanding obligations remain in
[implement-design.md](implement-design.md).

Remove each deliverable when its executable acceptance and user documentation
land; remove this plan when the application and publication work is complete. Keep implementation
history and verification transcripts in commits, not this plan.
