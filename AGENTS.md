# Working on roc-time

## Sources of truth

- Read [design.md](design.md) before changing temporal behavior or public APIs. Its requirements R01–R16 are architectural contracts.
- If an active project or task has a plan under `planning/`, read it before working on that scope. Plans do not silently override the design.
- `design.md` is the enduring ideal architecture, not an implementation tracker. Edit it only for a new or changed requirement, an invalidated assumption, or a necessary clarification of an architectural contract. State that reason when changing it. Landing a feature, choosing an internal algorithm, passing tests or collecting measurements does not by itself justify a design edit. Keep API details in module documentation, workflows in CONTRIBUTING.md, and reproducible evidence in tests/tooling.
- Completed-work history belongs in Git commits. Do not duplicate commit narratives, test-run logs, milestone inventories or benchmark transcripts in the design or plans. Active plans retain only unfinished deliverables, dependencies, unresolved decisions and information needed to finish them; delete obsolete entries rather than moving them to another document.
- This file contains methodology and guardrails. CONTRIBUTING.md provides contributor setup and workflows. README introduces package capabilities and usage. Keep each document focused on that role.
- Use the compiler pinned by `.roc-version`; `ROC` can select its executable for repository scripts. Verify `roc version` rather than assuming the executable on PATH matches.
- Keep disposable binaries, downloaded sources, generated probes, and raw exploratory outputs under ignored `.roc-time-tmp/`. Preserve architectural contracts in the design and reproducible checks in tests or tooling; do not require ignored files to understand a decision.

## Method

1. Identify the affected requirement IDs and a realistic caller scenario. State input domain, successful result, failure cases, range, and expected cost before implementing.
2. Try to break the proposal. Include a smallest counterexample involving an endpoint, an ambiguous interpretation, sharing/allocation, or a limit as appropriate. Resolve material findings in the design or implementation; record outstanding task-specific findings in an existing plan when useful.
3. Implement a vertical slice through the real package. Validate public construction once, then preserve invariants internally. Avoid a second interpretation engine for a new parser or adapter.
4. Add meaningful executable evidence using the property-based testing method below, alongside scenario fixtures and compile-failure cases as applicable. Tests that only restate the implementation are insufficient for semantic claims.
5. Run the relevant checks, then report exact commands, results, limitations, and remaining questions. Update an existing task plan when relevant. Mark work complete only when its acceptance criteria are met.

Resolve routine engineering choices within the authorized task. These rules do not introduce an approval step for ordinary edits. If a design contract needs to change, update the design and explain the semantic consequence alongside the implementation rather than silently weakening it.

## Discrete project plans

Use `planning/` only for a concrete project or task that benefits from a written plan. Do not create it for generic checklists, architecture summaries, broad future roadmaps, or transcripts of completed reviews. Small changes do not require a plan.

Use a descriptive filename without a number prefix. A useful plan states the objective, scope, dependencies, specific unresolved decisions, deliverables, and completion criteria. Include implementation detail or evidence only when it helps finish that task; link to design requirements instead of duplicating them.

At completion, incorporate only newly established architectural contracts into `design.md`; keep useful verification in tests or tooling. Do not migrate implementation history into the design. Remove the plan when it no longer adds value. Completed plans normally disappear; Git retains their history. Put a still-relevant implementation invariant beside its code, rather than retaining a completed plan as a log. Do not create an empty directory or placeholder index just to preserve this convention.

## Semantic guardrails

