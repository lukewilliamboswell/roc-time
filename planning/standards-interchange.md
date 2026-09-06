# Standards interchange through caller scenarios

Objective: carry useful Tempo-inspired applications through text input, validated
native meaning, explicit interpretation, computation and canonical text output.
Then explain and persist those same values. Follow R01–R02, R06–R09 and R12–R16
in [the design](../design.md); this project does not require completing every
reasoning model or declaring full ISO/EDTF conformance first.

## Remaining caller slices

1. **Richer archive descriptions:** support individually/group-qualified
   components, independently resolved interval endpoints, unknown versus open
   bounds, then selected masks and finite one-of/all-of sets. Specify group
   qualification representation before promising lossless native round trips.
   Preserve metadata without needing a complete uncertainty solver. Interpretation
   uses shared native machinery or returns an explicit unsupported result.
2. **Explain and save:** extend shared facts and bounded explanation to remaining
   value kinds, especially exact intervals, RFC declarations and bound selection
   results. Preserve distinct unresolved, unsupported, empty and limited outcomes
   without re-resolution. Add explicit styled rendering over the same facts.
   Extend native persistence to interpretation snapshots.
   Snapshot persistence must bind actual immutable interpretation data and
   policies, not only provider names/version labels. Preserve qualifiers and
   native calendar/resolution distinctions outside the text adapter profiles.
3. **Calendar presentation:** choose the first additional provider from a sourced
   Tempo scenario and independent equal-day fixtures. Hebrew presentation is a
   candidate requiring stable leap-month identity and declared capabilities.
   Retaining a calendar annotation can ship before conversion; presentation
   remains explicitly unsupported until its provider exists.

## Acceptance scenarios and independent evidence

Tempo revision `e8a074ed1efed6a0f78b87d900fc4cb0c4156278` supplies caller ideas,
not the sole semantic oracle. Retain credit to Kip Cole and contributors; any
adapted implementation needs exact file/revision and applicable notices.

| Scenario/source | Required observable distinction |
|---|---|
| [Tempo cookbook](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/guides/cookbook.md) | `2026`, `2026-06`, `2026-06-15` retain their supplied resolution. |
| [Tempo qualification tests](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/test/tempo/iso8601/qualification_test.exs) | `1984?`, `2004-?06-11`, `2004-06~-11` retain whole, individual and group scope. |
| [Tempo booking tutorial](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/guides/tutorial-booking-availability.md) | Text-in/text-out availability uses actual package coverage operations. |
| [Tempo round-trip fixtures](https://github.com/elixir-tempo/tempo/blob/e8a074ed1efed6a0f78b87d900fc4cb0c4156278/test/tempo/iso8601/round_trip_test.exs) | One-of square brackets remain distinct from all-of braces. |
| [LOC EDTF specification](https://www.loc.gov/standards/datetime/) | `1964/2008` does not invent exact year-start endpoints; `1985/` differs from `1985/..`. |
| [RFC 9557 §§2–5](https://www.rfc-editor.org/rfc/rfc9557.html) | `2022-07-08T00:14:07Z[Europe/Paris]` projects to 02:14:07 under fixed fixture rules; asserted `+00:00` conflicts. Calendar annotations select presentation. |

Before implementation, pin reviewed source expectations and their provenance in
versioned fixtures. Separate sourced examples from independently modeled
extensions. Pair semantic round trips and canonical idempotence with independent
expected fields, resolution, qualification and resolved boundaries. Include
invalid leap days, partial prefixes, unsupported precision, signed/provider
limits, annotation conflicts and byte-limit boundaries. `.12` and `.120` must
remain distinct when supplied resolution is meaningful.

Extend narrow roc-fuzz targets through public APIs, replay curated cases and run
finite campaigns. Check intended compile-failure diagnostics and executable
examples locally and from the distributable bundle. Measure parsing, formatting
and bounded explanation separately from interpretation; include failing controls
for resource assertions. Use the pinned compiler and normal integration gate.

Full ISO normative clauses remain an external dependency for broader conformance
claims, not for the independently specified RFC and LOC feature profiles.
Long/exponential years, seasons, significant digits, arbitrary precision and
general uncertain-interval reasoning remain explicitly scoped follow-ups.
Remove each deliverable when its executable acceptance is established; delete
this plan when the caller slices are complete.
