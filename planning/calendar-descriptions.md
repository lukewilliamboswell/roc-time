# Calendar descriptions and uncertainty

Extend the description foundations in R02, R07 and R13–R14 as required by the
selected [standards interchange slices](standards-interchange.md). Reuse validated
calendars, local selections and zone cursors. Existing native forms can receive
parsers and serializers without waiting for every symbolic reasoning model.

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

## Civil endpoint integration

Introduce endpoint knowledge separately from interval materialization. Each side
must retain a known resolution-bearing description, an unknown endpoint, or an
explicit unbounded endpoint. Exact resolved endpoints are a different case from
an endpoint lying somewhere within a calendar selection. CalendarValue's lower
boundary is not an inferred actual endpoint.

- Preserve each endpoint's original resolution and qualifiers through explicit
  calendar/zone interpretation. A year start and a month end are independent
  domains, potentially with disconnected fold preimages. Unknown endpoints need
  supplied evidence; unbounded endpoints need operations that explicitly support
  them or explicit finite bounds.
- Bridge to interval reasoning without enumerating every microsecond in a civil
  endpoint domain. IntervalEvidence's finite boundary-list inputs do not by
  themselves represent all possible endpoints within a year or month. Extend the
  domain representation and prove its quantified semantics before that lowering.
- Keep paired and independent intent explicit during interpretation. Do not
  introduce cross-pair combinations or lose correlations retained by the native
  resolved model. Establish satisfiability under explicit work limits before
  returning complete reasoning outcomes.
- Include mixed year/month resolution, signed I64 limits, gaps/folds, budget
  exhaustion and retained resumptions, comparing with exhaustive small models.
  General interval relationships need their own supported profile and oracle;
  point-membership evidence does not establish Allen reasoning over uncertainty.

Endpoint interchange first needs faithful public construction and serialization.
It can preserve unknown/open bounds and independently qualified resolutions
while returning explicit unsupported interpretation. Broader quantified civil
endpoint reasoning is deferred until a selected caller needs it; syntax support
must not advertise that reasoning as implemented.
