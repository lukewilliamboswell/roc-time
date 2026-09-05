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
`ROC=/path/to/pinned/roc python3 scripts/oracles.py` to compare 4,096 Gregorian
observations against checked-in generated Roc expectations. The full test command includes this
gate. Expectations come from CPython 3.14.3 `datetime` within years 1–9999 and a
400-year table model beyond that range; model-derived BCE/extreme-year cases
are not direct Python conformance evidence. The external forward formula shares
our year-counting approach, so sequential tests and reviewed conventions remain
necessary alongside differential agreement.

The gate checks each public conversion independently, plus malformed fields and
provider limits. Generated `tests/oracle_gregorian/Cases.roc` contains typed inputs and expected
results derived solely from the external references. A native Roc driver
compares them directly: normal replay performs no JSON case parsing or case
source generation. The compiler rejects malformed fixture types; wrong values,
missing/duplicate case identities, driver failures and budget overruns fail the gate. Normal replay reads versioned data and needs no
live reference service. Each stage is limited to 120 seconds and 1 MiB of output.
Reports and generated inputs stay under `.roc-time-tmp/oracles/`.

Fixture provenance and hashes live in `tests/oracles/gregorian-manifest.toml`.
To deliberately refresh expectations, use CPython 3.14.3 and run
`python3 scripts/oracles.py --refresh`, then review the generated Roc module and manifest diff.
Generation checks the table model against all 3,652,059 dates in Python's domain.
Never regenerate expected values from roc-time output or bless a mismatch.

Test applications live under `tests/<name>/main.roc`, with pure test logic in
neighboring type modules. The precision, span, coverage, Gregorian and arithmetic roots
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
