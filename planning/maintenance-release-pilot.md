# Maintenance release pilot

Objective: pilot shared main-development and `release/roc-0.1.x` compiler-support guidance
from roc-automation without implying an LTS or response-time commitment.

Remaining deliverables:

- Establish an actual upstream Roc release and verified compiler installer before
  creating a versioned compiler-support branch; an existing nightly pin is not
  evidence of stable compiler compatibility.
- Review the shared roc-automation PRs and the roc-time pilot PRs before merging.
- Run the pilot checks in GitHub, including a validation-only dispatch on the
  compiler-support branch after a suitable upstream release exists; do not create another release to test CI.
- Enable nightly bot PR creation and establish required checks through the
  repository's reviewed settings policy before claiming unattended operation.
- Verify one nightly candidate, no-op and failure report. Review-only bot PRs
  currently receive linked validation runs; required-status attachment must be
  verified separately before relying on it for protected merges.
- Merge or recover the existing rc1 documentation follow-up so later site
  deployments retain its versioned pages.

A compiler-support branch identifies an upstream Roc compiler compatibility line;
package releases are independently versioned and immutable. Support duration,
backport scope and any funded LTS are separate policies. Publication remains an
explicit action after exact candidate and bundle verification against a published
stable Roc compiler. Nightly development cannot publish package releases, including
from `main`. No automatic
cross-line compiler upgrade or merge bypass is part of this pilot.

Remove this plan once the reviewed integration and live pilot are complete.
