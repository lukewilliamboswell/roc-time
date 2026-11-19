# Integrate PRs and upgrade the compiler and fuzz platform

Objective: integrate PRs #56–#58, use Roc nightly-2026-11-18-a520eed for
packages and pinned automation, adopt roc-fuzz 0.7.0 suites, and resolve #55
with verified published examples. Preserve design requirements R01–R16.

## Remaining acceptance

- Publish compatible release 0.5.0 after verified integration, rerun the published
  nightly compatibility workflow, and close #55 only with passing release evidence.

The shared release workflow's compiler asset-API transport can fail with HTTP 403
before tests run. The browser route works in contributor CI, but the shared
release caller cannot select it. Exposing a verified transport input requires an
upstream fix and then a reviewed consumer pin update. Upstream publication
authorization is pending; a tested patch is prepared locally using the installer
revision from [setup-roc #13](https://github.com/roc-lang/setup-roc/pull/13).
The legacy unverified browser transport is not an acceptable substitute. Track the fix in
[roc-automation #153](https://github.com/lukewilliamboswell/roc-automation/issues/153).

Remove this plan when the integration and published compatibility work is complete.
