# Maintenance release pilot

Objective: pilot shared main-development and `release/0.1.x` maintenance guidance
from roc-automation without implying an LTS or response-time commitment.

Remaining deliverables:

- Review the shared roc-automation PRs and the roc-time pilot PRs before merging.
- Run the pilot checks in GitHub, including a validation-only dispatch on the
  maintenance branch after integration; do not create another release to test CI.
- Enable nightly bot PR creation and establish required checks through the
  repository's reviewed settings policy before claiming unattended operation.
- Verify one nightly candidate, no-op and failure report. Review-only bot PRs
  currently receive linked validation runs; required-status attachment must be
  verified separately before relying on it for protected merges.
- Merge or recover the existing rc1 documentation follow-up so later site
  deployments retain its versioned pages.

A maintenance branch identifies a compatible package line. Support duration,
backport scope and any funded LTS are separate policies. Publication remains an
explicit action after exact candidate and bundle verification. No automatic
maintenance compiler upgrade or merge bypass is part of this pilot.

Remove this plan once the reviewed integration and live pilot are complete.
