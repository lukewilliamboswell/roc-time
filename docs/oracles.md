# Oracle evidence

Oracles are a central part of roc-time's verification method. They provide
expected meaning independently of the implementation under test. A generated
round trip can pass when both directions use the wrong epoch; a recurrence
engine can consistently implement clamping where its RFC profile requires
skipping. The [design contracts](../design.md#acceptance-requirements) determine
the intended behavior. Oracles challenge both the algorithm and its interpretation
of those contracts. Neither a library majority nor a passing fuzz campaign
establishes that the chosen contract meets a caller's need.

This document specifies the enduring harness strategy. The cross-language
runner and Gregorian corpus below are **proposed, not implemented or verified**.
Existing evidence includes integer arithmetic checks, endpoint predicates,
small discrete coverage models, and a sequential Gregorian model in Roc.
The Gregorian model shares leap/month rules and manually entered epoch constants
with the implementation; its different traversal catches algorithm defects but
does not independently establish those conventions. Implementation status and
remaining work belong in the [active plan](../planning/implement-design.md).
Coverage's exhaustive bitmap checks establish bounded set membership evidence;
its query-vs-scan checks reuse production-normalized spans and overlap predicates,
so those checks establish search consistency rather than independently proving
construction or overlap semantics.

## Choosing an oracle

For each semantic change, record the requirement, realistic caller question,
input domain, policies, successful result, errors, and what could make all the
tests agree on the wrong answer. Use complementary evidence:

| Evidence | Useful independence | Limit |
| --- | --- | --- |
| Primary specification or sourced fixture | Establishes externally defined meaning and concrete answers | A source can be ambiguous, wrong, or outside our advertised profile |
| Small exhaustive reference model | Uses enumeration or a simple representation instead of the production algorithm | Proves agreement only on the enumerated domain; shared assumptions still need review |
| Differential implementation | Exercises another implementation and language/runtime | Shared algorithms, source ancestry, and data can produce correlated errors |
| Algebraic laws and metamorphic checks | Explore broad domains with roc-fuzz | Mutually consistent bugs may preserve every law |
| Caller scenario with reviewed expected result | Checks that the observable answer addresses the intended task | A few scenarios do not establish general conformance |

Pair semantic claims with an independent model or sourced expected result as
well as applicable laws. State independence precisely: different code is not
necessarily a different algorithm, and two wrappers around the same library
are one oracle. Document common algorithm ancestry, shared rule data and common
normalization code. Test-only reference models may deliberately enumerate
bounded domains; they must not become a second production interpretation engine.

Compare only a declared intersection of semantics: epoch, units, calendar and
year numbering, day boundary, precision, range, interval closure, rounding,
gap/fold policy, recurrence ordering, and error categories. Never silently clamp
input to another library's range or convert via floating-point timestamps.
An oracle's unsupported domain is a recorded coverage gap, not a passing case.
Expected disagreements need named cases, the precise policy difference and a
contract reference; avoid blanket exceptions or catch-all ignored errors.

## Harness boundary

Keep `scripts/fuzz.py` as the single roc-fuzz runner. Add a separate deterministic
oracle comparison gate, proposed as `scripts/oracles.py`, invoked once by
`scripts/all_tests.py`. It must exercise public package modules, with application
roots at `tests/oracle_<domain>/main.roc` and pure driver logic in type modules.
Version readable input/expected records and manifests under `tests/oracles/`.
Keep generated batches, compiler products and raw diagnostics under
`.roc-time-tmp/oracles/`. Reference tools run outside the production core.

The first transport can generate a bounded Roc data module and app under the
disposable directory, importing the real package and a maintained pure driver.
This avoids adding a JSON/parser or platform dependency just to test calendars.
Generate only typed numeric/tag literals from validated records, never splice
arbitrary source strings. Expected values remain on the Python side: the Roc
driver receives inputs and emits actual values. A future streaming transport
can reuse the same case contract when a suitable pinned platform is available.

Use a versioned record envelope containing case ID, operation, semantic profile,
typed input, context/fixture identity, expected success or structured error, and
oracle provenance. Represent I64/I128 values in exchanged JSON as decimal
strings; prohibit floating conversion. Match outputs by case ID, requiring
exactly one result per requested operation. Missing, duplicate, malformed or
unexpected output, a crash, timeout, and setup failure all fail the gate.
Keep diagnostics separate from machine-readable results. Compare error classes
and relevant payloads, not incidental diagnostic wording. Normalize only the
explicitly declared representation differences; never normalize away qualifiers,
identity, disconnected coverage or `Limited` results.

Manifests must identify source URL and section, release/revision, fixture hashes,
generator revision, semantic profile, generation command and seed, adapter
version, reference runtime/version, license and required notices. Separate
hand-reviewed anchors, externally generated cases, and model-derived cases.
Do not relabel generated expected values as primary-source facts. Normal CI
replays versioned expectations without live oracle downloads; refreshing them
is an explicit command whose diff is reviewed. Never regenerate expectations
from roc-time output or automatically bless a mismatch. Pin and verify downloaded
reference artifacts; record exact versions even for standard-library generators.

Check the harness itself: inject a wrong expected result, delete/duplicate a
result, corrupt a record and simulate a driver failure. Each must fail with an
actionable case ID or setup diagnostic. Check an epoch-shifted Gregorian fake
result fails even when its own forward/inverse round trip would succeed. These
checks validate comparison plumbing and do not count as package correctness.
Also inject a missing leap-day result to check calendar-sensitive comparison.

## First executable slice: Gregorian conversion

R05 currently supports astronomical years across the signed 32-bit range and
civil day zero at Gregorian 1970-01-01. A minimal useful oracle milestone should
compare both public conversions independently, plus constructor errors:

1. Generate expectations with Python `datetime.date.toordinal()` and
   `date.fromordinal()` for the overlapping range 1–9999. Subtract the ordinal
   of 1970-01-01 to obtain our civil-day convention. Use date operations, never
   `timestamp()` or local zones. Python documents its idealized Gregorian
   calendar, ordinal convention and range in the
   [datetime reference](https://docs.python.org/3/library/datetime.html#date-objects).
   This provides an external implementation, not full-range evidence.
   Independence differs by direction: CPython 3.14.3's forward conversion uses
   the same January-based complete-year formula as roc-time, while its inverse
   decomposes calendar cycles rather than using our binary search. Record this
   shared algorithm ancestry in the manifest; external maintenance and runtime
   add evidence but do not make the forward formula independent. See the
   [pinned CPython implementation](https://github.com/python/cpython/blob/v3.14.3/Modules/_datetimemodule.c).
2. Build a test-only 400-year lookup model from that external cycle: enumerate
   dates in years 2000–2399, associate each with its offset from 2000-01-01,
   and translate complete cycles by 146097 days using unbounded Python integers.
   For any supported year, floor-divide `year - 2000` by 400 and use the cycle's
   remaining year/month/day. Inverse lookup uses the same table with an offset
   into a cycle, not production year counting or binary search. Compare the
   table model with direct datetime results across their overlap first.
3. Include reviewed convention anchors: 1970-01-01 maps to zero, the preceding
   day maps to -1, year zero is 1 BCE, century exceptions and a leap year zero.
   The astronomical numbering convention is independently described by
   [Python's calendar documentation](https://docs.python.org/3/library/calendar.html).
   The extension still relies on the Gregorian cycle law; do not present it as
   direct external-library support for negative or extreme years. Keep the
   existing sequential Roc model as complementary evidence.
4. Cover both year limits, year -1/0/1, negative century boundaries, 1582
   without a historical cutover, 1900/2000/2100, month ends and invalid fields.
   Do not interpret a historical Julian source date as proleptic Gregorian:
   record its original calendar and any explicit conversion first.
   Range errors beyond the provider limits are roc-time contract fixtures,
   because datetime's narrower range cannot decide them. Separate malformed
   single-field cases from cases asserting validation precedence.

Initial normal-CI budget: at most 4096 deterministic cases including all anchors,
with a fixed-seed remainder split between direct datetime and full-range cycle
expectations. Every valid case checks fields-to-day and day-to-fields against
expected values, rather than feeding one production result into the other.
Bound compile/run subprocesses independently (initial ceilings: 120 seconds
each), batch size and output bytes; report actual count, duration and failures.
Measure before changing the budgets. A longer explicit job can exhaust the
146097-day cycle; its evidence must say which backend and directions ran.
Keep roc-fuzz's bounded Gregorian exploration and curated replay alongside this
gate. They discover different counterexamples.

Acceptance for this first harness: pinned compiler verified; provenance complete;
reference models agree on their overlap; all committed cases replay through the
real public API; malformed and range cases return intended errors; harness
failure checks fail as intended; normal integration invokes the gate; exact
commands, case counts and supported host/backend recorded. This does not finish
ordered arithmetic or cross-calendar interoperability. Those require their own
policy fixtures and independent equal-day sources.

## Evidence by requirement

The following is the required selection strategy, not a claim these harnesses
already exist. Prefer the simplest model that answers the observable question.

| Requirement | Independent anchor or model | Comparison boundary and trap |
| --- | --- | --- |
| R01 | Unbounded integer/rational arithmetic and reviewed rounding tables | Exact scaled integers, negative ties, narrowing after rounding, accumulated overflow |
| R02 | Compile-failure fixtures with positive controls; incompatible-axis scenarios | Numerical agreement cannot establish domain safety |
| R03 | Enumerate endpoint orderings and their definition-level Allen classification | Half-open touching and nonempty preconditions; a library's interval closure may differ |
| R04 | Exhaustive bitmap sets over a small finite universe | Compare membership and canonical output, not only set identities; retain full-range edge fixtures |
| R05 | Gregorian external ordinals plus cycle/sequence models; hand-worked ordered arithmetic | Year numbering, negative floor division, clamp/reject order; clamping is not invertible |
| R06 | Independently sourced equal-day fixtures for each supported calendar | Explicit day convention, epoch, supported range and any location/day-boundary context |
| R07 | Enumerate mappings through small synthetic transition tables; fixed real-rule cases | Distinguish boundary appointment from selection preimage; include non-hour gaps, folds and skipped dates |
| R08 | Authoritative scale definitions and versioned conversion tables where supported | POSIX width is not SI elapsed time; unsupported leap semantics must stay explicit |
| R09 | Instrumented supplied providers and paired immutable rule snapshots | Assert lookup counts, invalidation and unchanged same-axis comparisons, not just values |
| R10 | Tiny event multiset model retaining contributor IDs at every discrete cell | Equal extents preserve distinct identities; coverage projection intentionally loses them |
| R11 | RFC examples and small direct candidate-set enumeration; separately pinned differential libraries | Series COUNT, exclusions, invalid dates, BYSETPOS and window restriction; match profiles before comparing |
| R12 | Bounded state-machine trace model with candidate/buffer/output accounting | Compare resumed/uninterrupted identities and completion state; output equality alone misses excess work |
| R13 | Enumerate all admissible models in a bounded universe | None/all/some classification, inconsistent evidence and unsupported scope |
| R14 | Grammar/specification fixtures and independently authored persistence records | Semantic resolution/qualifiers/errors; round trips alone can preserve an incorrect parser interpretation |
| R15 | Operation/lookup counters plus instrumented allocation and retention measurements | No functional oracle establishes complexity or zero allocation; keep measurement workload and backend explicit |
| R16 | Real public applications and identical fixtures across advertised backends | Native/Wasm agreement is compiler diversity evidence, not independent semantic truth |

For zones, the [IANA time-zone project](https://data.iana.org/time-zones/tz-link.html)
provides versioned rule data. Pin the selected release and record extraction
commands; never let the host database define expected results. A second library
using the same rules tests interpretation, not independent historical accuracy.
For recurrence, use the actual clauses and examples in
[RFC 5545](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.10), including
[recurrence-set construction](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.8.5.1),
and review applicable errata when selecting a conformance profile. Tempo remains
an important differential source and inspiration; preserve attribution and
record the exact revision, but do not treat it as the sole correctness oracle.

## Resolving disagreement

Preserve input, each oracle's raw answer, normalized answer, profile, revisions
and the package result before minimizing. First distinguish transport failure,
domain mismatch, reference defect and package defect. Resolve conflicting
answers against the declared contract and primary evidence, not majority vote.
If the contract is ambiguous, settle and document it before changing expected
results. Keep unresolved disagreements visible as failed evidence; do not turn
them into successful skips.

Minimize while preserving the semantic preconditions and the disagreement.
Save a readable public-API regression with provenance and, where applicable,
the roc-fuzz raw input and generator revision. A deterministic differential
case need not have a fuzz encoding; adapt it explicitly rather than inventing
one. Report coverage gaps, excluded domains, exact tool revisions, case counts,
budgets and host/backend. Update oracle adapters and their provenance whenever
the public semantic profile changes.
