# Recurrence execution

Implement R11–R12 through public constructors, bounded cursors and the shared
calendar/zone APIs. This task depends on validated Gregorian dates, clock labels,
finite immutable zone rules and event/coverage distinctions.

## Deliverables

- Complete the supported schedule input/output workflow below before widening
  recurrence import. Prioritize durable definitions and interpretation.
- Resolve broader mixed UTC/local property support and UTC EXDATE matching
  against gap-adjusted sources before widening the timed profile: projecting
  an adjusted boundary cannot recover its original label.
- Resolve omitted yearly defaults before widening RFC adaptation, retaining
  the shared native execution engine.
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

### Durable definition and context

Add versioned persistence for `ScheduleDefinition`, using its semantic origin
and the existing native recurrence/zone definition accessors. Loading must use
the same checked constructors; keep query windows and progress outside the
archive.

Keep native and iCalendar definitions explicit: native storage must preserve
fractional labels, calendar/elapsed duration policies and source-keyed ending
overrides; iCalendar storage must retain mode, default duration and PERIOD ending
intent. Reuse existing schedule constructors for bounded evaluation. Do not
lower the archive to RFC text: native microseconds and years outside 1–9999 must
survive saving even when interchange rejects them.

Embed the immutable rule definition, including validity, transitions and
provenance, using the existing persistence rule transport. A name/version pair
alone is insufficient. Keep generic series IDs in an application envelope and
show the restored ID passed into fresh cursors for two overlapping windows.
The temporal persistence type must not encode arbitrary application types.

Use kind `schedule-definition`, profile `timed-schedule-definition-v1`, axis
`posix-1970` and unit `microsecond` in the existing version-1 envelope. Finalize
the flat JSON string-array grammar before encoding it: begin with `native` or
`ical`, followed by a shared native recurrence block, origin-specific ending
fields and the explicit context suffix. The recurrence block retains the anchor,
pattern/frequency/interval, calendar and clock selectors, termination domain and
counted source exceptions. Reuse native fraction-6 local labels, preserving
calendar identity. COUNT needs canonical U64 parsing; the I64 integer helper
must not narrow it. Other integers retain their nominal signed/unsigned domains.

Native ending fields distinguish coordinate/calendar duration and
After/AtBoundary/AtLocal overrides, including all endpoint policies. iCalendar
fields retain the supported profile/mode and canonical duration/PERIOD values;
its interpretation policies follow that profile. Local context appends the
complete existing rule transport; iCalendar UTC uses an explicit UTC marker.

Reuse the 65536-byte envelope, 49152-byte payload, 1024-transition and 4096-byte
rule-metadata limits. Preflight counts before encoding or typed decoding;
proposed archive caps are 4096 combined selectors, 1024 combined exception
labels and 1024 overrides/PERIODs. Prove exact byte boundaries and reject any
well-formed definition exceeding archive limits. Settle persistence equality
and hashing using the checked canonical declaration and complete embedded
context, without adding recurrence-set equality or repeated interpretation.
Preserve selector ordering/duplicates retained by native definition access and
PERIOD order/ending intent. Do not introduce encoding-only normalization that
makes construction and save/load disagree. Keep existing persistence kinds'
equality and hash discriminators unchanged when adding this kind.

The smallest complete timed workflow must retain the meeting's series identity,
original exception labels, default duration, explicit ending overrides and RFC
mode/policy, plus reproducible interpretation. Keep query windows and evaluation
progress outside the definition archive.

Construction/export/save/load costs must depend on bounded definition bytes,
selectors, exception entries and stored transitions, not occurrence count or
query duration. Set explicit archive count/byte caps and test an unbounded rule
with a tiny consumption budget to detect accidental expansion while saving.
Retain a native fractional-second or out-of-profile year case to
prove RFC export rejects precision/range loss instead of narrowing silently.

- Declare separately what RFC text can represent and what versioned native
  persistence preserves. Reject unrepresentable native definitions explicitly;
  do not silently drop selectors, exceptions, source identity or policies.
- Expose a checked semantic definition for export where existing types lack
  accessors. Preserve series identifiers, duration overrides and exception source
  labels without parsing inspection output or expanding occurrences while saving.
- Test missing/malformed embedded context and same-name/version snapshots with
  different transitions; a zone name alone must not imply reproducible
  interpretation.
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
