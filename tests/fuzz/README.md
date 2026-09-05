# Temporal property targets

The test roots `tests/precision/main.roc`, `tests/spans/main.roc`, `tests/coverage/main.roc`, `tests/gregorian/main.roc`, `tests/arithmetic/main.roc`, `tests/calendars/main.roc`, `tests/clock/main.roc`, `tests/offsets/main.roc`, and `tests/zones/main.roc`
import the real public package and the content-addressed
[roc-fuzz 0.3.0 release](https://github.com/lukewilliamboswell/roc-fuzz/releases/tag/0.3.0).
`dependency.json` records the release commit and independently verified SHA-256.
The runner verifies the archive digest; targets keep the release URL directly.
No local checkout or platform rebuild is required.

Each root wires the platform to a separate pure type module (`PrecisionCase`,
`SpanCase`, `CoverageCase`, `GregorianCase`, `ArithmeticCase`, or `CalendarCase`). Generators and semantic checks live in those
modules; the runner records their source hashes along with the root and public
package modules. Moving code into type modules does not change the saved-input
decoders, and the named-case replay checks validate that contract.

| Target | Domain and property |
| --- | --- |
| `precision-v1` | R01: all signed I64 coordinates/displacements with extra limit/zero cases; checked addition/subtraction against I128; microsecond-aligned nanoseconds and deliberate precision errors; nearest rounding bounded by half a microsecond with even ties; comparison operators against raw I64 order and dictionary lookup for equal boundaries. |
| `spans-v1` | R03: all signed endpoint coordinates, deliberate invalid constructors, and valid ordered spans; all 13 relation predicates and inverses against endpoint order, plus an enumerated small-domain membership/overlap oracle. |
| `coverage-v2` | R04: two lists of up to sixteen spans with starts in [-8, 8] and integer widths in [1, 17]; every integer point in [-9, 26] checks construction, union, intersection, difference, finite complement, count and width against raw-field membership; algebraic laws and owned/shared/sliced inputs; dictionary lookup across equal canonical values and whole-span iterator output. |
| `gregorian-v1` | R05: full Gregorian provider day range with endpoint/year-zero bias; coordinate and field round trips, independent next-day field progression, malformed fields and out-of-provider coordinates. Fixed tests separately enumerate all 292,194 days in years -400 through 399 against a sequential day counter. |
| `arithmetic-v1` | R05: full provider years with endpoint/year-zero bias; years ±2, months ±24 and days ±60 against a field-walking oracle for Reject/Clamp/Carry; I64 extreme components assert range failures. The model shares Gregorian month/leap conventions but neither production civil conversion nor month-index arithmetic. |
| `calendars-v1` | R06: full Julian provider coordinates with endpoint/epoch bias; cross-calendar shared-day equality vs description identity, Gregorian overlap range errors, Julian four-year periodicity, unsupported-name rejection, local calendar conversion preserving clock labels and distinguishing position from description. Independent generated Julian oracle modules anchor the conversion algorithm. |
| `clock-v1` | R01/R07/R08: numeric positions from -1 through 86400000000; explicit range errors, field reconstruction, microsecond adjacency and ordering. An exhaustive field-counter oracle independently checks all 86,400 seconds at three fractional positions. |
| `offsets-v1` | R01/R07/R08: full I64 POSIX coordinates with limit bias and full I32 offsets; both calendar projections, exact round trips, explicit offset sign and final range errors; immutable rule lookup against an independent step-function model, including excluded validity endpoints. RFC 3339 section 4.2 supplies a separate sign-convention fixture. |
| `zones-v1` | R07: two synthetic transitions, offsets -2 through 2 seconds, local labels within a complete finite rule domain and arbitrary microsecond fractions; classification and half-second selection membership compared with independent timeline-cell enumeration. Fixed fixtures add three-occurrence folds, a skipped local day and incomplete-domain errors. |

Bounds apply before production calls. None of the targets discards expected
structured error paths. The small-domain coverage oracle complements full-range
boundary/span checks and deterministic extreme-width tests in `CoverageTests`.
It is not an allocation measurement or evidence of Wasm support.

## Curated inputs and replay contract

Each semantic corpus includes four intentionally constructed 128-byte inputs:
`zero` (all 0), `ones` (all 255), `ramp` (0 through 127), and `alternating`
(`[0,255,1,127,128,2,254,42]` repeated sixteen times). They were curated on
2026-09-05 to exercise complete records, list lengths, shared/sliced construction,
signed-limit selectors, and arbitrary numeric payloads. They are starter cases,
not discoveries of a library defect. The runner copies them into disposable
campaign directories before mutation; searches never modify the curated files.

Consolidation also retained 64-byte zero, one-byte-value-255, and ascending
patterns from the second implementation (`pattern64-*`). Its thirteen named
Allen examples were migrated into the retained span generator as `relation-*`:
`span_cases.json` records their semantic inputs and the runner checks their
decoded `show` values before accepting the migration. They retain the anchor
[0, 3) and the corresponding relation case, rather than reusing bytes that
decode differently under the full-range generator. In roc-fuzz 0.3.0 the
retained encoding stores the fields in reverse order, each as eight
little-endian two's-complement bytes followed by selector 5.

`coverage-v2` deliberately broadens list length from 8 to 16 and width from 8
to 17 to preserve the second implementation's broader input domain. Starter
inputs were re-curated under that decoder; none was a discovered semantic
regression. The span and precision decoder versions are unchanged.

Raw-to-typed decoding depends on the target generator and roc-fuzz revision.
Changing field order, generator choice, or the platform can change its meaning.
Bump the target's `-v1` name on such changes, review `show` output, and retain
the old generator/revision or migrate named semantic regressions deliberately.
Do not treat printed `show` text as the raw replay format.

`corpus/lifecycle_fixed/byte-42` is the single byte `0x2a`. Its provenance is the
failure lifecycle exercised on 2026-09-05, compiler
`nightly-2026-09-04-c125b82`, LLVM speed backend with `--fuzz`, `arm64mac`, roc-fuzz
revision `ec137edcf0fa2530e3dbb175fec4ddff5281cc6d`. The deliberately failing
`tests/lifecycle/main.roc` drives the pure check that asserted byte 42 was forbidden. Seed `before*after`, seed
number 1, 100-run/5-second bounds produced exit 77 and a saved reproducer;
`show`, `replay`, and `minimize` reduced it to `[42]`. The fixed harness accepts
all bytes and replays it successfully. This verifies the failure pipeline; it
is intentionally separate from the passing semantic targets and is not claimed
as a roc-time bug. The lifecycle check repeats these assertions in normal CI.

## Verified execution

On Apple Silicon macOS, all nine targets built from the release URL, replayed
the curated inputs, and passed 10,000 runs each with seed 1, 5-second maximum,
256-byte input maximum, 256 MB RSS limit, and 2-second per-input timeout.
Coverage counters were present. Exact runnable commands live in CONTRIBUTING.md
and `scripts/fuzz.py`. Linux x86-64/musl is configured from the upstream platform
and must pass the CI gate, but runtime execution has not been verified locally.
Other host/architecture combinations explicitly report fuzz checks as unverified.
