# Implement the temporal design

Objective: satisfy [design requirements R01–R16](../design.md#acceptance-requirements) through the real public package. This plan tracks unfinished work; completed work is recorded in Git and executable evidence.

## Remaining deliverables and dependencies

1. Finish named-zone distribution and application integration (R07–R09, R16), using the existing structural rule adapter. Select the optional companion's encoding and data profile using the measurements below.
2. Add events, explicit coverage projection and contributor-preserving splitting (R10), building on canonical coverage and immutable interpretation snapshots.
3. Add stateful recurrence, a declared RFC profile, candidate/output budgets and resumptions (R11–R12). Preserve series state across windows; depend on calendar and zone interpretation rather than duplicating them.
4. Add resolution-bearing descriptions, uncertain endpoint knowledge and component qualifications before standards adapters (R13–R14). Keep symbolic range distinct from finite materialization. Separate stable month identity and provider capabilities before extending beyond Gregorian/Julian calendar shapes.
5. Implement shared semantic adapters and versioned persistence, including IXDTF offset assertions and presentation annotations. Declare edition/profile support separately for recognition, semantic preservation, interpretation and serialization.
6. Implement bounded semantic explanation using shared typed facts, preserving the design's masked-year, uncertain-endpoint, fold/skip, missing-context and limited-result distinctions. Extend inspection budgets to nested descriptions and embedded text.
7. Complete public examples and evidence across all requirements, including resource measurements and supported backend checks (R15–R16).

Use the [contributor verification workflow](../CONTRIBUTING.md#tests) and [oracle method](../AGENTS.md#oracle-evidence) for each slice. Do not change the architecture merely to record implementation progress.

## Zone database decisions and acceptance

- Compare generated Roc tables/columns with compact TZif ingestion. Keep the companion independent of nominal core types and use the existing versioned structural adaptation boundary.
- Measure core-only, static one-zone, dynamic global-name and generated-subset applications. Separate archive/source bytes, compiler time and peak memory, native/supported Wasm binary size, construction cost and retained runtime data. Establish whether unused dependency declarations are fetched and whether unused data is eliminated; neither is assumed.
- Compare full transition-record literals with columns converted at the adapter boundary using the generated provider workload; include actual construction and compiler costs before selecting its final encoding.
- Select the historical inclusion profile, aliases, future-rule representation, validity horizon and finite expansion budgets. Verify footer and truncation handling rather than extrapolating the final explicit offset.
- Add provider lookup, unknown-zone/subset errors, alias and horizon checks, malformed-data cases and independent reference comparisons. Show ordinary companion usage and application-supplied replacement in realistic examples, including explicit upgrades with unchanged prior snapshots.
- Pin source/generator/build profiles and notices; provide reproducible artifacts and a contributor update workflow. Source byte measurements are reproducible with `scripts/measure_zone_data.py`; results need not be copied into this plan.

## Outstanding evidence and external inputs

- Full ISO normative clauses are needed for clause-level conformance claims; catalogue summaries and Tempo support claims are insufficient. Independently specified foundations can proceed without them.
- Select exact RFC adapter, persistence and reasoning profiles before exposing those APIs. Unsupported scopes must remain explicit.
- Verify Linux x86-64/musl runtime and scheduled fuzz execution; these have not been verified locally. Establish supported Wasm execution separately.
- Measure complexity, allocations, final layouts and retained slices on the pinned compiler. Current functional evidence does not establish those resource claims.
- Retain the compiler reproduction under `tests/compiler_repro/result_widening/` until the pinned interpreter supports the affected error propagation; validate before removing the explicit mapping in calendar arithmetic.

Completion requires executable evidence for every acceptance requirement, usable public examples and the declared platform/resource evidence. Remove this plan when those deliverables are complete.
