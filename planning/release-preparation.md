# Verify the release publication

Objective: complete the supported-compiler release, public examples and documentation.

## Remaining deliverables

- Monitor the [release workflow](https://github.com/lukewilliamboswell/roc-time/actions/runs/34117544145)
  through package publication and documentation deployment. Investigate failures
  before retrying; preserve immutable published archives.
- Review the published release notes for supported standard serialization,
  removal of the private archive API, nested Calendar APIs, timed iCalendar
  export/UTC cancellations, and civil text/reporting capabilities. Include
  compiler information, both package URLs, starter download and concrete format
  limits; avoid broad conformance claims.
- Verify the published starter and applications against their actual immutable
  package URLs, then review the generated public-example follow-up described in
  [user time workflows](user-time-workflows.md).
- Complete the deployment and public navigation checks in
  [documentation website publication](documentation-site.md).

## Acceptance

Both published packages, their starter applications and documentation describe
and execute the same supported APIs. Public examples declare the release compiler
and immutable package URLs. Historical API documentation remains byte-preserved.

Remove this plan when publication and its verification are complete.
