# Complete automation adoption

## Objective

Finish PR #49 and reconcile tracker #27 with current roc-automation guidance.
Preserve design R01–R16 and independent evidence while replacing orchestration.
Product CI verifies Linux x86-64; Blueprint's other provisioning targets do not
establish product portability.

## Remaining deliverables

- Port the remaining Python fixture verification, oracle-replay, zone-generation,
  measurement and benchmark drivers to Roc. The Roc integration inventory keeps
  them executable during migration. Retain independent Python reference
  generators and measured Python subjects, their dependency pins, corpus bytes,
  provenance and failure controls.
- Verify the complete gate and documentation workflow on the PR with the locked
  native toolchains. Require `test`, `Build and verify documentation`,
  `Release / Build and test the source` and `Release / Test the release candidate`.
- Apply the prepared repository settings: add active main and all-tag rulesets;
  require `test`, `Build and verify documentation`,
  `Release / Build and test the source` and `Release / Test the release candidate`;
  restrict tag updates/deletions; disable Actions PR creation/approval; enable
  private vulnerability reporting; restrict Pages to main (remove roc-0.1.x).
  Upstream's read-only checker found these six gaps, including the missing
  SECURITY.md added in this PR. Preserve immutable releases, read-only default
  tokens and the main-only release environment. Maintainer applies settings and
  reviews obsolete branch deletions.

## Acceptance and rollout

- Preserve intended compile diagnostics, oracle transport failures, resource
  assertions and failing controls when replacing each remaining driver. Compare
  with its predecessor before deletion; ordinary oracle replay stays offline.
- Hosted PR and dispatched dry runs must pass against both bundles. The shared
  archive contains every example folder except rewritten dependency declarations.
- Validate the deployed HTML/PDF/Markdown publication and historical API routes.
  Prereleases do not replace the default release documentation.
- Maintainer publishes the next version allowed by strict bump checks on both
  packages. Existing releases remain immutable. Shared nightly with empty
  selectors must pass against the latest final release. Rehearse opening,
  updating and closing the owned tracking issue.
- Dashboard refresh must show every direct automation reference matching observed
  upstream main and complete passing compatibility evidence under 48 hours old.

Keep local policy: no compiler headers; ROC_NIGHTLY remains supported. No temporal
contract changes or separate SBOM project are part of this task. Publication,
external issue updates and destructive branch cleanup are maintainer rollout
steps unless separately authorized. Delete this plan when its remaining
acceptance criteria are satisfied.
