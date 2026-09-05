# Implement the temporal design

Objective: implement the architecture and executable acceptance requirements R01–R16 in design.md, without reducing the goal to the initial kernel.

The repository initially contains only packaging scaffolding. No earlier active plans were present when implementation began.

## Dependency order and deliverables

1. Exact nominal POSIX boundaries, coordinate displacements, nonempty spans and all Allen relations; precision/range and wrong-domain evidence (R01–R03, R08).
2. Canonical flat coverage, sweeps, binary searches and independent discrete-domain oracle (R04).
3. Gregorian civil conversion and ordered calendar arithmetic, explicit calendar interoperability profile (R05–R06).
4. Immutable zone fixtures and resolution, distinct appointments and selections, snapshot evidence (R07–R09).
5. Events, projection and contributor-preserving splitting (R10).
6. Stateful recurrence with explicit RFC profile, candidate/output budgets and resumptions (R11–R12).
7. Shared semantic adapters and versioned persistence, uncertainty and supported reasoning (R13–R14).
8. Promote every design scenario to a public executable example; domain failures, native/Wasm evidence and measured resource behavior (R15–R16).

For each slice, settle its public profile in design.md, add meaningful tests following the [property-based testing method](../AGENTS.md#property-based-testing), and run pinned module checks/tests and integration tooling. Completion requires evidence for every acceptance requirement, not just green scaffolding tests.

## roc-fuzz integration

The local integration acceptance criteria are met: the single `scripts/fuzz.py`
runner builds the public-package roots at `tests/<scenario>/main.roc`, checks their
pinned 0.3.0 release URL and SHA-256, replays curated inputs, runs bounded searches,
and verifies the full failure lifecycle. The consolidated full integration
command passed on Apple Silicon macOS with `nightly-2026-09-04-c125b82` and the
LLVM speed backend. Each semantic target completed 10,000 runs with seed 1,
5-second maximum, 256-byte inputs, 256 MB RSS and 2-second per-input limits.
The duplicate runner was removed at the user's request, with its extra checks
and thirteen named Allen cases migrated and verified under the retained decoder.

Enduring commands, domains and raw-input provenance are in
[contributor guide](../CONTRIBUTING.md#tests) and [test evidence](../tests/fuzz/README.md).
The release manifest is `tests/fuzz/dependency.json`; runtime data stays under
`.roc-time-tmp/` by default. Normal CI invokes one gate; a separate weekly
workflow configures longer campaigns and artifact retention.

Remaining host evidence: Linux x86-64/musl runtime and scheduled workflow
execution are not verified locally. This is not evidence of failure or a reason
to describe those hosts as passing. Extend the generated properties through the
later implementation slices (R05–R14) and retain separate R15–R16 resource and
backend checks.

## Next slice

The static-dispatch milestone implements ordering hooks for the four ordered
scalar domains, equality-consistent scalar/span/coverage hashes, whole-span
Coverage iteration and domain-labelled inspection. Tests exercise public
operators, dictionary lookup across independently constructed equal values,
canonical segmentation and empty/nonempty iteration; mixed-domain ordering
must fail typechecking. Generated boundary and coverage checks now also exercise
these hooks without changing their input decoders. Named arithmetic and explicit
numeric units remain necessary for checked errors and interpretation safety.
The pinned full integration command passed on 2026-09-05, including both static-
dispatch execution paths, all five 10,000-run campaigns, the external conversion
oracle, and all three bundled applications.

The zone input foundation now includes opaque `ClockTime`, explicit field and
leap-second errors, constant-cost coordinate conversion, and an independent
odometer oracle covering 259,200 labels. The `clock-v1` generated target checks
arbitrary fractions and adjacent labels. This does not implement resolution;
local date attachment, immutable zone rules and transition interpretation remain.
The full pinned integration command passed on 2026-09-05 with all seven
10,000-run campaigns, both oracle gates and all four bundled applications.
The interpreter required shared-memory access outside the sandbox; the successful
rerun supplies runtime evidence. Formatting and diff checks also passed.

Implement immutable zone fixtures and resolution (R07–R09), keeping boundary
appointments distinct from local selections. Include independent transition
evidence, provider validity limits and provenance; never infer host zone data.

The initial R06 profile now includes proleptic Julian conversion across the full
signed I32 year domain, explicit Gregorian/Julian dispatch, and calendar-tagged
day descriptions. Equal extents remain distinct from equal descriptions.
The reform-date anchor is sourced from Hinnant; 4,096 generated Julian oracle
observations use his independent March-based formulas against production's
January counting and binary-search inverse. Unknown calendars and destination
range failures remain explicit. The archive example preserves its source date
while displaying the corresponding Gregorian catalogue date.

Verified on 2026-09-05 with the full pinned integration command: six semantic
targets completed 10,000 runs each, both 4,096-case oracle drivers passed, and
all four applications passed interpreted and native bundle execution. Formatting
and `git diff --check` passed. This establishes the supported calendar profile,
not support for context-dependent calendars, historical regional reforms or zones.

Conversion is implemented in `CivilDay` and `GregorianDate`, separating the
shared day coordinate from validated Gregorian descriptions. The provider
range is the full signed 32-bit year domain, computed in I64. January-based
counting and a bounded inverse search avoid negative-year truncation and
unchecked narrowing. Deterministic evidence enumerates all 292,194 dates in
years -400 through 399 using a sequential calendar model. Generated evidence
covers the entire provider day range, field/coordinate round trips, next-day
progression, malformed fields, and range rejection. A compile-failure fixture
rejects civil coordinates passed as POSIX boundaries. The pinned full integration
command recorded below passed on 2026-09-05 with all four semantic targets,
including 10,000 Gregorian runs (seed 1, five-second maximum, LLVM speed/arm64mac).

`CalendarDelta` and `CalendarArithmetic` implement ordered years/months/days
with Reject, Clamp and Carry, full-I64 component handling and intermediate range
checks. The invoice application uses an explicit clamp business rule. Generated
checks compare all three policies with a bounded field-walking oracle; fixed
cases distinguish component order, a single two-month destination, noninvertible
clamping and negative-year rollover. POSIX displacement is rejected as a calendar
delta by an intended-diagnostic compile-failure check. Calendar arithmetic remains
Gregorian-specific; additional providers do not imply arithmetic support.

Interpreter investigation found a pinned-compiler defect in `?` propagation from
a checked integer result into an error union containing a record payload. Native
execution was correct. Equivalent explicit error mapping fixes calendar
arithmetic without changing its public errors; the retained minimal reproducer
is `tests/compiler_repro/result_widening/`. The full pinned integration command passed after the explicit mapping on
2026-09-05: all five semantic targets completed 10,000 runs each, the generated
Gregorian oracle replay passed, and all three applications passed both
interpreted and native execution against the bundle.

### Oracle evidence

The Gregorian oracle gate is implemented in `scripts/oracles.py` and
`tests/oracle_gregorian/`. It replays 4,096 committed observations, including
separate field-to-day and day-to-field expectations, malformed fields and
provider endpoints. CPython 3.14.3 generates direct expectations for years
1–9999; a table of its 2000–2399 cycle supplies explicitly derived expectations
outside that range. Generation verifies both directions over all 3,652,059
shared-domain dates. Runtime uses the real public package and a native driver;
checked-in `Cases.roc` contains typed inputs and reference-derived expectations,
compared directly by the native driver without JSON case parsing. Commands and limitations are in CONTRIBUTING.md.
The full pinned integration command passed on 2026-09-05, including comparator
corruption checks, a failing-driver control and all 4,096 native observations
(0.68 seconds for check/test/build/run on Apple Silicon macOS after switching
to generated Roc fixtures).

CPython's forward formula shares our January-based leap counting, while its
inverse uses cycle decomposition rather than our binary search. Keep the
sequential model and sourced convention evidence alongside these comparisons.
Coverage's bitmap oracle independently checks bounded membership; its query
scan reuses production-normalized members and overlap predicates, so that scan
establishes search agreement rather than independent overlap correctness.

Extend oracle evidence as arithmetic and other temporal capabilities land;
the separate Julian gate supplies cross-calendar conversion evidence; neither
gate implies zone, recurrence or resource evidence.

## Unresolved decisions

Calendar/provider ranges, calendar interoperability scope, zone policy signatures, RFC adapter feature profile, persistence schema and supported reasoning profile must be settled with evidence as their slices land. Allocation/layout and supported Wasm claims require measurements on the pinned compiler.

## Implementation evidence

`PosixBoundary`, `PosixDelta`, `PosixSpan`, and `Coverage` are implemented.
The construction-bypass test found and corrected nominal-but-transparent types;
all invariant-bearing public types now use opaque `::` declarations. Four
compile-failure fixtures assert intended domain/representation diagnostics.
Explicit numeric rounding, interval-collapse rejection, relation inverses,
canonical construction, sweeps, binary-search queries and checked accumulated
width have deterministic and generated evidence. The exhaustive point oracle
enumerates all pairs of four-point subsets, supplemented by overlapping-span
construction/query cases and full-range width limits. The public microsecond and
resolved-availability examples run against the bundle in interpreter and native
execution. API profiles are documented in design.md.

Verified with `ROC=.roc-time-tmp/roc_nightly-macos_apple_silicon-2026-09-04-c125b82/roc python3 scripts/all_tests.py`
on 2026-09-05; pinned version confirmed. The suite passed after granting localhost
access for bundle verification, including the single consolidated fuzz gate, migrated corpus replay, and the complete failure lifecycle.
The merged precision/span/coverage checks were also verified with
`ROC=.roc-time-tmp/roc_nightly-macos_apple_silicon-2026-09-04-c125b82/roc python3 scripts/fuzz.py --operation all`
using explicit `--opt=speed`. Layout/allocation, complexity measurements and Wasm
evidence remain. Gregorian conversion now has separate evidence above; calendar arithmetic now has evidence above; other calendar providers and later layers remain unimplemented.
