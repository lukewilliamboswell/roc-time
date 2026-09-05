# Recurrence execution

Implement R11–R12 through public constructors, bounded cursors and the shared
calendar/zone APIs. This task depends on validated Gregorian dates, clock labels,
finite immutable zone rules and event/coverage distinctions.

## Deliverables

- Timed-series inclusions, exclusions and occurrence durations, including an
  explicit decision on RDATE PERIOD support. Reuse CalendarPattern,
  SubdailyPattern, ClockPattern and ZoneRules. Apply the RFC timed profile's
  before-gap offset and first-fold policies (verified erratum 4271); only invalid
  calendar dates are discarded. BYSETPOS must see full timed candidate periods.
- Preserve inclusion/exclusion ordering and duration interpretation inputs in
  immutable resumptions. Extend the native cursor's work/buffer/output accounting
  through those operations; query restriction never restarts series COUNT.
- Extend RFC 5545 adaptation to timed values, omitted yearly defaults and
  declared serialization/persistence. Keep its explicit profile and UNTIL type
  checks; do not introduce a separate parser execution engine.
- Independently generated JSONL cases, RFC examples, synthetic zone transitions,
  bounded fuzz models, invalid-input/domain checks and realistic applications.

## Decisions and acceptance still needed

Use RFC 5545 §§3.3.10 and 3.8.5, with verified errata 1913/3779 for ordinal
BYDAY. All-day calendar candidates can use the full Gregorian provider range;
the text adapter must separately declare its representable year profile.
Selectors are bounded and validated once. A period spanning outside the provider
range returns OutOfRange rather than silently clipping.

Compose timed periods with bounded boundary classification and explicit
occurrence selection; preserve gap-adjustment evidence and AmbiguousGap errors.
Do not hide a full
transition-table scan inside one recurrence work unit. Use RFC 5545 §3.3.5's New York 2007 gap/fold examples
and verified erratum 4271 as conformance fixtures. For the subdaily adapter,
use [verified erratum 3883](https://www.rfc-editor.org/errata/eid3883): the
New York 1997-09-02 three-hour example ends at 21:00Z, not the original
17:00Z. Verify both UTC cutoff variants independently rather than preserving
the erroneous example's output. Settle BYSETPOS ordering and
deduplication when different source labels map to the same boundary after gap
adjustment; retain source identity rather than inferring it from coverage.
Settle exception duration identity, RDATE PERIOD support and subdaily buffering
limits before exposing those adapter operations. Unsupported scopes stay errors.
Resolve omitted-field defaults before widening `rfc5545-date-values-v1`:
RFC 5545 §3.3.10's derivation prose/table, RFC 8984 §4.3.3's explicit defaults
and dateutil disagree for YEARLY BYMONTHDAY without BYMONTH and BYWEEKNO without
BYDAY. The adapter currently requires those explicit fields in the affected
combinations. Identify primary clarification and differential evidence rather
than silently copying JSCalendar or dateutil behavior into the RFC profile.
The candidate layer's native defaults remain explicit in CalendarPattern.

Extend date-only executable scenarios to the adapter and timed paths: January
31 → March 31 → May 31 for COUNT=3, with original COUNT retained under March
queries and exclusions. Verify BYSETPOS over full interpreted periods, WKST/year
boundaries, duplicate dates, all budget exhaustion points and resumptions,
changing rule data, finite bounds and provider extremes. No unbounded scan may
occur inside a single cursor step.

Remove completed deliverables from this task and delete the plan when acceptance
is met. Contracts belong in design.md; evidence belongs in executable tests.
