# Integrate PRs and upgrade the compiler and fuzz platform

Objective: integrate PRs #56–#58, use Roc nightly-2026-11-18-a520eed for
packages and pinned automation, adopt roc-fuzz 0.7.0 suites, and resolve #55
with verified published examples. Preserve design requirements R01–R16.

## Remaining acceptance

- Finish native builds of all three suites, replay every curated witness and
  run each property with seed 1, 100 runs and one second. Verify failure
  lifecycle, minimization, member selection and changed/missing baseline controls.
- Review allocation observations for the new compiler/platform/suite layout.
  Refresh only reviewed host/profile entries; retain raw evidence in ignored
  temporary storage. A passing process without matched baseline evidence is
  insufficient for the normal gate.
- Complete `blueprint run check`, affected public examples, release dry run,
  archive replay and documentation checks. Local Nix setup has encountered
  insufficient disk space; direct source checks do not replace the full gate.
- Create the integration PR, fix its Linux CI failures, and verify all required
  checks at the final commit before merging the original PRs.
- Publish a compatible release after verified integration, rerun the published
  nightly compatibility workflow, and close #55 only with passing release evidence.

The approved metadata aliases are temporarily promoted one level because this
compiler cannot resolve nested types beneath aliases. Keep restoration TODOs
linked to roc-lang/roc#11464 and the nominal-layout TODOs linked to #13077.
The new compiler also requires format-owned codec errors; direct temporal
parsers retain detailed validation errors. Verify both paths through the real
public package, including nested JSON records/lists and an independent encoding.

Remove this plan when the integration and published compatibility work is complete.
