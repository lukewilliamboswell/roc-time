# Implement the temporal design

Objective: satisfy [design requirements R01–R16](../design.md#acceptance-requirements) through the real public package. This plan tracks unfinished work; completed work is recorded in Git and executable evidence.

## Remaining deliverables and dependencies

The next adoption target is an application that accepts ordinary date/time input,
calculates deadlines and local appointments, displays and stores results, and
finds availability. Scheduling and faithful partial dates build on that path.
Prioritize these complete workflows before widening specialist standards scope;
ordinary timestamp callers should not need the uncertainty or recurrence layers.
Keep the exact core, checked failures, explicit interpretation and microsecond
contract. Prefer composition through existing public operations; add convenience
APIs where a realistic caller otherwise has to reproduce temporal logic.

1. **Publish the everyday workflows already implemented (R16).** Follow
   [user time workflows](user-time-workflows.md) to deliver the staged civil
   text/display, civil reporting and named-zone applications with compatible compiler and immutable
   package URLs. Publication is separate from implementation acceptance; users
   of the current release cannot yet use these development APIs.
2. **Finish schedule interchange (R11–R12/R14).** Follow
   [recurrence execution](recurrence.md) to carry the existing profile through
   parse/construct, canonical export, save/load and bounded evaluation. Preserve
   series state across windows and resumptions. Widen import from sourced calendar
   workflows, including mixed-form exceptions where required; full ICS ingestion
   is a separate scope from extracted recurrence properties.

Release and resource evidence applies throughout this sequence. Keep public
examples runnable with their declared compiler and immutable package URLs,
including both core and zone data when needed. Measure provider acquisition,
construction and retained memory separately; establish each advertised backend's
execution evidence. Required checks belong to the changed slice, not a later
cleanup milestone. A passing narrow profile does not complete R01–R16.

## Deferred deliverables

These remain required unfinished work for the design objective. Bring a slice
forward when a concrete caller is blocked by it; broad feature parity with other
libraries is not sufficient justification.

- Extend [standards interchange](standards-interchange.md) and
  [calendar descriptions and uncertainty](calendar-descriptions.md) with selected
  EDTF endpoints, unknown/open bounds, masks and sets (R13–R14). Deliver faithful
  parsing, canonical serialization, explanation and persistence together. Never
  substitute year starts for uncertain endpoints or unsupported reasoning for a
  successful answer. Preserve the broader symbolic obligations in those plans.
- Extend calendar presentation and conversion for a sourced caller scenario
  (R06). Settle stable month identity and provider capabilities before calendars
  beyond the Gregorian/Julian shape; preserve unsupported presentation requests.
- Extend remaining bounded explanations, styled rendering and broader reasoning
  (R12–R14) after the ordinary workflows and schedule interchange are usable.
  Use shared typed facts and immutable interpretation snapshots; keep native
  persistence separate from interchange. Full localization and relative-language
  formatting require a selected caller and explicit data/rendering scope.
- Complete the remaining public examples and provider/resource/backend evidence
  across all requirements (R15–R16), including the obligations below. This does
  not defer verification needed to accept an earlier feature.

Use the [contributor verification workflow](../CONTRIBUTING.md#tests) and [oracle method](../AGENTS.md#oracle-evidence) for each slice. Do not change the architecture merely to record implementation progress.

## Zone database decisions and acceptance

- Measure remaining provider construction, retained runtime data and supported Wasm costs for core-only, static one-zone, dynamic global-name and generated-subset workloads. Establish whether entirely unused URL dependencies are acquired; source and binary elimination are separate concerns.
- If introducing subset packs, state their selection profile and distinguish omitted names from unknown identifiers. Do not imply subset support through an undocumented filter.

## Outstanding evidence and external inputs

- Full ISO normative clauses are needed for clause-level conformance claims; catalogue summaries and Tempo support claims are insufficient. Independently specified foundations can proceed without them.
- Select exact RFC adapter, persistence and reasoning profiles before exposing those APIs. Unsupported scopes must remain explicit.
- Verify scheduled fuzz execution from actual workflow runs. Establish supported Wasm execution separately.
- Measure complexity, allocations, final layouts and retained slices on the pinned compiler. Current functional evidence does not establish those resource claims.
- Extend hosted resource gates with coordinate-extent-independent span operations; member-count scaling for coverage and events; bounded zone selection and inspection. Separate construction from consumption, include early-stop/resume and failing controls in dev/speed builds, and instrument live/peak requested bytes before making retained-memory claims.
- Retain the compiler reproduction under `tests/compiler_repro/result_widening/` until the pinned interpreter supports the affected error propagation; validate before removing the explicit mapping in calendar arithmetic.

Completion requires executable evidence for every acceptance requirement, usable public examples and the declared platform/resource evidence. Remove this plan when those deliverables are complete.
