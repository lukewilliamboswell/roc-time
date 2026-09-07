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

1. **Complete checked civil text input and canonical output (R02/R14/R16).**
   A booking form accepts `2026-09-07`, `09:30` and `2026-09-07T09:30` through
   declared date, clock and local-datetime profiles alongside offset timestamps.
   Invalid dates and unsupported forms fail explicitly; local input never acquires
   an implicit zone. Complete the in-flight civil codecs, literal/generic codec
   integration and real application evidence before claiming this path ready.
   Boundary labels need not preserve textual resolution; callers importing partial
   or qualified descriptions must retain that meaning through the description
   APIs. Parsing and canonical serialization ship together through native validation.
2. **Provide ordinary presentation (R14/R16).** Follow
   [civil ergonomics](civil-ergonomics.md). A caller can display a due date
   or local appointment without implementing zero-padding and field assembly.
   Start with canonical output and a small explicit formatting surface for forms
   such as `7 Sep 2026, 09:30`. Select and document the supported fields, language
   and precision policy before exposing it. Formatting a date does not require
   zone resolution; formatting a resolved position requires a chosen context.
   This is ordinary application output, distinct from styled semantic explanations
   and a comprehensive locale dataset.
3. **Complete the named-zone appointment workflow (R05/R07/R09/R16).** Follow
   [user time workflows](user-time-workflows.md). From a
   published data dependency, parse a local appointment, show repeated-time
   alternatives, apply an explicit occurrence policy, advance one civil day while
   preserving the clock label, and display the result in a second named zone.
   Cover a gap, fold and provider-horizon failure with fixed rules. Advancing a
   civil day must remain distinct from adding 24 coordinate hours; appointment
   boundaries must remain distinct from a whole local-day selection. Reuse the
   current data adapter and resolver rather than adding an implicit registry.
4. **Connect clocks, numeric epochs and application records (R01/R02/R14/R16).**
   Complete the integration path in [user time workflows](user-time-workflows.md).
   Demonstrate a real supported platform clock reading converted to a boundary,
   an expiry comparison and a timestamp inside an encoded application record.
   Use a JSON codec where a supported integration is available; keep any missing
   platform/codec dependency explicit. If the chosen platform supplies integer
   milliseconds, provide checked conversion without caller-written overflowing
   multiplication. Document how the six-digit
   text profile interacts with nanosecond-producing services; add an explicitly
   rounded text adapter only for a demonstrated integration. Clock acquisition,
   timers and monotonic measurements remain platform responsibilities.
5. **Expose common civil queries (R05/R07/R16).** Follow
   [civil ergonomics](civil-ergonomics.md). An invoice/reporting caller can
   obtain a weekday, ordinal day and ISO week date,
   without constructing a recurrence or copying private calendar calculations.
   Define week-year boundaries, then verify independently. Add further helpers
   such as next-weekday or day/month selections when a concrete application needs
   them; selections must preserve exclusive ends, skipped dates and disconnected
   zoned coverage.
6. **Finish schedule interchange (R11–R12/R14).** Follow
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
