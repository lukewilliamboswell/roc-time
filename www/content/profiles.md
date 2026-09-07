# Know the supported scope

A format name is not a promise to implement its entire standard. Match the exact profile and operation to your input: parsing a description does not necessarily resolve it, enumerate it or preserve its original spelling.

## Match the profile to your input

| Area | Supported direction | Boundary to keep visible |
| --- | --- | --- |
| Exact values | Offset timestamps, nonempty half-open spans and coverage | Signed I64 microseconds; no silent overflow or precision reduction |
| Calendars | Gregorian and Julian dates and explicit calendar arithmetic | Proleptic rules; no inferred historical reform or unsupported-calendar fallback |
| Named zones | Optional IANA zone-data package | Interpretation requires complete immutable data within its declared validity |
| Timestamp/interval text | Declared offset timestamp and exact interval profiles | Explicit offset; no leap-second or sub-microsecond acceptance in these profiles |
| EDTF | Declared date-description forms retaining meaningful precision and qualification | Not all ISO 8601-2 or every EDTF level; consult the module’s actual profile |
| IXDTF | Declared annotations/assertions and explicit interpretation | Unknown critical extensions fail; zone and offset assertions remain distinct |
| Recurrence | Declared extracted RFC 5545 DATE/DATE-TIME profiles | No general ICS reader; RFC rules differ from repeated clamped arithmetic |
| Explanation | Bounded semantic facts and supported contextual explanations | Inspection text and prose are not persistence formats |
| Standard text storage | Store supported timestamp and date-description text using its parser and serializer | A standard declaration does not embed every native interpretation choice or immutable zone table |

For precise accepted grammar, field limits and error types, follow the version-specific [API map](api.html). There is deliberately no single “ISO compliant” badge.

## Failure is part of the interface

Malformed, unsupported, out-of-range and incomplete inputs require different responses. A user can fix malformed spelling; a valid unsupported calendar needs a different capability. A bounded query that ran out of work is not an empty success.

The core never reads the clock, consults a machine timezone, fetches a database or chooses a fold occurrence on your behalf. Applications supply effects and interpretation context explicitly. Adapters may define their own documented standard-specific policies.

## What is outside these guides?

General ICS processing, wider calendar providers, leap-aware time and complete ISO/EDTF/RRULE coverage need separate declared support. The [design](https://github.com/lukewilliamboswell/roc-time/blob/main/design.md) describes the intended architecture; it is not a list of features included in your selected package.
