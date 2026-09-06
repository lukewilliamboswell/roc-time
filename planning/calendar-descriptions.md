# Calendar descriptions and uncertainty

Implement the description foundations in R02, R07 and R13–R14 before adding
EDTF/ISO adapters. Reuse validated calendars, local selections and zone cursors.

## Deliverables

- Supply explicit admissible models for qualified values; preserve component
  scope without inferred numeric tolerances. Preserve endpoint knowledge
  separately from open-ended bounds.
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

Qualifications must remain descriptive until a caller supplies a supported
admissible model. Select that model explicitly before exposing reasoning APIs.
Do not use a parser-specific evaluation engine or claim EDTF/ISO conformance from
native construction. Delete completed deliverables as acceptance is established.
