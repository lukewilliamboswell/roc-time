# Documentation website publication

Objective: publish authored task guides and immutable versioned API documentation
without tracking generated HTML in Git.

## Remaining publication dependencies

- Run the docs workflow and confirm the authored root and existing version
  URLs, including retry behavior. Missing historical assets deliberately block
  deployment.
- Verify durable guide links resolve to release metadata, the API navigation
  and working pinned examples. Authored prose must not duplicate release pins.

## Acceptance

The Pages artifact contains generated guides plus restored version directories,
without authored source or compiler binaries. Prior API bytes are unchanged.
Follow-up PRs contain public example updates, not generated pages or copied
release metadata in the README.
Local assembly and tests use explicit restored docs roots. Publication succeeds
with narrowly scoped permissions and pinned tool/action dependencies.

Remove this plan when remote migration and deployment acceptance are complete.
