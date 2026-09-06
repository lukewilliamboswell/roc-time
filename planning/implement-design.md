# Implement the temporal design

Objective: satisfy [design requirements R01–R16](../design.md#acceptance-requirements) through the real public package. This plan tracks unfinished work; completed work is recorded in Git and executable evidence.

## Remaining deliverables and dependencies

Prioritize complete caller workflows by user impact: booking/availability and
archive/date import are the first adoption paths. The next adoption work is a
verified first-use path, versioned package distribution with compiler compatibility,
and usable optional zone-data distribution. Prepare and verify release artifacts
before publication; source-only examples do not establish easy package adoption.

Then follow [standards interchange](standards-interchange.md): usable text input,
shared native operations and canonical text output for those callers. Parsing
and serialization land together. Richer archive forms and recurrence export take
priority over styled explanations or additional diagnostic detail. Extend native
foundations when a caller needs them or evidence demonstrates a correctness or
resource problem; retain the required correctness and resource gates for each slice.

1. Prepare usable package adoption: verified versioned core/optional-zone bundles,
   a compatible compiler pin, and first-use examples that work outside this
   checkout. Settle release version and distribution before claiming a released
   package; publication remains a separate external action.
2. Extend [calendar descriptions and uncertainty](calendar-descriptions.md) for
   selected EDTF endpoint, qualification, mask and set forms (R13–R14). Deliver
   parsing, canonical serialization, explanation and persistence for each form.
   Never substitute year starts for uncertain endpoints or treat unsupported
   reasoning as success.
3. Complete schedule interchange and remaining [recurrence execution](recurrence.md).
   Prioritize recurrence export/persistence and imported-calendar caller needs;
   preserve series state across windows and resumptions.
4. Extend calendar presentation and conversion for a sourced caller scenario.
   Separate stable month identity and provider capabilities before calendars
   beyond the Gregorian/Julian shape; preserve unsupported presentation requests.
5. Extend remaining bounded explanations, styled rendering and broader reasoning
   when the preceding caller paths are usable. Use shared typed facts and explicit
   interpretation snapshots; keep native persistence separate from interchange.
6. Complete public examples and evidence across all requirements, including
   provider/resource measurements and supported backend checks (R15–R16).
   Evidence required for a changed feature is part of that feature's acceptance,
   not deferred until this final item.

Use the [contributor verification workflow](../CONTRIBUTING.md#tests) and [oracle method](../AGENTS.md#oracle-evidence) for each slice. Do not change the architecture merely to record implementation progress.

## Adoption acceptance still needed

- Wire the starter ZIP and compiler compatibility metadata into versioned release
  asset preparation and publication; the pinned publishing action accepts package
  archives only. Validate the prepared kit's final role URLs against release
  metadata before publication.
- Exercise the prepared release workflow in CI before claiming release readiness;
  settle the initial release version and publish only with authorization.

## Zone database decisions and acceptance

- Measure remaining provider construction, retained runtime data and supported Wasm costs for core-only, static one-zone, dynamic global-name and generated-subset workloads. Establish whether entirely unused URL dependencies are acquired; source and binary elimination are separate concerns.
- If introducing subset packs, state their selection profile and distinguish omitted names from unknown identifiers. Do not imply subset support through an undocumented filter.

## Outstanding evidence and external inputs

- Full ISO normative clauses are needed for clause-level conformance claims; catalogue summaries and Tempo support claims are insufficient. Independently specified foundations can proceed without them.
- Select exact RFC adapter, persistence and reasoning profiles before exposing those APIs. Unsupported scopes must remain explicit.
- Verify scheduled fuzz execution; no workflow runs are available yet. Establish supported Wasm execution separately.
- Measure complexity, allocations, final layouts and retained slices on the pinned compiler. Current functional evidence does not establish those resource claims.
- Extend hosted resource gates with coordinate-extent-independent span operations; member-count scaling for coverage and events; bounded zone selection and inspection. Separate construction from consumption, include early-stop/resume and failing controls in dev/speed builds, and instrument live/peak requested bytes before making retained-memory claims.
- Retain the compiler reproduction under `tests/compiler_repro/result_widening/` until the pinned interpreter supports the affected error propagation; validate before removing the explicit mapping in calendar arithmetic.

Completion requires executable evidence for every acceptance requirement, usable public examples and the declared platform/resource evidence. Remove this plan when those deliverables are complete.
