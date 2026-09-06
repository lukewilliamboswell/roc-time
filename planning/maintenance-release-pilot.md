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

- Create and push `roc-0.1.x` from the verified pilot changes with the September 5
  package pins; preserve September 6 on the development branch. Obtain actual
  GitHub validation evidence for both workflows before publication.
- Exercise the new `0.1.0-rc2` candidate release from `roc-0.1.x`, then verify its
  actual published URLs, notes, direct `roc main.roc` multi-file applications,
  documentation deployment and follow-up PR.
- Review/integrate the pilot PRs and the release follow-up without downgrading
  development package pins. Close the superseded rc1 follow-up after its docs
  are preserved. Public examples currently reference rc1, whose unprefixed
  mutable bindings warn under the September 5 compiler: promote the verified
  new release URLs before claiming that public path works on the pilot compiler.
- Verify a nightly update edits only the configured development headers while
  leaving example pins unchanged, including success/no-op/failure evidence.
  Keep automatic merging disabled and respect repository protection/review.
- Resolve or explicitly report `roc bump` limitations: these compilers reject
  prerelease values for `--expect`, and extracting the rc1 public API reports
  its unexposed `PersistenceEnvelope.Error`. Do not call this a passing API diff.
- Finish reusable guidance with live acceptance and the transition to actual
  upstream stable releases. Remove the explicit simulated-compiler mapping at
  that transition.

Support duration and any funded LTS remain separate policies. Once upstream
stable releases are adopted, publications must support a stable compiler even
when development moves ahead. The pilot exception must remain explicit and
scoped to its named branch and compiler.

Remove this plan once the integration and live acceptance criteria are complete.
