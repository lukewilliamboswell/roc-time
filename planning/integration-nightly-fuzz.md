# Integrate PRs and upgrade the compiler and fuzz platform

Objective: integrate PRs #56–#58, use Roc nightly-2026-11-18-a520eed for
packages and pinned automation, adopt roc-fuzz 0.7.0 suites, and resolve #55
with verified published examples. Preserve design requirements R01–R16.

## Remaining acceptance

- Complete `blueprint run check` on the final commit, including Linux native
  resource fixtures with regenerated bindings and matched reviewed baselines.
  Finish the local full-gate rerun; source-only checks do not replace it.
- Complete the release dry run, unchanged archive replay and documentation checks.
- Finish PR #59, verify its final checks and merge the original PRs and integration.
- Publish compatible release 0.5.0 after verified integration, rerun the published
  nightly compatibility workflow, and close #55 only with passing release evidence.

The shared release workflow's compiler asset-API transport can fail with HTTP 403
before tests run. The browser route works in contributor CI, but the shared
release caller cannot select it. A later source-build run passed setup without
an upstream change. Track configuration support in
[roc-automation #153](https://github.com/lukewilliamboswell/roc-automation/issues/153).

Remove this plan when the integration and published compatibility work is complete.
