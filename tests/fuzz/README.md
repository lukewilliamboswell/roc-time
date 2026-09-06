# Temporal property targets

The test roots `tests/precision/main.roc`, `tests/spans/main.roc`, `tests/coverage/main.roc`, `tests/gregorian/main.roc`, `tests/arithmetic/main.roc`, `tests/calendars/main.roc`, `tests/clock/main.roc`, `tests/offsets/main.roc`, `tests/zones/main.roc`, `tests/events/main.roc`, `tests/patterns/main.roc`, and `tests/recurrence/main.roc`
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
| `descriptions-v1` | R02/R07/R13–R14: full-day decimal grids at all six fractional resolutions, hour/minute/second/day widths and midnight carries; independently constructed two-segment gap/fold preimages, zero-work stops and resumptions; qualification set preservation under reordering/sharing, omitted-component and duplicate-scope errors, and no inferred certain coverage from qualifiers. Finite alternative truth is compared with direct cell enumeration, including singleton/duplicate models, endpoint adjacency and resumptions. Paired and independent interval models are checked by explicit enumeration of valid pairs over up to six boundary values, including I64 extremes, every membership breakpoint and inconsistent/empty evidence. |
| `clock-v1` | R01/R07/R08: numeric positions from -1 through 86400000000; explicit range errors, field reconstruction, microsecond adjacency and ordering. An exhaustive field-counter oracle independently checks all 86,400 seconds at three fractional positions. |
| `offsets-v1` | R01/R07/R08: full I64 POSIX coordinates with limit bias and full I32 offsets; both calendar projections, exact round trips, explicit offset sign and final range errors; immutable rule lookup against an independent step-function model, including excluded validity endpoints. RFC 3339 section 4.2 supplies a separate sign-convention fixture. |
| `events-v1` | R10: up to twelve spans with source-order U64 identities, bounded numeric starts/widths; independent cell membership verifies contributor partitions, coverage projection and disconnected clipping, with duplicate-ID rejection and retained/shared source entries. |
| `patterns-v1` | R11 candidate layer: full Gregorian years with limit/year-zero bias, monthly intervals 1–3 and period indices 0–6; month-field walking verifies period bounds, and an independently enumerated 400-year weekday cycle checks signed month-day/weekday-position intersections. Zero selectors and out-of-range exclusive ends must fail explicitly. Fixed/source oracle cases cover the other date-selector combinations. |
| `recurrence-v1` | R11–R12/R14: 2024–2025 monthly schedules on day 31 or the last Monday, intervals 1–3, COUNT 1–6, duplicate inclusions, exclusions and query starts in every month. An independent month-table/weekday walk builds the finite set before query filtering. Native resumptions with 1–128 work steps and one output slot, and equivalent parsed RFC date values, must yield exactly that set. Duplicate COUNT parts must fail. Generated positive RFC H/M/S durations lower through TimedOccurrence and agree with an independent integer-second sum, without zone work; canonical text reparses semantically and malformed suffixes fail. The schedule model alternates native ending overrides with parsed RfcPeriod additions, preserving existing inclusions, source identities and UTC-grid widths under resumption. A separate half-hour grid with a forward or backward offset jump filters native UntilBoundary results against a piecewise arithmetic model, with one zone segment per resumption. Fixed tests add UNTIL, positive positions, zero/reduced buffer limits and provider endpoints. |
| `zones-v1` | R07: two synthetic transitions imported through the structural database adapter, offsets -2 through 2 seconds, local labels within a complete finite rule domain and arbitrary microsecond fractions; classification, explicit occurrence policies, snapshot provenance/re-resolution and half-second selection membership compared with independent timeline-cell enumeration. Fixed fixtures add three-occurrence folds, a skipped local day and incomplete-domain errors. |

The `interchange-v1` target covers R01–R02/R13–R14 through EdtfDate and
OffsetTimestamp. It generates Gregorian years 1900–2100, valid dates, three
date resolutions, four qualification choices, offsets from -23:59 to +23:59
and zero through six fractional digits. An independent year/month counter from
1900 predicts POSIX boundaries, sharing Gregorian leap rules but no production
date-conversion algorithm. Native fields and source resolution are checked
separately from canonical round trips. Invalid dates, incomplete prefixes,
out-of-profile offsets, leap seconds and seventh fractional digits require
specific errors. Four synthetic corpus patterns exercise this generator; they
are not minimized discoveries. Module unit fixtures independently transcribe
LOC date/qualification examples and RFC 3339/9557 offset facts, and cover the
four-digit year endpoints outside this generated domain.

The same unchanged generator also drives ExactInterval and Ixdtf. Independent
one-second spans check exact interval parsing and computed-span serialization;
a fixed pair reverses local-label order while retaining valid resolved order.
IXDTF cases retain ordered elective annotations and fractional width, compare
constant-zone projection with integer offset arithmetic, require explicit
context, and distinguish numeric assertion conflicts from unasserted UTC.
Re-resolution changes presentation under new supplied rules while the old
snapshot retains its result and both keep the same instant. Unsupported calendar
presentation and critical tags fail explicitly; fixed RFC module fixtures cover
annotation grammar, critical duplicates and alias provenance separately.

