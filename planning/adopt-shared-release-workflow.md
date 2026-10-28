# Complete automation adoption

## Objective

Finish PR #49 and reconcile tracker #27 with current roc-automation guidance.
Preserve design R01–R16 and independent evidence while replacing orchestration.
Product CI verifies Linux x86-64; Blueprint's other provisioning targets do not
establish product portability.

## Remaining deliverables

- Provision native harness toolchains through Blueprint's locked Nix sources:
  Zig 0.17.0, CPython 3.14.3, Rust 1.95.0 including the musl target, and external
  tools. Remove CI-only setup after validating replacements.
- Port test, fixture-host, oracle-replay, fuzz, zone-generation, measurement and
  benchmark orchestration to Roc. Retain Python reference generators and measured
  Python subjects with pinned dependencies and provenance. Preserve corpus bytes,
  intended diagnostic checks, resource assertions and failing controls.
- Make `blueprint run check` the complete contributor gate. Keep it in CI and
  set the shared release check-task empty only once CI runs the complete gate.
  Preserve bounded fuzz searches and replay; separate sustained campaigns.
- Replace legacy documentation restoration with Roc preparation around the shared
  renderer. Preserve historical API routes and safely read legacy tar.gz and new
  ZIP archives. Add a read-only docs build and isolated Pages deployment, refreshed
  for final releases but not prereleases. Remove old implementations only after
  replacement checks pass.
- Remove automated lock-update PR creation. Use executable script shebangs and
  per-job permissions throughout. Reconcile contributor instructions and tracker
  items with local policy: no compiler headers and ROC_NIGHTLY remains supported.
- Review repository settings with upstream's read-only checker. Prepare main/tag
  protections, signed commits and current required checks; disable Actions PR
  creation, enable private vulnerability reporting, restrict Pages to main.
  Preserve immutable releases and the release environment. Maintainer applies
  settings and reviews obsolete branch deletions.

## Acceptance

- Review utility lock hashes and lengths against tools-0.6.0's manifest.
- Gate, example specification, release build and archive test pass with recorded
  compiler identities. Compare replacement drivers with their predecessors before
  deletion, including missing/malformed outputs, timeouts and failing controls.
- Validate HTML, PDF, Markdown exports, discovery index, API history and links.
- Hosted PR and dispatched dry runs pass against both bundles. All 30 example
  folders travel intact except rewritten dependency declarations.
- Maintainer publishes the next version allowed by strict bump checks on both
  packages. Existing releases remain immutable. Shared nightly with empty
  selectors passes against the latest final release and issue lifecycle is tested.
- Dashboard refresh shows every direct automation reference matching observed
  upstream main and complete passing compatibility evidence under 48 hours old.

Commits, publication, external issue updates and destructive branch cleanup are
maintainer rollout steps unless separately authorized. Do not expand this task
into temporal features or a separate SBOM project. Delete this plan when its
remaining deliverables and acceptance criteria are satisfied.
