# Recurrence execution

Implement R11–R12 through public constructors, bounded cursors and the shared
calendar/zone APIs. This task depends on validated Gregorian dates, clock labels,
finite immutable zone rules and event/coverage distinctions.

## Deliverables

- Resolve broader mixed UTC/local property support and UTC EXDATE matching
  against gap-adjusted sources before widening the timed profile: projecting
  an adjusted boundary cannot recover its original label.
- Extend RFC adaptation to omitted yearly defaults and declared
  serialization/persistence, retaining the shared native execution engine.
- Extend independent timed expectations beyond UTC to local-zone transitions
  and exception/ending interactions as their supported profiles expand. Retain
  bounded fuzz models, invalid-input checks and realistic applications.

## Decisions and acceptance still needed

### Save and exchange a supported schedule

Prioritize completing the currently supported profile before widening import.
The caller must be able to import or construct a meeting schedule, change its
definition through checked public construction, export canonical text, save/load
the native definition and evaluate the restored schedule over a bounded window.
This is an R11–R12/R14/R16 deliverable, using the existing execution engine.

- Declare separately what RFC text can represent and what versioned native
  persistence preserves. Reject unrepresentable native definitions explicitly;
  do not silently drop selectors, exceptions, source identity or policies.
- Expose a checked semantic definition for export where existing types lack
  accessors. Preserve series identifiers, duration overrides and exception source
  labels without parsing inspection output or expanding occurrences while saving.
- Decide whether persistence embeds an immutable interpretation snapshot or
  requires an explicitly identified snapshot on load. Test missing/mismatched
  context; a zone name alone must not imply reproducible interpretation.
- Distinguish saving a schedule definition from checkpointing an evaluation
  cursor. Definition persistence comes first; do not promise resumable cursor
  persistence without a declared compatible state format.
- Validate canonical parse/export/parse against independent RFC fixtures and
  malformed/version/unsupported-field cases. Verify original and restored
  definitions produce the independently expected events, exceptions and bounded
  incomplete outcomes across fixed gap/fold fixtures. Include multiple query
  windows so a matching first result cannot hide lost series state.
- Provide an executable multi-file application using the real public package
  and distributable bundle. Describe the supported property profile explicitly;
  this does not advertise a general ICS reader or writer.

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
