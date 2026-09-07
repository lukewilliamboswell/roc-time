# Derived duration-key hashing crashes the pinned compiler

On Linux x86_64 with `nightly-2026-09-06-d85e877`, both roots pass `roc check`.
Interpreting the failing root or building it with native dev/speed exits 139,
reporting a compiler SIGSEGV at `0x8`. Expected execution output is `Ok(73)`.
This failure needs neither fuzz instrumentation nor schedule persistence.

```sh
"$ROC" check tests/compiler_repro/structural_duration_hash/main.roc
"$ROC" tests/compiler_repro/structural_duration_hash/main.roc -- 1
"$ROC" build tests/compiler_repro/structural_duration_hash/main.roc --opt=dev --output=.roc-time-tmp/duration-hash-dev
"$ROC" build tests/compiler_repro/structural_duration_hash/main.roc --opt=speed --output=.roc-time-tmp/duration-hash-speed
```

`HashKey` hashes a structural union whose calendar branch contains calendar
components, an invalid-date policy and a nominal `PosixDelta` tail. The runtime
key is coordinate-only, but the calendar branch is part of its declared type.
The reproducer imports existing public quantity types from the local package;
it does not depend on `ScheduleDefinition`, `ScheduleEndings` or `Persistence`.

The [scalar control](scalar/main.roc) changes only the synthesized key's tail
field from `value.tail` to `PosixDelta.to_microseconds(value.tail)`. It checks,
interprets, builds and executes in both native modes, returning `Ok(73)`:

```sh
"$ROC" tests/compiler_repro/structural_duration_hash/scalar/main.roc -- 1
"$ROC" build tests/compiler_repro/structural_duration_hash/scalar/main.roc --opt=dev --output=.roc-time-tmp/duration-hash-scalar-dev
.roc-time-tmp/duration-hash-scalar-dev 1
"$ROC" build tests/compiler_repro/structural_duration_hash/scalar/main.roc --opt=speed --output=.roc-time-tmp/duration-hash-scalar-speed
.roc-time-tmp/duration-hash-scalar-speed 1
```

The reduced hash intentionally omits some calendar policies: unequal values
may collide, while equal values still hash equally. This is a compiler fixture,
not the package's complete semantic hash implementation. Production ending
hashing explicitly feeds the discriminator and every equality-relevant field,
retaining policies and override source identities. No requirement is removed
to avoid this crash.

These observations isolate a compiler defect involving this derived-key shape;
they do not establish its internal cause or imply that nominal hashing in
general fails. This is a known-failure reproducer. Recheck both roots and the
public declaration/Value dictionary gates when changing the compiler pin.
No upstream report has been sent.
