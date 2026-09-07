# Recurrence execution

Implement R11–R12 through public constructors, bounded cursors and the shared
calendar/zone APIs. This task depends on validated Gregorian dates, clock labels,
finite immutable zone rules and event/coverage distinctions.

## Deliverables

- Resolve broader mixed UTC/local property support and UTC EXDATE matching
  against gap-adjusted sources before widening the timed profile: projecting
  an adjusted boundary cannot recover its original label.
- Resolve omitted yearly defaults before widening RFC adaptation, retaining
  the shared native execution engine.
- Extend independent timed expectations beyond UTC to local-zone transitions
  and exception/ending interactions as their supported profiles expand. Retain
  bounded fuzz models, invalid-input checks and realistic applications.

## Decisions and acceptance still needed

### UTC cancellations for zoned meetings

The next candidate caller receives local DTSTART and UTC EXDATE properties from
an extracted calendar feed. Keep floating/UTC mixtures and mixed-form RDATE or
PERIOD values outside this first extension. The existing timed profile must
continue rejecting unsupported combinations until the complete slice lands.

- Preserve local exclusions as source labels and UTC exclusions as boundary
  values. Resolve candidates through the existing engine before matching UTC
  exclusions; never project an excluded boundary back into a source label.
  Apply exclusions to explicit inclusions too, without replenishing COUNT.
- Settle the collision rule when different source labels map to one excluded
  boundary. Excluding all matching boundaries is the candidate behavior; local
  exclusions remain source-specific. Preserve identity and BYSETPOS ordering.
- Decide whether boundary exclusions belong in the native recurrence definition
  or a shared prepared filter. Do not introduce a second cursor engine or an
  unbounded scan hidden inside one work unit.
- Preserve both domains through checked construction, definition access,
  canonical export, explanation and versioned persistence. Existing version-1
  archives contain a timed profile identifier; changing a global profile
  constant must not make them unreadable. Select explicit compatible versions
  before extending the stored grammar.
- Use the RFC gap/fold cases below, synthetic colliding-source cases, COUNT and
  PERIOD-inclusion precedence, overlapping windows and resumption. Pair saved
  and restored execution with an independent piecewise-offset model. Measure
  large exclusion sets with tiny consumption budgets.

A gap source such as New York 2007-03-11 02:30 maps to 07:30Z under the RFC
before-gap policy, but projecting 07:30Z yields 03:30 and loses source identity.
At the 2007-11-04 fold, 01:30 selects 05:30Z; a 06:30Z exclusion must not remove
that first occurrence merely because both boundaries project to 01:30.

### Broader import and execution

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
Keep unsupported mixed-form PERIOD properties and timed exception matching
explicit before widening the property adapter.
Resolve omitted-field defaults before widening `rfc5545-date-values-v1`:
RFC 5545 §3.3.10's derivation prose/table, RFC 8984 §4.3.3's explicit defaults
and dateutil disagree for YEARLY BYMONTHDAY without BYMONTH and BYWEEKNO without
BYDAY. The adapter currently requires those explicit fields in the affected
combinations. Identify primary clarification and differential evidence rather
than silently copying JSCalendar or dateutil behavior into the RFC profile.
The candidate layer's native defaults remain explicit in CalendarPattern.

When widening the profile, extend checks for BYSETPOS over full interpreted
periods, WKST/year boundaries, duplicate dates, all budget exhaustion points and
resumptions, changing rule data, finite bounds and provider extremes. No unbounded
scan may occur inside a single cursor step.

Remove completed deliverables from this task and delete the plan when acceptance
is met. Contracts belong in design.md; evidence belongs in executable tests.
