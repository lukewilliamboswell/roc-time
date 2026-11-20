# Hosted integration and published nightly compatibility

Verify the shared automation migration and the published package on the
floating Roc nightly. Follow R01–R16 in [the design](../design.md).

## Remaining acceptance

- Run the contributor gate on hosted Linux and the fuzz smoke gate on hosted
  Apple Silicon. Verify compiler admission on a cold hosted run and reuse of
  the verified cache on a warm run.
- Verify the hosted release dry run, including the manual and unchanged replay
  of the examples archive against both transferred bundles.
- After a compatible release is published, run published nightly compatibility.
  Check exact-tag compiler admission separately from archive execution. Close
  #55 with passing published-release evidence.

Remove this plan once the hosted and published compatibility checks pass.
