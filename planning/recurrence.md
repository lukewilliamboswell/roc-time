# Recurrence execution

Implement R11–R12 through public constructors, bounded cursors and the shared
calendar/zone APIs. This task depends on validated Gregorian dates, clock labels,
finite immutable zone rules and event/coverage distinctions.

## Deliverables

- Date-only series with inclusive date UNTIL, positive COUNT, explicit dates and
  exclusions, ordered deduplication and stable source identity. Reject a DTSTART
  that does not match its rule instead of assigning meaning to the RFC's
  undefined case.
- Local/UTC timed series, subdaily frequencies and time selectors. Reuse calendar
  candidates from CalendarPattern and ZoneRules; handle generated gaps before consuming COUNT.
  BYSETPOS belongs after full candidate generation/interpretation, not in a
  date-only filter reused by timed rules.
- Immutable resumptions carrying rule, query and interpretation inputs. Account
  for examined candidates, buffered candidates and output. Resume must produce
  exactly uninterrupted results; query restriction never restarts series COUNT.
- RFC 5545 text adaptation into the same validated forms, with explicit profile,
  unsupported scopes and UNTIL type checks. No separate parser execution engine.
- Independently generated JSONL cases, RFC examples, synthetic zone transitions,
  bounded fuzz models, invalid-input/domain checks and realistic applications.

## Decisions and acceptance still needed

Use RFC 5545 §§3.3.10 and 3.8.5, with verified errata 1913/3779 for ordinal
BYDAY. All-day calendar candidates can use the full Gregorian provider range;
the text adapter must separately declare its representable year profile.
Selectors are bounded and validated once. A period spanning outside the provider
range returns OutOfRange rather than silently clipping.

Settle gap/BYSETPOS ordering against primary evidence before claiming timed RFC
conformance: §3.3.10's invalid-generated-time exclusion and its reference to
explicit DATE-TIME interpretation need an explicit adopted interpretation.
Settle exception duration identity, RDATE PERIOD support and subdaily buffering
limits before exposing those adapter operations. Unsupported scopes stay errors.
Verify adapter-specific omitted-field defaults separately: RFC/JSCalendar and
dateutil do not agree on every YEARLY BYMONTHDAY/BYWEEKNO default. The candidate
layer's native defaults are explicit in CalendarPattern; adapters must inject
their chosen standard's defaults rather than infer conformance from dateutil.

Acceptance includes January 31 → March 31 → May 31 for COUNT=3; a March query
retains the original count; excluding March does not add July. Test positive and
negative BYSETPOS over complete periods, WKST/year boundaries, duplicate dates,
all budget exhaustion points and resumptions, changing rule data, finite bounds
and provider extremes. No unbounded scan may occur inside a single cursor step.

Remove completed deliverables from this task and delete the plan when acceptance
is met. Contracts belong in design.md; evidence belongs in executable tests.
