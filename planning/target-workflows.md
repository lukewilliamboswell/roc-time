# Target workflows

Align the repository with the
[roc-automation workflows](https://github.com/lukewilliamboswell/roc-automation/blob/be0776b7446800b1d975df5f9cb4961d560c1aa7/docs/workflows.adoc):
tooling as Roc scripts on a Blueprint-pinned `roc-stable`, packages and examples
on the floating nightly with no `roc` header field, repository examples on
relative package paths, an examples archive on each release, and a nightly check
of the latest release. Releases are dispatched from `main`; the first under this
model is 0.2.0.

## Deliverables

- Release 0.2.0 from `main`, the first release with an examples archive.
- Port the Python harness (`scripts/python_harness.py` and the scripts it runs)
  and the documentation tooling to Roc scripts.
- After 0.2.0, rehearse `Nightly compatibility` with an incompatible
  `nightly_tag`: it has only run against a release without an archive.
- Dispatch `Update Blueprint lock` on `main` once merged; its API commit and pull
  request cannot be exercised from a branch.

## Decisions and acceptance still needed

- The specification describes one package. Report to roc-automation how the
  `time`/`zones` pair and the `expected/` directory in the archive fit.
- The environment provides only the pinned compiler and the programs Roc scripts
  start. Decide whether Python 3.14.3, Zig 0.16.0 and Rust move into it when the
  remaining harness is ported.
- Repository settings are outside the tree: required check names (`test`,
  `Build and test release candidate`), the protected `release` environment, removal of
  the updater's required `configuration` check, and permission for GitHub Actions
  to create pull requests.

Complete when a rehearsed incompatible nightly opens, updates and closes exactly
one issue against a published release, and a lock update pull request passes
`ci.yml`.
