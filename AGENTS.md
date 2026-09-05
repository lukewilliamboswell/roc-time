# Working on roc-time

## Sources of truth

- Read [design.md](design.md) before changing temporal behavior or public APIs. Its requirements R01–R16 are architectural contracts.
- If an active project or task has a plan under `planning/`, read it before working on that scope. Plans do not silently override the design.
- This file contains methodology and guardrails. README introduces the project. Keep each document focused on that role.
- Use the compiler pinned by `.roc-version`; `ROC` can select its executable for repository scripts. Verify `roc version` rather than assuming the executable on PATH matches.
- Keep disposable binaries, downloaded sources, generated probes, and raw exploratory outputs under ignored `.roc-time-tmp/`. Preserve durable decisions in the design and reproducible checks in tests or tooling; do not require ignored files to understand a decision.

## Method

1. Identify the affected requirement IDs and a realistic caller scenario. State input domain, successful result, failure cases, range, and expected cost before implementing.
2. Try to break the proposal. Include a smallest counterexample involving an endpoint, an ambiguous interpretation, sharing/allocation, or a limit as appropriate. Resolve material findings in the design or implementation; record outstanding task-specific findings in an existing plan when useful.
3. Implement a vertical slice through the real package. Validate public construction once, then preserve invariants internally. Avoid a second interpretation engine for a new parser or adapter.
4. Add meaningful executable evidence: a scenario fixture, an algebraic property, an independent reference model, or a compile-failure case. Tests that only restate the implementation are insufficient for semantic claims.
5. Run the relevant checks, then report exact commands, results, limitations, and remaining questions. Update an existing task plan when relevant. Mark work complete only when its acceptance criteria are met.

Resolve routine engineering choices within the authorized task. These rules do not introduce an approval step for ordinary edits. If a design contract needs to change, update the design and explain the semantic consequence alongside the implementation rather than silently weakening it.

## Discrete project plans

Use `planning/` only for a concrete project or task that benefits from a written plan. Do not create it for generic checklists, architecture summaries, broad future roadmaps, or transcripts of completed reviews. Small changes do not require a plan.

Use a descriptive filename without a number prefix. A useful plan states the objective, scope, dependencies, specific unresolved decisions, deliverables, and completion criteria. Include implementation detail or evidence only when it helps finish that task; link to design requirements instead of duplicating them.

At completion, move enduring decisions into `design.md` and useful verification into tests or tooling. Remove the plan when it no longer adds value. Retain a completed plan only if it contains substantive implementation rationale that remains useful and is not recorded elsewhere. Do not create an empty directory or placeholder index just to preserve this convention.

## Semantic guardrails

- Use the chosen signed I64 microsecond representation for resolved boundaries and elapsed quantities; default to 64-bit machines. Keep nominal domain distinctions. Reject sub-microsecond input by default; require explicit rounding for precision reduction. No floating-point endpoints, silent overflow, hidden precision reduction, or integer infinity sentinels.
- Keep coordinate domains, calendar quantities, elapsed quantities, events, and coverage distinct. Do not use structural/raw numeric equality where the domain contract requires extent or identity comparison.
- Do not silently assume UTC, use the machine's zone, replace an unsupported calendar with Gregorian, choose a fold occurrence, or convert incomplete evaluation into an empty success.
- Do not resolve arbitrary civil selections by taking their earliest and latest endpoints. Preserve disconnected coverage and distinguish selection from appointment semantics.
- Keep interpretation context explicit and immutable. No implicit clock reads, network calls, global provider registry, or unbounded cache in the core.
- Preserve recurring-series state across query windows and resumptions. Clamped calendar addition is not an implementation of RFC recurrence rules.
- Public malformed data returns structured errors. Do not hide failures with invented dates, default spans, catch-all empty results, or unchecked casts. Use internal unchecked operations only under documented, tested invariants.
- Unsupported feature scopes remain explicit. Do not claim all of ISO, EDTF, RRULE, leap-aware time, or Allen reasoning based on a narrower implementation.

## Examples and evidence

- Label future API snippets as proposed. Formatting/parsing acceptance proves syntax only. Stubs or mocks of the intended library do not prove that a usage works.
- When a feature lands, promote its design scenario to an executable example or test using the actual public modules. Keep documentation and implementation synchronized.
- Use fixed zone/calendar fixtures with provenance. Include synthetic transition fixtures for edge cases; do not depend on the host's current database.
- Use Tempo as a source of ideas and differential cases, not the sole correctness oracle. Retain credit to Kip Cole and contributors. Record upstream file/revision and applicable notices when adapting implementation code.
- For compile-failure tests, check the intended diagnostic; a failure caused by an unrelated missing import is not evidence of domain safety.

## Performance discipline

- Measure construction, interpretation, core computation, and formatting separately, as well as end to end. Report compiler, backend, target, workload, ownership/sharing, warmup, samples, and observable outputs.
- Measure allocations and retained memory separately from time and process RSS. Inspect generated layout or instrument the platform before claiming exact record size or zero allocations.
- Vary input sizes and distributions to test complexity. Include owned/shared lists and retained slices. Preserve correctness checks while optimizing the chosen I64 implementation.
- Optimize only demonstrated costs. Do not add unsafe conversions, implicit caches, bespoke indexes, or compiler workarounds to improve a benchmark while changing its semantics.
- Investigate compiler defects with a minimal reproduction and report the affected task and limitation. Do not disguise an unsupported backend as a passing portability result.

## Verification and handoff

For code changes, run the affected module's `roc check`/`roc test` and executable examples with the pinned compiler. Before handing off changes that affect package integration, run `ROC=/path/to/pinned/roc python3 scripts/all_tests.py`. A failed environmental step remains unverified until rerun successfully; report it accurately.

For documentation-only changes, review contracts and examples, check local links and Mermaid structure, and use the pinned formatter to validate new Roc sketch syntax. Do not run unrelated benchmarks or claim unimplemented sketches were typechecked. Keep unresolved API choices explicit; do not fill the package with scaffolding to make documentation appear executable.

Keep changes scoped. Do not commit, publish, or contact upstream contributors unless requested. A final handoff states what changed, what was verified, and which material questions remain open.
