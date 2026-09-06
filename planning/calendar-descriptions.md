# Calendar descriptions and uncertainty

Implement the description foundations in R02, R07 and R13–R14 before adding
EDTF/ISO adapters. Reuse validated calendars, local selections and zone cursors.

## Deliverables

- Extend admissible models beyond finite, same-resolution calendar alternatives
  when required by supported symbolic forms. Preserve component scope without
  inferred numeric tolerances and endpoint knowledge separately from open bounds.
- Interval descriptions with independent endpoint resolution, plus distinct
  alternatives and all-of selections. Define supported reasoning models and
  compare definite/possible/impossible results with small independent models.
- Explicit symbolic ranges beyond numerical providers, including long years,
  masks and finer fractions; do not silently coerce them into kernel endpoints.
- Extend caller examples, property-based tests, independent expectations,
  malformed-input evidence and interpretation resource checks with each form.

## Decisions and acceptance

Broader symbolic forms must coexist with CalendarValue’s finite Gregorian/Julian
profile without silently reducing them to its provider range or six fractional
digits. Validate a description without requiring its exclusive upper boundary
to fit. Lowering must fail rather than shorten selections at provider
or POSIX limits. Month/year bounds use the selected calendar and never a fixed
elapsed duration. Starting labels used internally are canonical selection bounds,
not evidence that omitted fields were supplied by the caller.

Qualifications remain descriptive until a caller supplies a supported model.
Extend CalendarEvidence’s finite point-membership model only with explicit
semantic intersections; do not treat calendar selections as uncertain instants
or infer correlations between independently supplied endpoint alternatives.
Do not use a parser-specific evaluation engine or claim EDTF/ISO conformance from
native construction. Delete completed deliverables as acceptance is established.

## Next interval slice

Introduce endpoint knowledge separately from interval materialization. Each side
must retain a known resolution-bearing description, an unknown endpoint, or an
explicit unbounded endpoint. Exact resolved endpoints are a different case from
an endpoint lying somewhere within a calendar selection. CalendarValue's lower
boundary is not an inferred actual endpoint.

Resolve the initial finite reasoning model before exposing interval queries:

- Independent endpoint domains admit start/end combinations constrained by
  start < end. A correlated model must instead retain explicitly paired choices;
  taking their Cartesian product introduces interpretations the caller excluded.
- Empty admissible sets are inconsistent evidence. Invalid start/end pairs must
  not silently turn the entire model into an empty success, nor be counted as
  evidence against a query. Decide where satisfiability is established and bound
  its work separately from membership evaluation.
- Preserve each endpoint's original resolution and qualifiers through explicit
  calendar/zone interpretation. A year start and a month end are independent
  domains, potentially with disconnected fold preimages. Unknown endpoints need
  supplied evidence; unbounded endpoints need operations that explicitly support
  them or explicit finite bounds.
- Include a small correlation counterexample: paired intervals [0,1) and [2,3)
  make point 1 impossible. Recombining starts {0,2} with ends {1,3} adds [0,3),
  making it possible, and an invalid reversed pair. Verify both model definitions
  independently rather than assuming they are interchangeable.
- Include overlapping endpoint domains, mixed year/month resolution, empty and
  reversed bounds, signed I64 limits, gaps/folds, budget exhaustion and retained
  resumptions. Compare reasoning against exhaustive small admissible models.

The next vertical slice should carry one of these declared models through real
public construction and a bounded query before adding interval interchange.
