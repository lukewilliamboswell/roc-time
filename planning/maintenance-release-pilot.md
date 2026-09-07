# Compiler-support release pilot

Validate a repeatable development and supported-compiler workflow across
roc-automation and roc-time, including published multi-file examples, package
bundles, release notes and documentation. This is a workflow experiment, not a
claim that upstream has released stable Roc.

Pilot inputs:

- `roc-0.1.x` simulates the supported compiler branch using
  `nightly-2026-09-05-b195f5b`.
- Development uses `nightly-2026-09-06-d85e877`.
- Compiler pins live in app/package/platform headers. Published examples retain
  their supported compiler and immutable package URLs while development tests
  rebind temporary copies to the checkout.
- Package versions are independent of compiler lines. Published changes receive
  new immutable releases; existing release contents must not be replaced.

Remaining deliverables:

- Finish documentation deployment and verify its public URLs; integrate the
  pilot PR and close superseded follow-ups after preserving their complete docs
  and published example snapshots.
- Complete explicit automatic validation for bot-created release follow-up PRs,
  then exercise it against the exact generated commit.
- Verify a nightly update edits only the configured development headers while
  leaving example pins unchanged, including success/no-op/failure evidence.
  Keep automatic merging disabled and respect repository protection/review.
- Finish reusable guidance with live acceptance and the transition to actual
  upstream stable releases. Remove the explicit simulated-compiler mapping at
  that transition.

Support duration and any funded LTS remain separate policies. Once upstream
stable releases are adopted, publications must support a stable compiler even
when development moves ahead. The pilot exception must remain explicit and
scoped to its named branch and compiler.

Remove this plan once the integration and live acceptance criteria are complete.
