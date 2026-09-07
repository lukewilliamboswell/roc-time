# Prepare the next release

Objective: publish a coherent standard-first package experience after resolving
current cancellation/fuzz failures and removing private archive formats.

## Remaining deliverables

- Prepare the `roc-0.1.x` support branch with the selected changes while retaining
  the pilot stable compiler (`nightly-2026-09-05-b195f5b`). From support tip
  `c4cf2ff`, review `932a859` followed by the ordered first-parent commits in
  `093a559..FINAL_MAIN` with `cherry-pick -x`. Exclude nightly update `37ac9d3`
  and unrelated automated action upgrades. Preserve both package compiler headers
  and existing published example pins when resolving conflicts. Run the full gate on
  that exact source/compiler combination; development-only success is insufficient.
- Promote the applications in [user time workflows](user-time-workflows.md) and
  verify the starter kit against both immutable package bundles. Keep every
  multi-file application runnable directly using its declared Roc compiler.
- Prepare release notes describing supported standard serialization, the removed
  private archive API, timed iCalendar export/UTC cancellations, and ordinary
  civil text/reporting capabilities. Include compiler information, both package
  URLs, starter download and concrete format limits; avoid broad conformance claims.
- Complete the API-doc asset migration and publication checks in
  [documentation website publication](documentation-site.md). Validate authored
  guide navigation against the selected release APIs and examples.

## Acceptance

The reviewed release source passes its full gate with the selected support-line
compiler; examples and starter run against exact candidate bundles. Documentation
and release notes describe the same APIs and limits. Generated API pages remain
release artifacts, with historical URLs preserved. Release publication is a
separate irreversible step after these reviewable deliverables are ready.

Remove this plan when release preparation and its verification are complete.
