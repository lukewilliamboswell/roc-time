# Implement the temporal design

Objective: satisfy [design requirements R01–R16](../design.md#acceptance-requirements) through the real public package. This plan tracks unfinished work; completed work is recorded in Git and executable evidence.

## Remaining deliverables and dependencies

1. Complete remaining provider resource/portability evidence (R07–R09, R15–R16).
2. Complete [recurrence execution](recurrence.md), a declared RFC profile, candidate/output budgets and resumptions (R11–R12). Preserve series state across windows; depend on calendar and zone interpretation rather than duplicating them.
3. Add resolution-bearing descriptions, uncertain endpoint knowledge and component qualifications before standards adapters (R13–R14). Keep symbolic range distinct from finite materialization. Separate stable month identity and provider capabilities before extending beyond Gregorian/Julian calendar shapes.
4. Implement shared semantic adapters and versioned persistence, including IXDTF offset assertions and presentation annotations. Declare edition/profile support separately for recognition, semantic preservation, interpretation and serialization.
5. Implement bounded semantic explanation using shared typed facts, preserving the design's masked-year, uncertain-endpoint, fold/skip, missing-context and limited-result distinctions. Extend inspection budgets to nested descriptions and embedded text.
6. Complete public examples and evidence across all requirements, including resource measurements and supported backend checks (R15–R16).

Use the [contributor verification workflow](../CONTRIBUTING.md#tests) and [oracle method](../AGENTS.md#oracle-evidence) for each slice. Do not change the architecture merely to record implementation progress.

## Zone database decisions and acceptance

- Measure remaining provider construction, retained runtime data and supported Wasm costs for core-only, static one-zone, dynamic global-name and generated-subset workloads. Establish whether entirely unused URL dependencies are acquired; source and binary elimination are separate concerns.
- If introducing subset packs, state their selection profile and distinguish omitted names from unknown identifiers. Do not imply subset support through an undocumented filter.

## Outstanding evidence and external inputs

- Full ISO normative clauses are needed for clause-level conformance claims; catalogue summaries and Tempo support claims are insufficient. Independently specified foundations can proceed without them.
- Select exact RFC adapter, persistence and reasoning profiles before exposing those APIs. Unsupported scopes must remain explicit.
- Verify Linux x86-64/musl runtime and scheduled fuzz execution; these have not been verified locally. Establish supported Wasm execution separately.
- Measure complexity, allocations, final layouts and retained slices on the pinned compiler. Current functional evidence does not establish those resource claims.
- Retain the compiler reproduction under `tests/compiler_repro/result_widening/` until the pinned interpreter supports the affected error propagation; validate before removing the explicit mapping in calendar arithmetic.

Completion requires executable evidence for every acceptance requirement, usable public examples and the declared platform/resource evidence. Remove this plan when those deliverables are complete.
