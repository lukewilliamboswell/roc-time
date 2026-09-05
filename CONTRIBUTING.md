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
Put exhaustive cases and harnesses under `tests/` using the same root layout.
Update recursive discovery and verify local and bundled package usage when
adding or moving an example.

## Scripts


All repository tooling lives in `scripts/` and is written in Python 3 with no
third-party Python dependencies.

| Script | Purpose |
| --- | --- |
| `all_tests.py` | Full local CI run: check, test, fuzz, docs, bundle, examples |
| `generate_zone_database.py` | Generate a pinned bounded companion package and verify imports through the core adapter |
| `measure_zone_roc.py` | Generate prototype zone encodings and measure source/archive, compiler and native binary costs |
| `measure_zone_data.py` | Reproduce pinned zone archive/data size measurements, separately from compiler/runtime costs |
| `oracles.py` | Deterministic external/reference-model comparisons through public APIs |
| `fuzz.py` | Pinned target builds, bounded searches, curated replay and failure lifecycle |
| `test_compile_failures.py` | Domain separation and opaque representation checks |
| `bundle.py` | Bundle `package/` into a distributable `.tar.zst` |
| `docs.py` | Generate versioned docs into `www/<version>` |
| `test_bundle_examples.py` | Verify the examples against a bundled package served over localhost |
| `update_example_urls.py` | Point the examples at a released bundle URL |

Python tooling orchestrates compiler subprocesses and localhost serving for
bundle verification.

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

At least one oracle is required for temporal implementation work. Run
`ROC=/path/to/pinned/roc python3 scripts/oracles.py` to compare 4,096 Gregorian and 4,096 Julian
observations, plus 2,592 zone observations, against checked-in generated Roc expectations. The full test command includes this
gate. Expectations come from CPython 3.14.3 `datetime` within years 1–9999 and a
400-year table model beyond that range; model-derived BCE/extreme-year cases
are not direct Python conformance evidence. The external forward formula shares
our year-counting approach, so sequential tests and reviewed conventions remain
necessary alongside differential agreement.

The gate checks each public conversion independently, plus malformed fields and
provider limits. Generated `tests/oracle_gregorian/Cases.roc` contains typed inputs and expected
results derived solely from the external references. The Roc driver runs under
both the interpreter and native execution, comparing them directly: normal replay performs no JSON case parsing or case
source generation. The compiler rejects malformed fixture types; wrong values,
missing/duplicate case identities, driver failures and budget overruns fail the gate. Normal replay reads versioned data and needs no
live reference service. Each stage is limited to 120 seconds and 1 MiB of output.
Reports and generated inputs stay under `.roc-time-tmp/oracles/`.

Fixture provenance and hashes live in `tests/oracles/gregorian-manifest.toml` and
`tests/oracles/julian-manifest.toml`. Julian fixtures are generated from
Howard Hinnant’s attributed public-domain March-based formulas, independent of
production January counting; the 1582 equal-day fixture anchors the epochs.
To deliberately refresh expectations, use CPython 3.14.3 and run
`python3 scripts/oracles.py --refresh`, then review the generated Roc module and manifest diff.
Generation checks the table model against all 3,652,059 dates in Python's domain.
Never regenerate expected values from roc-time output or bless a mismatch.

Zone provenance is in `tests/oracles/zones-manifest.toml`. The pinned tzdata
2025.2 wheel contains IANA 2025b data; its URL and SHA-256 are recorded there.
The generator uses `ZoneInfo.from_file`, never the host database, and writes
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
neighboring type modules. The precision, span, coverage, Gregorian, arithmetic, calendar-interoperability, clock, offset and zone roots
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
Apple Silicon macOS is verified; Linux x86-64/musl is configured for CI but has
not been executed locally. Other hosts explicitly report fuzzing as unverified.
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
native caller that imports every name through the real package adapter. Output
includes source integrity metadata and applicable notices. This generator does
not publish a release; provider integration tests and bundled application
examples remain necessary before distribution.