- Use the chosen signed I64 microsecond representation for resolved boundaries and elapsed quantities; default to 64-bit machines. Keep nominal domain distinctions. Reject sub-microsecond input by default; require explicit rounding for precision reduction. No floating-point endpoints, silent overflow, hidden precision reduction, or integer infinity sentinels.
- Keep coordinate domains, calendar quantities, elapsed quantities, events, and coverage distinct. Do not use structural/raw numeric equality where the domain contract requires extent or identity comparison.
- Do not silently assume UTC, use the machine's zone, replace an unsupported calendar with Gregorian, choose a fold occurrence, or convert incomplete evaluation into an empty success.
- Do not resolve arbitrary civil selections by taking their earliest and latest endpoints. Preserve disconnected coverage and distinguish selection from appointment semantics.
- Keep interpretation context explicit and immutable. No implicit clock reads, network calls, global provider registry, or unbounded cache in the core.
- Preserve recurring-series state across query windows and resumptions. Clamped calendar addition is not an implementation of RFC recurrence rules.
- Public malformed data returns structured errors. Do not hide failures with invented dates, default spans, catch-all empty results, or unchecked casts. Use internal unchecked operations only under documented, tested invariants.
- Review public types against Roc's static-dispatch conventions using the pinned compiler: equality/order, hashing, iteration, inspection and literals where their meaning is defined. Preserve domain distinctions and checked failures; operator convenience must not silently introduce overflow, units, an epoch or a timezone. Literal adapters must use real validated constructors/parsers, and serialization must preserve the semantic format rather than expose opaque backing records.
- Keep `to_inspect` concise, semantic and bounded. Debug inspection must not resolve zones, enumerate recurrences or materialize selections. Detailed explanation uses shared semantic facts with explicit context, work limits and incomplete/unsupported outcomes; neither diagnostic prose nor display formatting is a persistence format. Follow [the design contract](design.md#inspection-explanation-and-presentation).
- Unsupported feature scopes remain explicit. Do not claim all of ISO, EDTF, RRULE, leap-aware time, or Allen reasoning based on a narrower implementation.

## Examples and evidence

- Maintain `examples/` as focused, realistic applications demonstrating public package capabilities from a caller's perspective. Cover the implemented capabilities broadly across the collection while keeping each application centered on one useful task. Prefer clear inputs, meaningful results and ergonomic flow over assertion-heavy demonstrations; test fixtures, exhaustive cases and harnesses belong under `tests/`.
- Give each application its own folder and name its entrypoint `main.roc`, for example `examples/coverage/main.roc`. Put most pure domain logic in a separate capitalized type module; keep the app root focused on inputs, effects and presentation. Use the same layout for test applications so multiple app or test roots can drive pure cores. Type modules expose a matching nominal type and associated items, as described in the [Roc language reference](https://github.com/roc-lang/roc/blob/main/docs/langref/modules.md#type-modules).
- When moving or adding example applications, update recursive discovery, bundle copying, release URL rewriting and documentation links. Verify the multi-file application against both the local package and its distributable bundle.
- Label future API snippets as proposed. Formatting/parsing acceptance proves syntax only. Stubs or mocks of the intended library do not prove that a usage works.
- When a feature lands, promote its design scenario to an executable example or test using the actual public modules. Update user/API documentation as needed; do not annotate the design with implementation status.
- Use fixed zone/calendar fixtures with provenance. Include synthetic transition fixtures for edge cases; do not depend on the host's current database.
- Use Tempo as a source of ideas and differential cases, not the sole correctness oracle. Retain credit to Kip Cole and contributors. Record upstream file/revision and applicable notices when adapting implementation code.
- For compile-failure tests, check the intended diagnostic; a failure caused by an unrelated missing import is not evidence of domain safety.

## Property-based testing

[roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) is the default property-based testing platform for temporal implementation work. For changes to temporal semantics, add or extend a test root under `tests/` through the real public modules. Where generated testing is unsuitable, explain the alternative executable evidence. The platform release URL and integrity metadata are pinned in `tests/fuzz/dependency.json`; each fuzz test must use that exact URL. Update the pin and test declarations together when deliberately upgrading the dependency. `scripts/fuzz.py` is the single runner for builds, replay, bounded searches, and failure-lifecycle checks. See [contributor guide](CONTRIBUTING.md#tests) for commands.

- State the applicable requirement IDs, input domain, property preconditions, and independent oracle or semantic law. Keep targets narrow and deterministic, with explicit interpretation fixtures and bounded input sizes and work.
- Generate useful valid inputs directly and deliberately include signed limits, adjacent endpoints, empty collections, duplicates, and touching/overlapping spans as applicable. Exercise owned, shared, and sliced collections where ownership can affect behavior. Small exhaustive models complement exploration across the full supported range.
- Test malformed public inputs for the required structured errors. Reject a generated input only when it is outside the property's domain; do not discard expected error paths or turn ordinary public errors into harness crashes.
- Check inverse and round-trip preconditions explicitly. Checked arithmetic may overflow in an intermediate step; clamped calendar arithmetic is not invertible; semantic round trips need not preserve source spelling. Pair algebraic laws with independent models or sourced fixtures so mutually consistent bugs can be detected.
- Reproduce and minimize failures, then preserve a readable deterministic regression using public APIs. Retain useful minimized raw inputs with target/generator, compiler, and roc-fuzz revisions needed for replay. Keep disposable campaigns, binaries, downloads, and raw exploratory output under `.roc-time-tmp/`; curated regression inputs and their provenance belong in versioned tests.
- Run affected targets with explicit finite budgets and replay their saved regressions. Record exact commands, revisions, backend/target, seed, budgets, and results. Normal CI must build targets, replay curated regressions, and run bounded searches on supported hosts; longer campaigns supplement that gate, with unfinished automation work tracked in an active plan. Unsupported hosts and failed setup remain explicit limitations.

Fuzzing supplements fixed fixtures, compile-failure checks, public examples, and resource measurements. A passing campaign establishes evidence for its tested properties and budget, not exhaustive correctness, allocation bounds, or portability to untested backends.

## Oracle evidence

Use at least one oracle when adding temporal behavior or changing an algorithm; this is a standing implementation requirement. Extend the working `scripts/oracles.py` gate, an independent bounded reference model, or sourced executable fixtures as appropriate. Establish the intended caller meaning from the design and primary evidence, then compare the public API against independently sourced expectations or a deliberately different bounded model. Round trips and agreement between libraries can preserve the same incorrect interpretation.

- Record what makes each oracle independent, its supported semantic intersection, shared assumptions and remaining gaps. Distinguish sourced facts, external-library outputs and model-derived extensions; never claim an oracle supports a domain it cannot represent.
- Pin source revisions, data, generators and adapters with provenance, integrity hashes and applicable notices. Review expected-result refreshes; never derive or automatically bless expectations from the package under test. Keep normal replay deterministic and independent of the host's clock, zone database or live network data.
- Prefer checked-in JSONL corpora for independently generated case collections. Compile each native fixture once, then let the Python harness validate records, dispatch inputs with bounded parallelism and compare outputs in deterministic corpus order. Pass case inputs, not their expected results, to the native operation under test. Keep small typed Roc scenario fixtures and interpreter smoke tests where useful; fixture encoding is a tooling choice, not a temporal contract. Preserve generators and provenance; ordinary replay does not regenerate data or depend on a reference service.
- Make comparison failures, missing results and setup failures fail visibly. Validate the harness with deliberately wrong results and malformed output. Minimize disagreements without discarding their preconditions, resolve them against the contract rather than majority vote, and preserve readable regressions.
- Treat functional comparisons, compile-time domain safety and measured resource behavior as distinct evidence. Report exact coverage and limitations; implementation work and outstanding harness acceptance belong in the active plan.

## Performance discipline

- Measure construction, interpretation, core computation, and formatting separately, as well as end to end. Report compiler, backend, target, workload, ownership/sharing, warmup, samples, and observable outputs.
- Use the custom test fixture platform for executable allocation assertions and trace marks around observable operations. State counter scope and ownership; allocation/reallocation call counts and cumulative requested bytes are not live or retained memory. Keep runtime inputs and consume outputs so optimization cannot erase the workload. Verify failing assertions: optimized builds can remove `expect`, so use the always-active hosted assertion for optimized resource gates.
- Measure allocations and retained memory separately from time and process RSS. Inspect generated layout or instrument the platform before claiming exact record size or zero allocations.
- Vary input sizes and distributions to test complexity. Include owned/shared lists and retained slices. Preserve correctness checks while optimizing the chosen I64 implementation.
- Optimize only demonstrated costs. Do not add unsafe conversions, implicit caches, bespoke indexes, or compiler workarounds to improve a benchmark while changing its semantics.
- Investigate compiler defects with a minimal reproduction and report the affected task and limitation. Do not disguise an unsupported backend as a passing portability result.

## Verification and handoff

For code changes, run the affected module's `roc check`/`roc test` and executable examples with the pinned compiler. Before handing off changes that affect package integration, run `ROC=/path/to/pinned/roc python3 scripts/all_tests.py`. A failed environmental step remains unverified until rerun successfully; report it accurately.

For documentation-only changes, review contracts and examples, check local links and Mermaid structure, and use the pinned formatter to validate new Roc sketch syntax. Do not run unrelated benchmarks or claim unimplemented sketches were typechecked. Keep unresolved API choices explicit; do not fill the package with scaffolding to make documentation appear executable.

Keep changes scoped. When commits are requested, create clean, coherent commits at verified milestones as work progresses; do not defer all changes to one final commit. Do not commit, publish, or contact upstream contributors unless requested. A final handoff states what changed, what was verified, and which material questions remain open.
