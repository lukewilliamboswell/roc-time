# Contributing to roc-time

Read [design.md](design.md) for the temporal contracts and [AGENTS.md](AGENTS.md)
for engineering guardrails. Check any active task in `planning/` before changing
its scope. Issues and pull requests should identify a realistic caller scenario
and the affected design requirements.

Use the compiler pinned by `.roc-version`; verify its `version` output and set
`ROC` to its executable when running repository scripts. Keep experiments and
generated artifacts under ignored `.roc-time-tmp/`.

Examples are focused applications, not test fixtures. Each belongs in its own
folder with a `main.roc` entrypoint and pure logic in a separate type module.
Keep unit `expect` tests beside their implementation. Run them once with
`roc test package/main.roc`; the CLI discovers the package's module graph.
Do not add separate `*Tests.roc` unit modules or a per-module test loop.
Put integration fixtures and harnesses under `tests/` using the same root layout.
Update recursive discovery and verify local and bundled package usage when
adding or moving an example.

## Scripts


All repository tooling lives in `scripts/` and is written in Python 3 with no
third-party Python dependencies.

| Script | Purpose |
| --- | --- |
| `all_tests.py` | Full local CI run: check, test, fuzz, docs, bundle, examples |
| `test_zone_database.py` | Offline committed-data integrity, all-name native imports and provider error checks |
| `generate_zone_database.py` | Generate a pinned bounded companion package and verify imports through the core adapter |
| `measure_gregorian.py` | Measure validated date construction and coordinate round trips with checked checksums |
| `measure_zone_roc.py` | Generate prototype zone encodings and measure source/archive, compiler and native binary costs |
| `measure_zone_data.py` | Reproduce pinned zone archive/data size measurements, separately from compiler/runtime costs |
| `measure_zone_package.py` | Measure real provider builds, binary sizes and observable static/dynamic lookup allocations |
| `fixture_platform.py` | Build the instrumented test host and verify resource assertions/trace effects |
| `benchmark_chrono.py` | Compare selected date/timestamp operations with pinned Rust Chrono |
| `oracles.py` | Deterministic external/reference-model comparisons through public APIs |
| `fuzz.py` | Pinned target builds, bounded searches, curated replay and failure lifecycle |
| `test_compile_failures.py` | Domain separation and opaque representation checks |
| `bundle.py` | Bundle `package/` into a distributable `.tar.zst` |
| `docs.py` | Generate API docs and the user landing guide into `www/<version>` |
| `test_doc_examples.py` | Compile and run Roc code blocks from public module documentation |
| `test_bundle_examples.py` | Verify the examples against a bundled package served over localhost |
| `update_example_urls.py` | Point the examples at a released bundle URL |

Python tooling orchestrates compiler subprocesses and localhost serving for
bundle verification.

## API documentation

API usage examples belong in module `##` comments, in fenced `roc` code blocks.
Use complete imports through the `time` dependency and executable `expect`
examples. `scripts/test_doc_examples.py` checks them together against the real
package and runs in the default gate. The docs publisher adds
`docs/overview.html` as the landing guide because the compiler-generated package
index currently contains navigation and a logo only. Review generated API pages
with `ROC=/path/to/pinned/roc python3 scripts/docs.py 0.1.0 --docs-root .roc-time-tmp/docs-review`.

## Tests

The gate also runs `tests/static_dispatch/main.roc` under both the interpreter
and native execution to check public operator, dictionary-key and iterator use.

Run the full CI check locally with `ROC=/path/to/pinned/roc python3 scripts/all_tests.py`.
Generate local versioned docs with `python3 scripts/docs.py 0.1.0`.

The Roc compiler version used by CI is pinned in `.roc-version`.

