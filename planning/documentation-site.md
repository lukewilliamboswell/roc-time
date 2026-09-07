# Documentation website integration

Objective: make task-oriented guides the repository website entrypoint while
preserving version-specific API documentation and working released examples.
The authored foundation lives in `www/site/`; its local build uses basic-ssg.

## Remaining deliverables

- Integrate the generator into the documentation release pipeline. Decide one
  owner for `www/index.html`: `scripts/docs.py` currently writes a version
  redirect, so it must not overwrite the authored landing page.
- Stage a deployment artifact containing generated guide HTML and historical
  versioned API documentation. Exclude `www/site/` source/build tooling from
  that artifact; preserve the release-docs snapshot and history checks.
- Bind guide release labels, API links and starter-kit links to a deliberately
  selected published package/compiler pair. Updating the package must not
  silently promote unreleased API claims. Retain clearly separated development
  source/API navigation.
- Add the build/link gate to an appropriate documentation workflow with pinned
  toolchain/action dependencies. Keep publishing permissions in the deployment
  job; a local build or pull request must not deploy.
- Expand guides when their linked workflows gain a supported release: first
  appointment/reporting convenience and schedule interchange/storage. Promote
  complete runnable applications and verify their released bundles before
  replacing development labels with release claims.

## Acceptance

The site builds with its pinned basic-ssg release and compiler, including at a
repository URL prefix. Its landing page leads to getting started, substantive
task guides, declared scope, API navigation and version guidance. Published
example instructions use complete application folders and compatible immutable
dependencies. Every generated internal link resolves; historical API pages are
unchanged. The deployed root is the intended landing page after subsequent
stable and prerelease documentation updates, and the artifact contains no site
source files or development binaries.

Remove this plan when pipeline integration and release promotion behavior meet
these criteria. Build instructions belong in `www/site/README.md`; user content
belongs in its Markdown sources, not in the repository README or this plan.
