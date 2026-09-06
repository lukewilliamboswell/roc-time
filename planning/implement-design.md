# Implement the temporal design

Objective: satisfy [design requirements R01–R16](../design.md#acceptance-requirements) through the real public package. This plan tracks unfinished work; completed work is recorded in Git and executable evidence.

## Remaining deliverables and dependencies

The immediate critical path is [standards interchange](standards-interchange.md):
usable text input, shared native operations, canonical text output, explanation
and persistence for the same caller scenarios. Deliver parsing and serialization
together. Extend native foundations only when a selected scenario needs them;
general uncertainty reasoning and provider-wide measurements do not block the
first bounded adapters. Each slice still requires its own correctness and
resource evidence.

1. Implement bounded date-description and offset-timestamp profiles, then exact
   interval booking input/output and IXDTF annotations (R01–R02, R07–R09, R14–R16).
2. Extend [calendar descriptions and uncertainty](calendar-descriptions.md) for
   selected EDTF endpoint, qualification, mask and set forms (R13–R14). Preserve
   descriptions before implementing broader interpretation; never substitute
   year starts for uncertain endpoints or treat unsupported reasoning as success.
3. Add bounded semantic explanation and versioned persistence alongside these
   adapters, using shared typed facts and explicit interpretation snapshots.
   Keep standards interchange separate from the native persistence format.
4. Extend calendar presentation and conversion for a sourced caller scenario.
   Separate stable month identity and provider capabilities before calendars
   beyond the Gregorian/Julian shape; preserve unsupported presentation requests.
5. Complete remaining [recurrence execution](recurrence.md), provider evidence
   and broader reasoning. Preserve series state across windows and resumptions.
   Bring a deliverable forward when a selected interchange scenario needs it.
6. Complete public examples and evidence across all requirements, including
   resource measurements and supported backend checks (R15–R16).

Use the [contributor verification workflow](../CONTRIBUTING.md#tests) and [oracle method](../AGENTS.md#oracle-evidence) for each slice. Do not change the architecture merely to record implementation progress.

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
