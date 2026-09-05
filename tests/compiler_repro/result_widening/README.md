# Pinned interpreter result-widening reproducer

On `nightly-2026-09-04-c125b82`, Apple Silicon macOS, interpret `main.roc`
with the pinned Roc executable. The expected result is `Ok` containing the original 2025-01-31 date
(originally displayed as `Ok(<opaque>)`, before custom inspection was added).
The observed result is `Err(InvalidDestination({ day: 1, month: 0, year: 2025 }))`.
The same root built with `roc build` and executed natively returns the expected
success. This fixture is a known compiler defect reproducer, not a passing
semantic gate or a claim of package invalid input.

`Probe.identity` converts an already valid year to I64 through a checked helper,
then propagates with `?` into a result whose error union includes a record payload.
Replacing that propagation with explicit `Ok(value)` / `Err(OutOfRange)` matching
returns the expected success under the interpreter too. CalendarArithmetic uses
that equivalent explicit mapping without changing its public error behavior.

The [room example](../../../examples/coverage/main.roc) also needs explicit
matching when propagating `Availability.report`'s `OutOfRange` error into the
app's union containing `DuplicateId(Str)`. With `?`, the interpreter reports
`DuplicateId("")` for a successful report; native execution succeeds. Verify
both execution paths before removing that mapping.

The code requires neither a clock nor an operating-system time service. This
reproducer is retained for a future compiler-pin update; no upstream report has
been sent. Do not remove the explicit mapping based on typechecking alone.
