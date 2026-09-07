# Documentation website publication

Objective: publish authored task guides and immutable versioned API documentation
without tracking generated HTML in Git.

## Remaining publication dependencies

- Upload the byte-preserved documentation archives for `0.1.0-rc1`,
  `0.1.0-rc2` and `0.1.0-rc3` to their corresponding releases before deploying
  this workflow. Recover source bytes from the Git parent that still contains
  `www/<version>/`; use `scripts/release_docs.py pack` and verify restored files
  byte-for-byte. Never regenerate or replace those historical pages.
- Verify the published asset digests and run the docs workflow. Confirm the
  authored root and existing version URLs, including retry behavior. Missing
  historical assets deliberately block deployment.
- Bind guide release labels, API links and starter links to the selected public
  release when promoting new applications. Keep development claims separate.

## Acceptance

The Pages artifact contains generated guides plus restored version directories,
without authored source or compiler binaries. Prior API bytes are unchanged.
Follow-up PRs contain public example and README updates, not generated pages.
Local assembly and tests use explicit restored docs roots. Publication succeeds
with narrowly scoped permissions and pinned tool/action dependencies.

Remove this plan when remote migration and deployment acceptance are complete.
