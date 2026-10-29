# Contributing to roc-time

Start with a small application scenario: what input does the caller have, and
what result should they get? Include that scenario in your issue or pull request,
along with the relevant requirements from [design.md](design.md). This helps
reviewers distinguish a useful convenience from a change in temporal meaning.

Before implementing, read [AGENTS.md](AGENTS.md) for the contribution method and
any relevant task under `planning/`. The design describes the lasting contracts;
the plans describe unfinished work. For a documentation change, start with the
reader's task and check every command or example you change.

## Set up your checkout

The package follows the latest Roc nightly. Automation runs on a separate pinned
compiler so the checks can still run when a new nightly breaks package code.

| Command | Selected by | Used for |
| --- | --- | --- |
| `roc-stable` | The nightly release named in [Blueprint.roc](Blueprint.roc), pinned by `Blueprint.lock` | Running the automation scripts in `scripts/*.roc` |
| `roc` | Your installed latest [nightly](https://github.com/roc-lang/nightlies/releases) | Checking, testing, bundling and running the packages and examples |

There is no `roc` header field or `.roc-version`. Check `roc version` when
reporting a result, and keep `roc-stable` for automation rather than testing the
package with it.

Install the [blueprint](https://github.com/lukewilliamboswell/roc-blueprint)
0.8.0 CLI, Nix, and a current nightly `roc`. Blueprint fetches the fixed
compiler and shared utilities and realizes Zig 0.17.0, CPython 3.14.3, Rust
1.95.0 (including its musl target), and PDF readers from reviewed Nix inputs.
The host supplies Git, the GitHub CLI, curl, archive tools and standard file
utilities declared by `Expect`. With those installed:

```sh
roc version
blueprint run check
```

This is the same complete gate CI runs: package checks, examples, semantic tests,
resource checks and documentation. The shared release workflow separately
tests the exact publication artifacts. For an interactive shell
with the automation dependencies, run `blueprint shell`.

Scripts take the package compiler from `ROC_NIGHTLY`, falling back to `roc` on
`PATH`. The environment provides the fixed tooling compiler and native toolchains.
`blueprint run native-versions` verifies their selected versions. For example,
`ROC_NIGHTLY=/path/to/roc blueprint run check` selects a particular package
compiler. Commit `Blueprint.roc` and `Blueprint.lock`; only `blueprint update`
writes the lock. Keep experiments and generated artifacts under ignored
`.roc-time-tmp/`.

## Make and check a change

For package code, begin with `roc check package/main.roc`,
`roc test package/main.roc` and the application affected by your change. Before
handoff, run `blueprint run check`. A failing setup step is still unverified;
include its actual error rather than treating later unchecked stages as passed.

Examples are focused applications, not test fixtures. Each belongs in its own
folder with a `main.roc` entrypoint and pure logic in a separate type module.
Keep unit `expect` tests beside their implementation. Run them once with
`roc test package/main.roc`; the CLI discovers the package's module graph.
Do not add separate `*Tests.roc` unit modules or a per-module test loop.
Put integration fixtures and harnesses under `tests/` using the same root layout.
Examples depend on `../../package/main.roc` and, where they use zone data,
`../../tzdb/package/main.roc`, so they always exercise the working tree. Every
folder under `examples/` is an application with a case in `tests/spec.json`;
record a new or changed application's output with
`blueprint run release-package -- test-examples --update`, the utility the release workflow
runs, built from roc-automation's `scripts/release_package.roc` with the `roc`
on `PATH`.

## Scripts

New automation is written as Roc scripts. Each entry point in `scripts/*.roc`
starts with `#!/usr/bin/env roc-stable`, is committed executable, names basic-cli
by release URL and carries no `roc` field. Pure logic lives in `scripts/src/`
modules with `expect` tests, which the gate runs on `roc-stable`. Scripts never
depend on this repository's packages.

| Script | Purpose |
| --- | --- |
| `check_all.roc` | Complete contributor gate; `check-source` runs the package and tooling subset |
| `check_integration.roc` | Integration case driver with progress, timings and failure summaries |
| `restore_api_docs.roc` | Restore immutable ZIP and legacy tarball API archives, validating identity and paths |
| `check_api_docs.roc` | Audit documented API entries and nested-method search, including failure controls |
| `prepare_site.roc` | Select the published release or build an explicit development preview |
| `build_docs.roc` | Verify the released renderer and build/check the native HTML and PDF manual |
| `assemble_site.roc` | Render the tagged release manual and assemble restored immutable API versions |

The Roc integration driver still calls legacy Python oracle, fixture and
measurement drivers while those are migrated. Independent reference generators
and Python benchmark subjects remain pinned evidence inputs. Every product
command receives the selected package compiler explicitly.

`release.yml` calls the shared release workflow of
[roc-automation](https://github.com/lukewilliamboswell/roc-automation) at a full
commit SHA. CI runs `blueprint run check`; the shared workflow builds, tests and publishes the
release with roc-automation's `release-package` utility; this repository keeps no
bundling, archiving or publishing script. `nightly.yml` calls the shared
compatibility workflow the same way. Author release notes in
`docs/releases/<version>.adoc` before dispatching a release and include them from
`docs/releases.adoc`; `{package-url}` and `{tzdb-url}` stand for the two bundle URLs.
A pull request's dry run renders the newest notes file.

| Script | Purpose |
| --- | --- |
| `test_zone_database.py` | Offline committed-data integrity, all-name native imports and provider error checks |
| `generate_zone_database.py` | Generate a pinned bounded companion package and verify imports through the core adapter |
| `measure_gregorian.roc` | Measure validated date construction and coordinate round trips with checked checksums |
| `measure_zone_roc.roc` | Generate prototype zone encodings and measure source/archive, compiler and native binary costs |
| `reference_zone_payloads.py` | Retained pinned CPython TZif decoder; emits independent reference columns for the prototype |
| `measure_zone_data.roc` | Reproduce pinned zone archive/data size measurements, separately from compiler/runtime costs |
| `measure_zone_package.roc` | Measure real provider builds, binary sizes and observable static/dynamic lookup allocations |
| `check_fixture_platform.roc` | Verify instrumented host resource assertions, trace effects and failing controls |
| `benchmark_chrono.py` | Compare selected date/timestamp operations with pinned Rust Chrono |
| `benchmark_comparison.py` | Opt-in comparison with Chrono, Jiff, Go time, Python datetime/ciso8601 and Tempo |
| `oracles.py` | Deterministic external/reference-model comparisons through public APIs |
| `fuzz.roc` | Pinned target builds, bounded searches, curated replay and failure lifecycle |
| `check_compile_failures.roc` | Domain separation and opaque representation checks |
| `build_docs.roc` | Generate API docs into an ignored build directory |
| `check_doc_examples.roc` | Compile and run Roc code blocks from public module documentation |

## API documentation

There are two outputs to review: the authored user manual and the generated
module reference. The manual explains workflows; module comments document exact
operations and executable API examples.

The user manual is authored in `docs/index.adoc` and top-level AsciiDoc chapters.
Keep existing chapter filenames and explicit ASCII IDs stable. Use
`xref:chapter.adoc#id[descriptive text]` for links between chapters, and include
every chapter in `index.adoc` so it reaches the combined PDF. Use simple PSV
tables with explicit columns and named source blocks. Raw HTML, arbitrary
AsciiDoc extensions and direct Roc-source includes are outside the renderer's
supported profile. See the
[shared authoring contract](https://lukewilliamboswell.github.io/roc-automation/documentation.html#experimental-native-docs-contract).

```sh
DOCS_OUTPUT=.roc-time-tmp/manual-preview blueprint run check-docs
```

Use a new output directory. This builds both the HTML site and `roc-time.pdf`
with roc-automation's released `tools-0.6.0` renderer. Blueprint fetches each
executable and verifies it against `Blueprint.lock`; update its recipe and
review all per-system lock digests together. Rendering uses the shared theme
and needs no compiler; Roc scripts run its preparation and assembly,
and the Blueprint environment provides Poppler for independent PDF checks.

The gate checks every local HTML link/fragment, legacy chapter route, chapter
destination in the PDF, and exact visible source-block bytes. PDF extraction
checks chapter and command text. Review desktop/mobile navigation, scrolling
tables, and PDF layout when changing content. Tables scroll horizontally on
narrow screens. These checks do not claim PDF/UA conformance.

For a complete preview with immutable historical API references:

```sh
blueprint run restore-api-docs -- --output .roc-time-tmp/api-history
blueprint run site -- --api-root .roc-time-tmp/api-history --output .roc-time-tmp/site-preview
```

With `RELEASE_VERSION` set, site assembly renders that immutable tag's authored
manual using the shared renderer; fetch the tag before a local release preview.
Without it, the manual is labelled unreleased. `site-release` selects the latest
final release and `site-preview` checks the current manual. Both write a new
`.roc-time-tmp/pages-site`; use a clean worktree or move the previous output.
API trees are restored separately, preserving `/<version>/` URLs byte for byte.

API usage examples belong in module `##` comments, in fenced `roc` code blocks.
Use complete imports through the `time` dependency and executable `expect`
examples. `scripts/check_doc_examples.roc` checks them together against the real
package and runs in the default gate. The shared release utility archives the compiler's original output without
injecting HTML. Generate a local reference with
`roc docs package/main.roc --output=.roc-time-tmp/api-main`.

## Tests

For a first contribution, you can run the package check, unit tests and one
affected example while working. The complete gate below adds independent
semantic comparisons, generated inputs, compile-failure checks and resource
fixtures. Pick the focused commands relevant to your change; keep the full gate
for integration.

Run the gate with `blueprint run check`; set `ROC_NIGHTLY` to use a package
compiler other than `roc` on `PATH`. `blueprint run release-package -- test-examples` alone runs
every example in place against the working tree. Generate local development API docs
with `roc docs package/main.roc --output=.roc-time-tmp/api-main`. The gate also runs
`tests/static_dispatch/main.roc` in the interpreter and natively to check public
operators, dictionary keys and iterators.

A new nightly can fail the gate with no fault in the change under review. Compare
with the default branch and the latest nightly compatibility run before treating
a failure as a regression.

Property-based testing with [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz)
is a core development method for temporal semantics, alongside fixed fixtures,
compile-failure tests, and executable examples. It exercises semantic laws and
independent reference models, with discovered failures preserved as regressions.
See the [contributor method](AGENTS.md#property-based-testing).

At least one oracle is required for temporal implementation work. Run:

```sh
ROC=/path/to/roc python3 scripts/oracles.py --workers 4
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
fields. Replay also lifts every case to UTC midnight through `ICalTimedRule`,
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

Valid forward Gregorian cases in years 0001–9999 also exercise `ICalDateTime`
parsing and explicit UTC midnight conversion against the same expected day.
This covers calendar-date interpretation, not named zones or leap seconds.

Gregorian expectations come from CPython 3.14.3 `datetime` for years 1–9999 and
a 400-year table model outside that range. The model extension is not direct
Python support. The forward formula shares our year-counting approach, so
sequential tests and sourced conventions remain necessary alongside agreement.

Civil query evidence runs with `ROC=/path/to/roc python3 scripts/test_civil_queries.py`.
It replays pinned [CPython fixtures and labelled cycle extensions](tests/civil_query_checks/provenance.md)
and independently walks all 146097 days of a Gregorian cycle in native dev/speed
builds. The Gregorian fuzz target supplements this with generated full-range
queries and successor laws. `blueprint run fixture-platform` measures input
construction separately from query allocations over owned, shared and sliced
dates; these are requested-byte counters, not retained-memory measurements.

DATE recurrence export evidence runs with
`ROC=/path/to/roc python3 scripts/test_date_export.py`. Its
[sourced/profile fixtures](tests/date_export_checks/PROVENANCE.md) distinguish
RFC occurrence facts from our canonical spelling and native-profile limits.
The recurrence fuzz target checks exported properties and restored cursors
against an independent finite calendar model. The hosted DATE export resource
gate separates input storage, native construction, definition access, export,
cursor construction and first/resumed consumption. It varies selector sizes,
ownership and finite query horizons over an unbounded rule; allocation failure
controls run in both dev and speed builds. Normal replay never regenerates
expected output from the package under test.

Timed recurrence export evidence runs with
`ROC=/path/to/roc python3 scripts/test_timed_export.py`. Its
[independent fixtures](tests/timed_export_checks/README.md) compare canonical
properties and bounded execution across explicit UTC, floating and synthetic
zone contexts. The recurrence fuzz target also checks rebuilt and reimported
rules against finite calendar/clock models. The hosted timed export gate
separates native construction, semantic access, checked wrapper construction,
export and first/resumed consumption. Wrapper construction currently renders
canonical properties to validate their byte cap; its allocation traffic is
measured separately. These counters measure requested bytes, not retained
memory. The [meeting exchange application](examples/meeting_exchange/main.roc)
is checked against local sources and distributable bundles. The same oracle and fuzz models exercise
`ScheduleDefinition` construction and fresh-window cursors, including source
identities and native fractional labels. Its hosted resource gate varies
0–4096 ending overrides, owned/shared/sliced inputs and finite query horizons,
measuring construction, definition access and first/resumed consumption
separately. Checked definitions prepare endings once; this evidence does not
establish retained-memory bounds.

The [UTC cancellation fixtures](tests/utc_cancellations_checks/README.md)
extend this evidence to zoned DTSTART with UTC EXDATE. They distinguish original
source exclusions from selected-boundary exclusions across actual gaps/folds,
colliding source labels and explicit RDATE/PERIOD inclusions. Original and saved
definitions run with different finite budgets against fixed independent
positions and identities. The gate runs the composed checks interpreted and
natively, and the independently calculated UTC coordinates. The meeting exchange
application demonstrates a UTC cancellation for a local Paris meeting.

Fixture provenance and hashes live in `tests/oracles/gregorian-manifest.toml` and
`tests/oracles/julian-manifest.toml`. Julian fixtures are generated from
Howard Hinnant’s attributed public-domain March-based formulas, independent of
production January counting; the 1582 equal-day fixture anchors the epochs.
To deliberately refresh expectations, use CPython 3.14.3 and run
`python3 scripts/oracles.py --refresh`, then review the JSONL and manifest diff.
Generation checks the table model against all 3,652,059 dates in Python's domain.
Never regenerate expected values from roc-time output or bless a mismatch.

Zone provenance is in `tests/oracles/zones-manifest.toml`, including the source
release, pinned wheel URL and SHA-256.
The generator uses `ZoneInfo.from_file`, never the host database, and writes
`tests/oracles/zones.jsonl` plus small typed smoke/rule fixtures in
`tests/oracle_zones/Cases.roc`. To refresh with CPython 3.14.3, download that exact
wheel under `.roc-time-tmp/` and run:

```bash
python3 scripts/generate_zone_oracle.py .roc-time-tmp/tzdata.whl
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
use the content-addressed [roc-fuzz 0.4.3 release](https://github.com/lukewilliamboswell/roc-fuzz/releases/tag/0.4.3)
URL directly; corpus and dependency metadata live under `tests/fuzz/`.
`scripts/fuzz.roc` is their single runner. Set `ROC_NIGHTLY` to select a package compiler:

```sh
blueprint run fuzz -- --operation all
blueprint run fuzz -- --operation build --targets precision
blueprint run fuzz -- --operation run --targets precision --runs 10000 --seconds 5 --seed 1
blueprint run fuzz -- --operation replay --targets precision
.roc-time-tmp/fuzz/precision show tests/fuzz/corpus/precision/alternating
blueprint run fuzz -- --operation lifecycle
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

The compiler's encoding hook uses `encoding.parse_str(encoding, state)`
and `encoding.encode_str(text, state)`. Keep the executable codec checks when
upgrading the compiler: documentation on the compiler's moving main branch may
describe a different hook signature. Codec tests establish interchange strings,
not a versioned native persistence format.

## Instrumented fixture platform

Install Zig 0.17.0 (`ZIG` can select its executable) alongside the package
compiler. The default gate builds the host and verifies its controls:

```sh
ROC_NIGHTLY=/path/to/roc blueprint run fixture-platform
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

Dev builds exercise `expect` failures. The optimized backend removes
`expect`, so resource assertions needed in optimized runs use `Host.assert!`.
The host makes both supported assertion failures return nonzero; negative
controls test that behavior. Keep tested operations observable using runtime
inputs and consumed outputs. Separate input construction, algorithm and output
formatting when measuring. Resource evidence is specific to compiler, backend,
input size and ownership; do not generalize one passing probe to all operations.

The [boundary exclusion fixture](tests/boundary_exclusions_resource/main.roc)
runs through the same resource command. It separates table input/construction,
definition access, cursor construction and first/resumed consumption for
0, 1, 64 and 4096 exclusions, owned/shared/sliced lists and two large horizons.
Five-second execution bounds and always-active failing allocation controls
guard against eager execution. The recurrence fuzz model independently applies
piecewise offsets and both exclusion domains to a finite source grid. Its
[saved buffer-limit regression](tests/fuzz/boundary-exclusion-merge-buffer.json)
starts with one merge slot and resumes the returned cursor with two only after
an explicit `BufferLimit`; a permanently insufficient buffer does not promise
forward progress.

[structural_duration_hash](tests/compiler_repro/structural_duration_hash/README.md)
isolates a compiler crash when deriving a structural hash key containing a
nominal duration tail. Its scalar control checks and executes in interpreter,
dev and speed modes. `TimedSchedule.Endings` hashes the complete declaration fields
explicitly; the schedule definition checks exercise dictionary lookup for
checked native definitions. Recheck
the failing root and its control when upgrading the compiler.

[unit_value_dict_build](tests/compiler_repro/unit_value_dict_build/README.md)
isolates optimized builds that hang when a dictionary's value is the empty
record. `EventCollection` tracks seen identities in a `Set` instead; recheck the
root and its Bool control when upgrading the compiler.

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
compiler in use when they were set. Schedule checks also pause between start and calendar-end
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

Timestamp formatting has a separate fixture at
`tests/timestamp_format_resource/main.roc`. It checks every fractional width,
UTC assertion distinctions and four-digit year endpoints against independent
canonical spellings. Parsing and input storage precede the measured scope;
formatting allows one allocation/reallocation call and 128 requested bytes per
output, with dev/speed failing controls. Retained inputs are observed afterward.
These counters measure allocation traffic, not live or retained memory.

Run `blueprint run resource-identities` with `ROC_NIGHTLY` to check
that union with an empty operand and subtraction of empty coverage reuse the
input without allocation. The default gate runs this check on both backends.
Runtime inputs include empty and large coverage, signed endpoint extremes and
retained aliases; semantic comparisons sit outside the allocation counters.
An always-active allocation control verifies that the gate detects failures.

Interchange resource evidence lives in `tests/interchange_resource/main.roc`.
The normal fixture gate measures parsing, serialization, interpretation, stored
snapshot reads and inspection separately for 1/32 annotations and 2/16,384
retained transitions. It checks semantic output and 100,000 stored reads with
zero allocation traffic under a five-second subprocess limit, plus dev/speed
failing allocation controls. Rules and runtime input are built outside those
scopes. Counts are cumulative requested bytes, not live or retained memory;
initial interpretation remains linear in the supplied transition table.
The same gate measures scoped EDTF parsing, serialization and bounded plain
explanation separately with a runtime five-scope input and a 16 KiB ceiling per
scope. It checks the year/month group fact and canonical text, allocation-free
rejection above 64 input bytes, and a dedicated zero-ceiling failing control.

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

The [cross-language benchmark guide](benchmarks/comparison/README.md) adds
Go, Python, Jiff and Tempo adapters, dependency pins, upstream workload references
and explicit compatibility profiles. Run its opt-in setup with
`ROC=/path/to/roc python3 scripts/benchmark_comparison.py --fetch --smoke`.
Docker and the additional language runtimes are not required by the normal gate.

The [Chrono benchmark guide](benchmarks/chrono/README.md) defines the shared input
profile, independent output checks, compiler/allocator choices and sampling method.
The gate compiles both benchmark executables and runs
`benchmark_chrono.py --smoke --fetch`: 1,000 iterations, one warmup and three
samples per kernel, checked against the independent corpus and checksums.
Use the Rust version in `benchmarks/chrono/rust-version` and install the matching
`x86_64-unknown-linux-musl` target on Linux, or `aarch64-apple-darwin` on Apple
Silicon. For example, run `rustup toolchain install "$(cat benchmarks/chrono/rust-version)" --profile minimal --target x86_64-unknown-linux-musl`,
then select it with `RUSTUP_TOOLCHAIN` when running the gate. CI installs and
selects this exact version.

Missing toolchains, failed dependency acquisition and mismatches fail the gate.
Cargo dependencies use the checked-in lockfile; builds run offline after the
locked fetch. Smoke timings are correctness evidence, not performance claims.

Run longer opt-in benchmarks without concurrent builds or tests. They compare
selected date and timestamp operations, not overall library capability; their
in-process timing excludes setup. Keep raw results under `.roc-time-tmp/`.

## Compilers and releases

Neither compiler is updated automatically. Refresh locked tooling with
`blueprint update` in a maintainer pull request, review the source revisions and
utility digests, then run the complete gate and release dry run before merging.

The package compiler is the latest nightly. When a nightly breaks the packages or
examples, fix them on `main`; when it breaks a published release, that release
needs a patch release, described below.

To change the tooling compiler, open a pull request that changes the `roc-stable`
tag in `Blueprint.roc`, run `blueprint update roc-stable` in the same pull request
to lock the new archive's digests, and fix any script the new compiler breaks
there, so the tag and the scripts move together. Native documentation
rendering uses the separately verified released binary described below.

Releases are dispatched from `main` and are immutable. To release:

1. Dispatch `Release` on `main` with a new package SemVer such as `0.2.0` or
   `0.2.0-rc1`; a prerelease suffix marks the release as a prerelease. Every pull
   request runs the same workflow as a dry run under version `0.0.1-dryrun`.
2. CI runs the complete gate. The shared workflow checks the version with `roc bump` against
   the latest release, runs the examples against the working tree, then bundles
   both packages with the latest nightly, builds `roc-time-examples-<version>.zip`
   and the API documentation archive from the same commit, and runs that archive
   unchanged against those exact bundles served on loopback through a fresh
   package cache, in a job that has no copy of this repository.
3. The publish job, behind the protected `release` environment, checks out
   nothing from this repository, attests the tested files, uploads them to a
   draft, verifies every asset against the tested file and publishes. Then
   `Documentation` restores immutable API versions, renders the tagged final-release
   manual with the shared renderer, and deploys Pages.
4. Verify the release notes, both package URLs and the examples archive against
   the published URLs.

Release files include the versioned PDF manual and the package, examples and
API archives below. `roc-time-<hash>.tar.zst` and
`roc-time-tzdb-<hash>.tar.zst` are the two packages; Roc uses the filename prefix
to distinguish packages sharing a versioned release path, and the archive bytes
and content hashes are those produced by `roc bundle`.
`roc-time-examples-<version>.zip` holds every application under `examples/` with
only its `time` and `zones` dependency lines changed to that release's URLs, a
README, and `spec.json` with the output recorded at release time. Committed
examples are never rewritten after a release, so there is no follow-up pull
request. `roc-time-docs-<version>.zip` preserves the compiler-generated API pages
under `<version>/`; `LICENSE` is attached as published.

The release notes state the `roc version` the release was built and tested with
and the shared workflow revision that built it. That record replaces a header
pin.

Never move a tag, replace a published asset or publish rebuilt archives under an
existing version. Use the shared publisher's interrupted-release checks when retrying a failed
publication. A fix after publication always requires a new version.
If docs deployment fails after the release succeeds, dispatch `Documentation` on `main` to restore the latest final release. API documentation is
stored as immutable release assets and restored during Pages assembly; generated
pages are not checked into Git and authored guides live in `docs/*.adoc`. Assembly
refuses missing earlier release documentation. Configure the `github-pages`
environment to allow deployment from `main`.

The nightly compatibility workflow is roc-automation's shared workflow: it runs
the latest full release's examples archive, unchanged, on the latest nightly and
keeps one tracking issue open while it fails. A failure there means that release
needs a patch release: fix `main`, then release the next patch version. The
published archive is never edited. Releases through 0.3.2 carry `expected/` output
rather than `spec.json`, so the first shared-format release is 0.3.3. Dispatch the workflow with `nightly-tag` or `release-tag` to test another
combination.

`roc-0.1.x` is a frozen branch from the earlier compiler-pin model and is not a
release source.

Build and test a release candidate locally with roc-automation's utility and the
package compiler on `PATH`:

```sh
RP_REPOSITORY=lukewilliamboswell/roc-time blueprint run release-package -- build 0.0.1-dryrun
RP_REPOSITORY=lukewilliamboswell/roc-time blueprint run release-package -- test-archive
```

## Zone-data representation measurements

With the package compiler and CPython 3.14.3, run:

```sh
ROC_NIGHTLY=/path/to/roc blueprint run measure-zone-roc -- .roc-time-tmp/tzdata.whl --samples 3
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
python3 scripts/generate_zone_database.py .roc-time-tmp/tzdata.whl .roc-time-tmp/generated-zone-package --verify-roc /path/to/roc
```

Generation requires CPython 3.14.3 and the distribution wheel URL/hash pinned
in `scripts/generate_zone_database.py` (currently tzdata 2026.5 / IANA 2026e).
Download that wheel to the path supplied above; the historical oracle wheel is
pinned independently in `scripts/generate_zone_oracle.py` and is not a substitute.
Generation verifies integrity and both embedded IANA version declarations. The
generator and [package manifest](tzdb/package/manifest.json) declare the finite
validity horizon. Future footer transitions are expanded ahead of time, with original
alias/canonical identities from `tzdata.zi`.
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
Review each intervening IANA release and extend the source-backed public caller
fixtures in [tests/zone_database](tests/zone_database/README.md). Preserve the
historical oracle pins and corpora unless deliberately reviewing those separately.
Existing release URLs and resolved snapshots keep their original data; an
application selects new rules by updating its dependency and explicitly
re-resolving where needed.
The resource fixture uses runtime names and consumes transition checksums. It
limits lookup to zero allocation/reallocation calls in development and at most
one in optimized native builds under the compiler used for the measurement. This covers the data lookup and
returned record, not core adaptation, parsing/formatting or retained memory.
Trace marks bracket the operation. The host assertion remains active when
optimized `expect` checks are removed. Bundled examples import the text assets
through the downloaded package in interpreter and native execution.
Build both release bundles and their example archive with the shared utility:

```sh
RP_COMPILER=/path/to/roc blueprint run release-package -- build 0.0.1-dryrun
```

Measure the actual package with
`ROC_NIGHTLY=/path/to/roc blueprint run measure-zone-package -- --package tzdb/package`.
Repeat `--package` to compare a historical pack checked out under `.roc-time-tmp/`.
Reports retain commands, hashes, compiler/target, build samples and observable
lookup results. Source encoding, compile-time evaluation and linked data retention
are separate costs; a static name alone does not prove unused-zone elimination.

Run `ROC_NIGHTLY=/path/to/roc blueprint run measure-gregorian` for the
Gregorian conversion microbenchmark (LLVM speed, one million dates, three
warmups and fifteen samples). Run it without concurrent test or build jobs.
The fields and roundtrip workloads include process startup and final formatting;
raw timings and machine/compiler metadata stay under `.roc-time-tmp/`. This is
not an allocation measurement or a general library ranking.
