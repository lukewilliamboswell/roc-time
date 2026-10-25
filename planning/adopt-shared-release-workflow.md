# Adopt the shared release workflow

## Objective

Replace `release.yml`, `ci.yml` and the scripts that bundle, archive, test and
describe a release with roc-automation's reusable `release-package.yml` and its
`release-package` utility, keeping only what is specific to roc-time: the
packages, the examples, the oracle and fuzz harness, the manual and the site.

## Scope

Candidates for deletion once the shared side supports this repository's shape:
`scripts/build_release.roc`, `build_bundle.roc`, `build_examples_archive.roc`,
`test_examples.roc`, `release_notes.roc`, `latest_release.roc`,
`scripts/src/Release.roc` and the `release`, `latest-release` and `examples`
Blueprint tasks (892 lines of Roc), plus `ci.yml` and `release.yml`. The Python
docs archiving (`scripts/docs.py`, `release_docs.py`, `check_docs_history.py`)
and `release-docs.yml` stay until the site assembly reads the shared archive.

Stays in roc-time regardless: `check` (tooling, layout, packages, Python harness),
the oracle corpora, fuzz targets, benchmarks, `tzdb/` generation, the manual
and `assemble_site.roc`.

## Dependencies on the shared utility

Each is a capability roc-time's release needs that the utility does not have.
None can be worked around here without forking the release logic again.

1. **Directory examples.** Every application is `examples/<name>/main.roc` with
   one or two sibling type modules, depending on the package as
   `../../package/main.roc`. The utility accepts only `examples/<name>.roc` and
   `../package/main.roc`. The archive must carry every file of the directory
   and rewrite only `main.roc`'s dependency lines; the suite `path` is
   `examples/<name>/main.roc`, which the suite format already allows.
2. **Underscored names.** All 30 application directories use `_`; the suite
   contract rejects `_` in a path component while the archive helper and the
   example-file rule accept it.
3. **Two bundles.** `package/main.roc` (`time`) and `tzdb/package/main.roc`
   (`zones`), published as `roc-time-<hash>.tar.zst` and
   `roc-time-tzdb-<hash>.tar.zst` so the two share one release path. The zones
   bundle includes `.txt` and `manifest.json` members, which the utility's
   "members are the package's modules" check rejects. Proposal: derive the
   bundle roots from the relative dependency paths the examples declare, name
   each file `<repository>-<hash>` and `<repository>-<directory>-<hash>`, and
   allow declared data members. The `roc-time-bundles.json` role manifest then
   has no reader: the archive's `spec.json` dependencies name both URLs.
4. **Notes with two URLs.** Authored notes use no `{package-url}` today; the
   renderer appends a packages section with both URLs and digests. Proposal:
   one placeholder per bundle, `{time-url}` and `{zones-url}`, with
   `{package-url}` remaining the single-bundle spelling.
5. **Non-deterministic output.** `clock_deadline` prints the current time and is
   verified against wall-clock bounds; `calendar_conversion`, `coverage` and
   `sample_windows` have no recorded output and are only built and run. The suite
   has exact expectations or a declared `skip` with a reason and an issue.
   Decision needed: record the three outputs and declare `clock_deadline` as a
   skip, or add a bounded matcher.
6. **Runner prerequisites.** `check` runs the Python harness, which needs the
   Zig, Python and Rust toolchains that `.github/actions/setup-harness`
   installs. The shared build job runs only `blueprint run <check-task>`.
   Option here: split `check` into a Roc-only task for the shared workflow and
   keep the harness in this repository's own CI workflow.
7. **Version check policy.** `roc bump` may be unable to compile the previous
   release with the current nightly, so this repository warns instead of
   failing. The utility fails a dispatched release in that case.
8. **Documentation assets.** This repository publishes
   `roc-time-docs-<version>.tar.gz`, `roc-time-manual-<version>.zip` and the
   PDF, and `release-docs.yml` refuses to deploy when earlier API docs are
   missing. The utility publishes `<name>-docs-<version>.zip` and an optional
   PDF. The site restore must read the shared archive before the Python docs
   scripts go.

## Deliverables

- Thin `release.yml` caller; `ci.yml` reduced to the harness, or deleted if the
  harness moves behind the `check` task.
- `tests/spec.json` in the suite format, generated once from `tests/examples/*.txt`
  (stdout only; stderr empty; exit code 0), then maintained with
  `release-package test-examples --update`.
- The deletions listed under scope, with `CONTRIBUTING.md` and `README.md` updated.

## Completion criteria

A pull-request dry run and a dispatched dry run with a pinned nightly pass on
the shared workflow; the examples archive it builds holds every application
directory unchanged except dependency lines; the two bundles are published under
their current names; the nightly compatibility workflow runs the archived suite.
