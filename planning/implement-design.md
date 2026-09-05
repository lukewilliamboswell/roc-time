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
[README](../README.md#tests) and [test evidence](../tests/fuzz/README.md).
The release manifest is `tests/fuzz/dependency.json`; runtime data stays under
`.roc-time-tmp/` by default. Normal CI invokes one gate; a separate weekly
workflow configures longer campaigns and artifact retention.

Remaining host evidence: Linux x86-64/musl runtime and scheduled workflow
execution are not verified locally. This is not evidence of failure or a reason
to describe those hosts as passing. Extend the generated properties through the
later implementation slices (R05–R14) and retain separate R15–R16 resource and
backend checks.

## Next slice

Implement the Gregorian civil-date and shared civil-day profile (R05–R06),
including explicit ranges, negative years/year zero, round trips and ordered
month-end arithmetic. Promote the invoice scenario through the public package
and add its generated evidence through the consolidated test runner.

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

Next implement ordered arithmetic with explicit destination policy, the invoice
application, and cross-calendar equal-day fixtures. Conversion alone does not
complete R05–R06. Keep unsupported calendar dispatch explicit as providers land.

### Oracle evidence before extending calendar semantics

Follow the durable [oracle harness strategy](../docs/oracles.md), including its
first Gregorian milestone and explicit distinction between implemented evidence
and proposed harness work.

The current Gregorian tests provide algorithmically distinct sequential counting
and generated next-day checks, but share calendar assumptions and manually
entered epoch anchors with the implementation. They are not an independently
sourced conformance corpus. The coverage bitmap model independently checks set
membership on a bounded domain; its query scan still uses production-normalized
members and `PosixSpan.overlaps`, so that check establishes search/scan agreement
rather than independent construction or overlap correctness.

Implement the first external oracle harness for Gregorian conversion before
extending calendar arithmetic. Compare public API observations against a pinned,
independently generated Gregorian corpus over the external provider's actual
domain; verify the comparison protocol detects wrong values and missing cases.
Keep year-zero/negative-year and provider-limit evidence separate from direct
external comparisons. Python `datetime` supports years 1–9999: applying a
400-year translation outside that domain supplies derived model evidence, not
direct Python conformance. A local CPython 3.14.3 probe confirmed its rejection
of year zero and -1 and its epoch-relative result -719162 for 0001-01-01.
This probe informs harness selection; it did not execute roc-time or establish
new package conformance evidence. Durable fixture provenance, reproducible
generation, exact case accounting, disagreement handling and finite CI budgets
are required deliverables for this harness.

Source inspection also found that CPython 3.14.3 `days_before_year` uses the same
January-based leap-count formula as our forward conversion. External maintenance
therefore provides useful differential evidence, but not forward-algorithm
independence. Its inverse conversion uses cycle decomposition rather than our
binary search. Record independence per operation, and retain the distinct
sequential model and independently sourced convention anchors.

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
evidence remain. Gregorian conversion now has separate evidence above; calendar arithmetic and later layers remain unimplemented.
