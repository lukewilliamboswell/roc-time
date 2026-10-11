# Target workflows

Align the repository with the
[roc-automation target workflows](https://github.com/lukewilliamboswell/roc-automation/blob/main/docs/ideal-workflows.md):
tooling as Roc scripts on a Blueprint-pinned `roc-stable`, packages and examples
on the floating nightly with no `roc` header field, repository examples on
relative package paths, an examples archive on each release, and a nightly check
of the latest release. Releases are dispatched from `main`; the first under this
model is 0.2.0.

## Deliverables

- `nightly.yml`: run the latest full release's examples archive unchanged on the
  latest nightly, driven by `scripts/test_examples.roc`, with a report job that
  keeps one tracking issue. Until a full release carries an archive, finish green
  with a notice and no issue.
- `update-blueprint.yml`: propose a signed, lock-only pull request from
  `blueprint update` and start its `ci.yml` run.
- Release 0.2.0 from `main`, the first release with an examples archive.
- Port the Python harness (`scripts/python_harness.py` and the scripts it runs)
  and the documentation tooling to Roc scripts.

## Decisions and acceptance still needed

- The specification describes one package. Report to roc-automation how the
  `time`/`zones` pair and the `expected/` directory in the archive fit.
- The environment provides only the pinned compiler and the programs Roc scripts
  start. Decide whether Python 3.14.3, Zig 0.16.0 and Rust move into it when the
  remaining harness is ported.
- Repository settings are outside the tree: required check names (`test`,
  `Build and test release candidate`), the protected `release` environment, and
  removal of the updater's required `configuration` check.

Complete when a rehearsed incompatible nightly opens, updates and closes exactly
one issue against a published release, and a lock update pull request passes
`ci.yml`.
