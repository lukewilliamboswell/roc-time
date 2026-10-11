# Target workflows

Align the repository with the
[roc-automation target workflows](https://github.com/lukewilliamboswell/roc-automation/blob/main/docs/ideal-workflows.md):
tooling as Roc scripts on a Blueprint-pinned `roc-stable`, packages and examples
on the floating nightly with no `roc` header field, repository examples on
relative package paths, an examples archive on each release, and a nightly check
of the latest release. Releases are dispatched from `main`; the first under this
model is 0.2.0.

## Deliverables

- Remove every `roc` header field and replace the exact-pin guards in the Python
  harness with a recorded `roc version`.
- Point `examples/` at `../../package/main.roc` and `../../tzdb/package/main.roc`,
  apply the source migrations currently applied only to copies, and fold the
  staged `tests/` applications into `examples/`.
- Roc scripts: layout static checks, in-place example tests, both bundles with
  their role manifest, loopback bundle and archive tests including rejection
  cases, `roc-time-examples-<version>.zip`, and release notes naming both
  compilers. Delete the Python each replaces, including the starter kit and the
  release follow-up tooling.
- `ci.yml` and `release.yml` on the floating nightly, resolved once per run;
  publication behind a protected `release` environment; docs publication without
  the follow-up pull request. Retire the nightly updater and its configuration.
- `nightly.yml` with one tracking issue, and `update-blueprint.yml`.
- Rewrite the compiler, release and example guidance in CONTRIBUTING.md,
  AGENTS.md, README.md, the example and zone READMEs and the site content.

## Decisions and acceptance still needed

- The specification describes one package. Record how the `time`/`zones` pair
  and an `expected/` output directory in the archive fit, and report both to
  roc-automation.
- The environment provides only `roc-stable` and the programs Roc scripts start.
  Decide whether Python 3.14.3, Zig 0.16.0 and Rust move into it when the
  remaining harness is ported.
- Repository settings are outside the tree: required check names, the `release`
  environment, and removal of the updater's required `configuration` check
  before its workflow is deleted.

Complete when a release dry run produces an archive whose headers differ from
the repository's only in the package dependencies, a rehearsed incompatible
nightly opens, updates and closes exactly one issue, and no workflow or script
reads a compiler pin from a header.