Persistence checks use the same generator and independently decode envelope
metadata with builtin JSON. They cover the nine declaration/scalar kinds, compare
stored boundaries with the existing Gregorian day-count oracle, and preserve
qualifiers, fractional width and offset assertions. Fixed I64 endpoints and
positive/negative 9007199254740993 exercise decimal string payloads beyond the
common JSON floating-point integer range. Unknown versions and incompatible units
must fail. Round trips supplement these independent field/coordinate checks;
they do not establish snapshot persistence or support for other value kinds.

The coverage target also persists native spans and coverage. An independent
unit-cell scan of the generated raw inputs derives the expected maximal runs and
their decimal endpoint payloads, without calling native coverage normalization.
It checks that gaps survive restoration and that touching, overlapping, duplicate
and out-of-order persisted members return `NonCanonicalCoverage`. Separate fixed
fixtures cover empty coverage, signed endpoint limits and the 1,024-member cap.

The descriptions target persists Gregorian and Julian values at every native
resolution. Expected payload fields come from generated input fields, including
the unscaled fractional integer and its supplied digit count. Checks preserve
calendar identity and both provider year limits, retain each qualifier's scope
and flags, canonicalize reordered qualifications, and reject duplicates or
qualifiers on omitted components. This tests native persistence, not additional
EDTF grammar or uncertainty interpretation.

Description explanation checks compare typed facts with generated calendar,
clock and fractional-resolution fields, and require scoped qualifications and
an explicit model requirement. Interchange explanation checks compare snapshot
position facts with the independent date-count oracle and retain unsupported
calendar presentation as a separate fact. Both exercise zero/small fact and byte
budgets; incomplete rendering must never report `Complete`. Exact-interval facts
are compared with independently calculated POSIX endpoints and the original
source offsets and fractional widths, including reversed local-label order.
RFC primitive facts retain local/UTC form, endpoint roles and separate calendar
days and coordinate seconds; PERIOD facts do not infer a zone or expand a
recurrence. These checks do not parse diagnostic prose to establish temporal
meaning or establish allocation bounds.

Snapshot persistence properties compare restored positions and offsets with
the existing independent integer model and preserve source/presentation facts.
A separate five-microsecond synthetic rule table changes its offset one
microsecond after the saved point. Another table reuses the same name, version
and current result but has a different later offset; persistence must retain
both tables distinctly and answer the later query with its declared offset.
These generated fixtures use supplied provenance; database provenance and
malformed payloads have deterministic native fixtures.

Civil snapshot persistence extends that target with independent two-second
fold and gap models. Generated shifts preserve First/Last/MatchingOffset policy,
modeled boundary positions, empty/disconnected coverage and mixed Gregorian/Julian
endpoint identities. The expected preimages come from the declared piecewise
integer offset function; persistence round trips supplement that model.

The recurrence target also compares `next`, stopped/resumed scalar folds and
Roc `Iter` chunks with its independent calendar set and ordered weighted sum.
Each traversal must preserve the same dates and respect work/output budgets.

Bounds apply before production calls. None of the targets discards expected
structured error paths. The small-domain coverage oracle complements full-range
boundary/span checks and deterministic extreme-width tests in `CoverageTests`.
It is not an allocation measurement or evidence of Wasm support.

The calendar interoperability target also checks year/month description bounds
across both provider ranges, including their signed limits, against independent
bounded enumeration of valid fields (at most 372 candidate dates per year).

## Curated inputs and replay contract

Each semantic corpus includes four intentionally constructed 128-byte inputs:
`zero` (all 0), `ones` (all 255), `ramp` (0 through 127), and `alternating`
(`[0,255,1,127,128,2,254,42]` repeated sixteen times). They were curated on
2026-09-05 to exercise complete records, list lengths, shared/sliced construction,
signed-limit selectors, and arbitrary numeric payloads. They are starter cases,
not discoveries of a library defect. The descriptions corpus applies the same four
byte patterns, curated on 2026-09-06 with the pinned compiler and roc-fuzz 0.3.0. The runner copies them into disposable
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

The offsets target also drives `RfcDateTime` with generated whole-second labels
on the days immediately before and after the epoch. An independent integer-second
grid checks UTC boundaries, local values must require context, canonical text
retains UTC/local form, and numeric-offset suffixes are rejected.

## Verified execution

Apple Silicon macOS and Linux x86-64/musl have verified execution through the
pinned release platform. The Linux gate covers all fourteen semantic targets,
curated replay and the failure lifecycle using LLVM speed with `--fuzz`, compiler
`nightly-2026-09-04-c125b82` and roc-fuzz 0.3.0
(`ec137edcf0fa2530e3dbb175fec4ddff5281cc6d`). Searches use seed 1, at most
10,000 runs or 5 seconds, a 256-byte input maximum, 256 MB RSS limit and a
2-second per-input timeout. A time-limited campaign may execute fewer than
10,000 inputs; these finite searches do not establish exhaustive correctness.
Exact runnable commands live in CONTRIBUTING.md and `scripts/fuzz.py`.
Other host/architecture combinations explicitly report fuzz checks as unverified.

Selection explanation properties use those independent fold/gap preimages to
check stored boundary policies, canonical members and source calendar identity.
Collection budgets of zero, one and eight distinguish limited evaluation from
complete empty coverage. Rendering completeness is checked independently of the
typed evaluation status, with zero/tiny output budgets and out-of-range fact
indexes. Fact access does not reinterpret the saved context.