Property-based testing with [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz)
is a core development method for temporal semantics, alongside fixed fixtures,
compile-failure tests, and executable examples. It exercises semantic laws and
independent reference models, with discovered failures preserved as regressions.
See the [contributor method](AGENTS.md#property-based-testing).

At least one oracle is required for temporal implementation work. Run:

```sh
ROC=/path/to/pinned/roc python3 scripts/oracles.py --workers 4
```

The default gate includes 4,096 Gregorian, 4,096 Julian, 2,592 zone, 448 calendar-pattern and 512 RFC date-rule
observations stored as JSONL under `tests/oracles/`. Each native fixture is
compiled once. Python validates the corpus, passes only inputs as arguments to
bounded parallel processes, and compares exact observations in corpus order.
Use `--oracle gregorian`, `julian`, `zones`, `calendar_pattern`, `rfc_date` or `rfc_timed` to select one corpus. Full-corpus expected
results stay in the Python harness. Small typed scenarios retain
interpreter coverage and comparator regression checks.

Corpora are hash-checked and schema-validated. Missing, duplicate or reordered
identities, wrong values, malformed output, failed processes and missing host
metrics fail replay. Each process has a five-second timeout and a 16 KiB output
budget; compilation stages allow 120 seconds and 1 MiB. Up to 16 workers are
supported, with four by default. Failure inputs/output and deterministic result
records are saved under `.roc-time-tmp/oracles/`. Per-case records include host
allocation traffic, which includes argument decoding and result formatting;
use explicit in-fixture counter snapshots to isolate an algorithm.

Calendar-pattern cases compare complete later periods with pinned dateutil
2.9.0.post0. Week-number selectors use an independent calendar-row model:
enumerate seven-day rows, assign each to its majority year, then select positive
or negative row positions. The corpus retains nine adjacent-year disagreements
with dateutil under `calendar_pattern-reference-gaps.jsonl`; those outputs are
evidence to review, not expectations copied from roc-time. The negative-week
case also corresponds to a TODO in dateutil's next-year week handling. Other
differences expose its previous-year week-count calculation. Fixed Roc tests
retain readable examples of both cases.

Refresh with `python3 scripts/generate_pattern_oracle.py /path/to/wheel-directory`
using the exact dateutil and six wheel names/hashes in the generator and
`calendar_pattern-manifest.toml`. Wheels remain under `.roc-time-tmp/`; normal
replay needs neither the reference dependencies nor network access. This corpus
does not yet establish timed recurrence, COUNT, BYSETPOS, exclusion or cursor
semantics. Do not infer those from a passing calendar-candidate check.

The RFC date-rule corpus uses dateutil's text parser and recurrence-set evaluator
for 16 date-only templates, with COUNT/UNTIL, signed selectors, inclusions,
exclusions and query windows. Replay drives the public parser and native cursor
with 17 work steps and one output slot per batch. Regenerate with
`python3 scripts/generate_rfc_date_oracle.py /path/to/wheel-directory` using the
same pinned dateutil/six wheels. The manifest records its semantic intersection;
it excludes timed rules, week-number selectors and disputed omitted yearly
fields. Replay also lifts every case to UTC midnight through `RfcTimedRule`,
checking the same independently generated dates and one-day occurrence widths.
That extension tests the shared date/timed semantic intersection, not subdaily
selectors, zone transitions or general timed conformance. Fixed parser tests
cover malformed inputs and profile boundaries.

The timed corpus independently exercises twelve UTC templates with second,
minute, hour, day and month frequencies, clock selectors, signed BYSETPOS,
COUNT, inclusive UNTIL, duplicate additions/exclusions and later query windows.
It compares integer POSIX microseconds with dateutil results and checks one-second
appointment widths, consuming one output per batch with 17 source-work steps.
Regenerate with CPython 3.12.3 and
`python3 scripts/generate_rfc_timed_oracle.py /path/to/wheel-directory`;
wheel hashes, generator hash and seed are pinned in its manifest. This corpus
excludes local-zone transitions, leap seconds and PERIOD overrides. Those require
separate sourced fixtures and models; UTC agreement does not establish them.

Valid forward Gregorian cases in years 0001–9999 also exercise `RfcDateTime`
parsing and explicit UTC midnight conversion against the same expected day.
This covers calendar-date interpretation, not named zones or leap seconds.

Gregorian expectations come from CPython 3.14.3 `datetime` for years 1–9999 and
a 400-year table model outside that range. The model extension is not direct
Python support. The forward formula shares our year-counting approach, so
sequential tests and sourced conventions remain necessary alongside agreement.

Fixture provenance and hashes live in `tests/oracles/gregorian-manifest.toml` and
`tests/oracles/julian-manifest.toml`. Julian fixtures are generated from
Howard Hinnant’s attributed public-domain March-based formulas, independent of
production January counting; the 1582 equal-day fixture anchors the epochs.
To deliberately refresh expectations, use CPython 3.14.3 and run
`python3 scripts/oracles.py --refresh`, then review the JSONL and manifest diff.
Generation checks the table model against all 3,652,059 dates in Python's domain.
Never regenerate expected values from roc-time output or bless a mismatch.

Zone provenance is in `tests/oracles/zones-manifest.toml`. The pinned tzdata
2025.2 wheel contains IANA 2025b data; its URL and SHA-256 are recorded there.
The generator uses `ZoneInfo.from_file`, never the host database, and writes
`tests/oracles/zones.jsonl` plus small typed smoke/rule fixtures in
`tests/oracle_zones/Cases.roc`. To refresh with CPython 3.14.3, download that exact
wheel under `.roc-time-tmp/` and run:

```bash
python3 scripts/generate_zone_oracle.py .roc-time-tmp/tzdata-2025.2.whl
```

The three ten-day fixtures cover Lord Howe's 2024 half-hour fold/gap and Apia's
2011 skipped day. Generation validates exported offsets at every second of each
window. Expected local occurrences use both Python fold values and UTC-to-local
round-trip validation; a fold flag alone does not prove that a label exists.
The corpus covers 15-minute labels at three microsecond positions on three days
around each transition. This is selected-window evidence, not full tzdb support.
Python's two-fold model does not validate arbitrary multi-fold behavior; synthetic
Roc tests provide separate triple-fold evidence. Retain the copied tzdata license
notices when refreshing. Normal replay requires neither Python tzdata nor a
network service.


Test applications live under `tests/<name>/main.roc`, with pure test logic in
neighboring type modules. The precision, span, coverage, Gregorian, arithmetic, calendar-interoperability, clock, offset, zone, event, calendar-pattern, recurrence and description roots
use the content-addressed [roc-fuzz 0.3.0 release](https://github.com/lukewilliamboswell/roc-fuzz/releases/tag/0.3.0)
URL directly; corpus and dependency metadata live under `tests/fuzz/`.
`scripts/fuzz.py` is their single runner. Set `ROC` to the compiler pinned in `.roc-version`:

```sh
python3 scripts/fuzz.py --operation all
python3 scripts/fuzz.py --operation build --targets precision
python3 scripts/fuzz.py --operation run --targets precision --runs 10000 --seconds 5 --seed 1
python3 scripts/fuzz.py --operation replay --targets precision
.roc-time-tmp/fuzz/precision show tests/fuzz/corpus/precision/alternating
python3 scripts/fuzz.py --operation lifecycle
```

The full test command includes curated replay, 10,000-run/5-second searches for
each semantic target, and the deliberately failing harness lifecycle. Searches
also bound raw inputs to 256 bytes, RSS to 256 MB, and each target call to two
seconds. Builds, corpora, failure artifacts, and logs stay under `.roc-time-tmp/`
by default; `ROC_TIME_TMPDIR` selects a different disposable working directory.
Apple Silicon macOS and Linux x86-64/musl have verified native fuzz execution.
Other hosts explicitly report fuzzing as unverified.
See [target domains and corpus provenance](tests/fuzz/README.md).

For a saved failure, run these commands from a directory under `.roc-time-tmp/`
so the runner's own `.roc-fuzz/` artifacts remain disposable. `TARGET` and
`INPUT` below denote the absolute executable and raw-input paths printed by the
failed campaign:

```sh
TARGET show INPUT
TARGET replay INPUT
TARGET minimize INPUT minimized
TARGET replay minimized
```

`--operation lifecycle` exercises these commands automatically, checks failing
exit status and artifact creation, minimizes to one byte, then verifies the
fixed harness against the saved regression.

## Generic codecs and literals

Generic text codecs and quoted literals are checked by
`tests/codecs/main.roc`, through the built-in JSON codec and a small independent
encoding that verifies unconsumed input and format failures. The full gate runs
this application with the interpreter and dev/speed builds. Text-format types
delegate custom `parser_for`, `encoder_for` and `from_quote` methods to validated
parsing and canonical serialization; deriving these methods from opaque backing
records would bypass the semantic representation. Runtime interpolations use
an explicit fallible `parse` call. Invalid typed literals belong in the normal
compile-failure gate and must fail for the intended validation diagnostic.

The pinned compiler's encoding hook uses `encoding.parse_str(encoding, state)`
and `encoding.encode_str(text, state)`. Keep the executable codec checks when
upgrading the compiler: documentation on the compiler's moving main branch may
describe a different hook signature. Codec tests establish interchange strings,
not a versioned native persistence format.

## Instrumented fixture platform

Install Zig 0.16.0 (`ZIG` can select its executable) alongside the pinned Roc
compiler. The default gate builds the host and verifies its controls:

```sh
ROC=/path/to/pinned/roc python3 scripts/fixture_platform.py --verify
```

The [resource probe](tests/platform_probe/main.roc) uses the copied roc-pdf host
foundation with allocation counters, numeric trace marks and hosted assertions.
`Host.allocation_count!` counts allocation and reallocation calls;
`allocated_bytes!` counts full requested sizes, including reallocations;
`deallocation_count!` counts deallocation calls. Counters reset after host argv
construction. Totals include result construction and may include argv disposal,
but are reported before returned values are freed. They are neither live-byte
measurements nor a balanced allocation/free ledger.

Take snapshots before and after an operation to assert its allocation cost.
Counter queries and `Host.mark!` make no Roc allocations. Marks emit
`ROC_TRACE protocol=1` records with a numeric ID and allocation count; the exported
host symbol and preserved debug information provide a starting point for sampling
profilers or breakpoints. Profiling sessions still need an explicit workload and
measurement method; marker I/O is not free.

Dev builds exercise `expect` failures. The pinned optimized backend removes
`expect`, so resource assertions needed in optimized runs use `Host.assert!`.
The host makes both supported assertion failures return nonzero; negative
controls test that behavior. Keep tested operations observable using runtime
inputs and consumed outputs. Separate input construction, algorithm and output
formatting when measuring. Resource evidence is specific to compiler, backend,
input size and ownership; do not generalize one passing probe to all operations.

The same command runs [recurrence prefix resource checks](tests/recurrence_resource/main.roc)
in dev and speed builds. Runtime horizons ending in years 2001 and 2,000,000,000
must produce the same first occurrence and identical requested-byte traffic.
Iterator construction, one-batch consumption and an early-stopping scalar fold
each have a 4096-byte traffic ceiling; resumption must yield the second date.
A query starting near the end of each horizon must return `Limited(WorkLimit)`
under a one-step search budget. Fully consuming a zero-work iterator must yield
exactly one incomplete outcome and terminate. Both operations have separately
measured traffic ceilings, including when there is no nearby visible occurrence.
The probe also resolves the first all-day occurrence through the composed date
and zone cursors, with a separate traffic ceiling and the same vast date horizon.
Boundary classification is measured separately on 16- and 8192-transition
synthetic tables. Table construction is outside that scope; one segment of
classification must remain incomplete and have identical allocation traffic.
After full classification outside the measured choice scope, selecting an
asserted offset from the resulting 17- or 8193-occurrence fold must allocate
nothing. The synthetic offsets deliberately repeat one local clock range.
Clock-pattern traversal separately consumes one candidate from all 86400
hour/minute/second combinations after selector construction; its byte ceiling
catches eager materialization of the clock candidates. The timed cursor then
combines that full clock grid with the vast daily series and resolves just its
first occurrence under explicit candidate, buffer and zone budgets. Rule
construction remains outside this consumption measurement. Its outcome iterator
also consumes a single prefix and a complete zero-work stream: a limited
result must stop iteration rather than retry forever. The standard ceiling is
4 KiB of requested allocation traffic per stage, except 8 KiB for the timed
iterator prefix, 12 KiB for the composed schedule iterator prefix and 8 KiB
for its terminal zero-work result. These accommodate measured traffic on the
pinned compiler. Schedule checks also pause between start and calendar-end
interpretation, then resume with zero source work under the shared zone budget.
A secondly recurrence over the same horizons separately verifies that seeking
and consuming one clock period stays within the base budget. A POSIX cutoff at
I64.highest separately measures cursor construction (including its conservative
local source bound) and first consumption, each under the base budget. Source-exclusion
lookup is checked with 16 and 4096 normalized labels. Inclusion merging also
compares 16 and 4096 explicit starts, interpreting one pre-anchor inclusion
beside a retained rule start under the same budgets. Duration-override lookup
also compares 16 and 4096 entries and verifies the selected span, with
construction outside the measured prefix scope. Fixed-duration construction must use no zone
segments; calendar-duration end resolution must pause after one segment in
both short and long transition tables, with start resolution outside its scope.
The calendar end lies in every fold segment, so one inspected segment cannot
establish a complete result. An explicit local end repeats this bounded prefix
check against both table sizes. A resolved explicit end separately consumes zero
zone work, including an endpoint at the greatest I64 boundary. Each has its own
4 KiB requested-byte ceiling; short/long-table traffic must match.
A calendar-year selection additionally measures cursor construction and first
segment consumption against 16 and 4096 transitions. The year contains trillions
of local microseconds; a one-segment budget must return an incomplete result.
Each phase uses the same 4 KiB traffic ceiling, with identical short/long-table
traffic required. Input rule storage is outside these measured phases. Finite-evidence queries
separately measure construction, first alternative and resumption against 16
and 4096 candidate years. Opposing witnesses must establish Possible after two
alternatives, preserving the original shared query. Model normalization and
storage are outside those prefix measurements; each phase has a 4 KiB traffic
ceiling and must match across sizes.
These are explicit traffic budgets, not claims of live memory or zero-cost
iteration. Short/vast traffic must still match exactly.
A five-second process deadline catches catastrophic hidden traversal, and a
zero-byte ceiling must fail through the hosted assertion. These are regression
bounds for this shared-cursor workload, not exact allocation or retained-memory
contracts. Review ceiling changes against measured operations and ownership;
do not raise them merely to make a regression pass.

Interchange resource evidence lives in `tests/interchange_resource/main.roc`.
The normal fixture gate measures parsing, serialization, interpretation, stored
snapshot reads and inspection separately for 1/32 annotations and 2/16,384
retained transitions. It checks semantic output and 100,000 stored reads with
zero allocation traffic under a five-second subprocess limit, plus dev/speed
failing allocation controls. Rules and runtime input are built outside those
scopes. Counts are cumulative requested bytes, not live or retained memory;
initial interpretation remains linear in the supplied transition table.

Native persistence resource checks in `tests/persistence_resource/main.roc`
separate checked construction, encoding and decoding for 1/32/1,024 canonical
coverage members. Small and full-range signed coordinates distinguish member
work from coordinate distance. A 1,025-member value must fail construction before
allocation; rejecting its JSON still includes envelope decoding costs. The gate
runs dev/speed builds with finite subprocess limits and a dedicated failing
allocation ceiling. These counters measure requested allocation traffic, not
live or retained bytes.

`tests/calendar_persistence_resource/main.roc` separates native calendar and
qualified-description encoding/decoding for zero/eight qualifiers and all six
fractional resolutions. The final unit of the last supported Julian day must
remain persistable although its exclusive upper boundary is out of range.
Input-byte and qualifier-count limits are checked with structured errors. The
normal fixture gate runs dev/speed builds and a dedicated failing allocation
ceiling; decoding error costs include the outer JSON envelope.

`tests/explanation_resource/main.roc` compares bounded rendering against small
and large retained rule tables and metadata strings. It checks zero-budget
behavior, UTF-8 previews, rendering completeness and 100,000 paired snapshot fact
reads with no requested allocations. The dev/speed gate uses a five-second
subprocess limit and failing allocation controls. Fact budgets count indexed
facts; the preferred-calendar fact may inspect the adapter's bounded annotation
list, but must never traverse zone transitions or resolve again. Metadata is
previewed before formatting, so a large version string cannot force a full copy.
Exact-interval fact checks must use the cached extent and retain both original
endpoint declarations; inspecting or explaining them must not repeat boundary
conversion. RFC primitive checks distinguish local/UTC forms and calendar days
from coordinate seconds without interpreting a duration or expanding a series.
Use `examples/explain_event_terms/main.roc` for the caller flow and the interchange
fuzz target for generated semantic facts. Resource claims remain separate from
these functional checks. `tests/declaration_explanation_resource/main.roc`
checks fact reads, inspection and zero/tiny/full rendering budgets in dev and
speed builds, including maximum-I64 calendar-day declarations and allocation
ceiling negative controls. Its counters measure requested allocation bytes,
not retained memory.

Snapshot persistence has a separate fixture at
`tests/snapshot_persistence_resource/main.roc`. It measures checked construction,
encoding, load validation and repeated stored reads separately, with 0, 2 and
1024 transitions across full-I64 validity. Larger tables and oversized metadata must fail before encoding;
allocation ceiling controls run in dev and speed builds. Functional interchange
properties distinguish contexts with identical labels and current results but
different microsecond transitions. These are requested-allocation observations,
not retained-memory measurements or authenticated database provenance.

Civil persistence uses `tests/civil_persistence_resource/main.roc`: repeated
one-microsecond selections produce many disconnected members under a finite
synthetic fold table with full-I64 validity. Construction, encoding, loading
and stored reads are measured separately. A retained partial cursor is resumed
under a separate allocation ceiling, then checked unchanged through its original
branch. Transition/member overflows must fail before encoding; both dev and speed
builds include failing allocation controls.
The interchange generator independently checks fold policies and empty gap
coverage. Neither canonical text agreement nor allocation traffic establishes
retained memory or correctness without the corresponding semantic fixtures.

Selection explanation evidence in `tests/selection_explanation_resource/main.roc`
separates stored fact reads from bounded rendering for coverage, civil boundaries,
complete selections and limited batches. Vary member counts, metadata lengths
and owned/shared/sliced coverage. Zero-budget rendering and indexed fact reads
have allocation assertions; fixed-budget rendering includes visible metadata
clipping and failing ceiling controls in dev and speed builds. A fully rendered
limited batch must still report incomplete evaluation. These counters measure
allocation traffic, not retained memory.

Recurrence declaration explanations use
`tests/recurrence_explanation_resource/main.roc`. Construction and indexed reads
are measured separately from zero/tiny/fixed-budget rendering, with large selector
and explicit-date lists, shared input storage, and unbounded or large-count rules.
No query window or provider is needed. Dev/speed builds include failing allocation
controls. Generated recurrence properties compare declaration facts against
independently modeled inputs and distinguish rule COUNT from post-exclusion output.

Finite resolved-interval evidence has a separate resource fixture at
`tests/interval_resource/main.roc`. It varies 64, 512 and 4096 choices for paired
intervals and independent endpoints, with owned, shared and retained sliced
inputs. Independent 4096-by-4096 endpoints admit 16,777,216 valid pairs; the
constructor must stay within `1024 * n + 8192` requested bytes and a five-second
process bound, without pair materialization. A 64-fold input increase may grow
construction traffic by at most 128-fold. Input generation is outside those
scopes. Point-query scopes must request zero bytes and preserve gap, definite,
possible and impossible observations. Always-active zero-ceiling controls must
fail in both dev and speed builds. These are allocation-traffic and execution
bounds, not live/retained-memory or exact-layout claims.

The host is test-only and adds no package dependency. Apple Silicon macOS and
Linux x86-64/musl native execution are verified, including dev/speed resource
assertions and failing controls. Linux uses pinned linker inputs; other targets
remain unsupported by this fixture host. Provenance and licenses
are in [tests/platform/NOTICE](tests/platform/NOTICE).

## Comparative benchmarks

The [Chrono benchmark guide](benchmarks/chrono/README.md) defines the shared input
profile, independent output checks, compiler/allocator choices and sampling method.
Run these opt-in benchmarks without concurrent builds or tests. They compare
selected date and timestamp operations, not overall library capability; their
in-process timing excludes setup. Keep raw results under `.roc-time-tmp/`.

## Packaging

Bundle the package for distribution using `python3 scripts/bundle.py --output-dir dist`.

Run the release workflow from GitHub Actions with a release version such as `0.1.0`.
It builds and tests the bundle, creates the GitHub release, generates versioned docs,
commits the generated `www/` update, and publishes the docs to GitHub Pages.

## Zone-data representation measurements

With the pinned Roc compiler and CPython 3.14.3, run:

```sh
ROC=/path/to/pinned/roc python3 scripts/measure_zone_roc.py .roc-time-tmp/tzdata-2025.2.whl --samples 3
```

Use the same pinned wheel as the zone oracle generator. The script verifies its
hash, generates disposable Roc modules, and compares core-only, static one-zone,
dynamic global-name and four-zone subset applications. It writes generated
sources, command output and a JSON report under `.roc-time-tmp/`. Every measured
zone application consumes its data and checks its output against the source
values, so merely linking an unused import is not the workload.

Builds disable Roc's cache; operating-system caches may be warm. macOS compiler
peak RSS comes from `/usr/bin/time -l` and requires access to system statistics.
Other hosts report no compiler memory measurement. This prototype retains
transition times, type indices, offsets and future-rule text, but omits DST flags
and abbreviations. Repeat with `--encoding tzif` to measure original TZif bytes
embedded as `List(U8)` instead. That mode consumes all bytes without parsing
them; it includes fields omitted by the column mode. Neither mode expands future
rules or constructs validated zone providers. Its sizes are not a complete database implementation's costs. Runtime
allocations, retained data, URL acquisition and Wasm require separate evidence.
Do not copy measurement transcripts into the architecture or active plan.

Generate the optional bounded database into a new directory with:

```sh
python3 scripts/generate_zone_database.py .roc-time-tmp/tzdata-2025.2.whl .roc-time-tmp/generated-zone-package --verify-roc /path/to/pinned/roc
```

Generation requires CPython 3.14.3 and verifies the wheel hash. It exports
1800-01-01 through 2200-01-01 exclusively, with future footer transitions
expanded ahead of time and original alias/canonical identities from `tzdata.zi`.
The output is a separate Roc package with `Database.get(name)` returning the
structural record accepted by `ZoneRules.from_database`; core has no dependency
on it. Unknown names fail at lookup and the imported rules enforce their horizon.
The generated pack exposes offsets, not abbreviations or DST-status labels.

The generator compares transition endpoints, interval midpoints and monthly
probes with C `ZoneInfo` loaded from the pinned bytes. Python footer expansion
and C interpretation are different code paths sharing source data; this does
not establish independent historical truth. `--verify-roc` checks and builds a
native caller that imports every name through the real package adapter, checks
transition counts and position-weighted checksums, and queries both sides of
every transition. The generator emits two compact text assets and copies
`tzdb/Database.roc` into the package. Top-level values decode the assets at
compile time; runtime lookup does not parse them. Maintain that source module,
then regenerate the pack. `text-assets-v1` is a private generator/decoder
contract, separate from the public structural interchange schema. Output
includes source integrity metadata and applicable notices. This generator does
not publish a release; provider integration tests and bundled application
examples remain necessary before distribution.

The default test gate replays the committed `tzdb/package/` without the wheel or
CPython generation pin. Refresh into a new ignored directory, review semantic
changes, then replace the committed generated pack and its manifest together.
The resource fixture uses runtime names and consumes transition checksums. It
limits lookup to zero allocation/reallocation calls in development and at most
one in optimized native builds under the pinned compiler. This covers the data lookup and
returned record, not core adaptation, parsing/formatting or retained memory.
Trace marks bracket the operation. The host assertion remains active when
optimized `expect` checks are removed. Bundled examples import the text assets
through the downloaded package in interpreter and native execution.
Bundle the companion separately:

```sh
python3 scripts/bundle.py --package-dir tzdb/package --output-dir .roc-time-tmp/zone-bundle
```

Measure the actual package with
`ROC=/path/to/pinned/roc python3 scripts/measure_zone_package.py --package tzdb/package`.
Repeat `--package` to compare a historical pack checked out under `.roc-time-tmp/`.
Reports retain commands, hashes, compiler/target, build samples and observable
lookup results. Source encoding, compile-time evaluation and linked data retention
are separate costs; a static name alone does not prove unused-zone elimination.

Use `update_example_urls.py --zone-bundle-url` alongside `--bundle-url` when
updating both independently versioned dependencies. Example
bundle checks rewrite both core and optional-data dependencies to local URLs.

Run `ROC=/path/to/pinned/roc python3 scripts/measure_gregorian.py` for the
Gregorian conversion microbenchmark (LLVM speed, one million dates, three
warmups and fifteen samples). Run it without concurrent test or build jobs.
The fields and roundtrip workloads include process startup and final formatting;
raw timings and machine/compiler metadata stay under `.roc-time-tmp/`. This is
not an allocation measurement or a general library ranking.
