# Make common API paths clear before publication

Objective: let callers complete ordinary date, availability and scheduling tasks
without learning implementation layers. Preserve the contracts in
[design.md](../design.md#acceptance-requirements); this task changes API ergonomics,
not temporal meaning. Proposed additions below are design proposals, not available APIs.

## Decision criteria

- Optimize the number of decisions a caller must understand, not the number of
  exported modules. Distinct dates, labels, boundaries, coverage, events and
  recurrence state prevent meaningful mistakes (R02, R10–R12).
- Teach one recommended route per task, then expose advanced composition.
  Explicit calendar, zone, ambiguity policy and work limits are necessary decisions.
  Repeated record unpacking and manual text padding are not.
- Place conveniences with the type that owns their meaning. Reuse validated
  construction and interpretation; do not add a second engine or repeat validation
  for each query (R07, R09, R15).
- Treat every reachable associated method as public contract. Hiding a module
  import does not hide methods on inferred values returned by public functions.
- Evaluate the complete application: inputs, errors, partial results, output and
  immutable dependency pins. A shorter successful expression alone is insufficient.

## First: improve the taught workflows

### Organize related nominal types through nesting

Use Roc's nested associated types to group semantic families. Distinct nominal
types do not require distinct top-level imports. The standard library's
`Crypto.SHA256.Digest`, `Crypto.SHA256.Hasher` and `Num.Range` demonstrate this
organization in `src/build/roc/Builtin.roc` in the Roc repository.

Prioritize a proposed Calendar family: `Calendar.Date`, `Calendar.Delta` and
`Calendar.Value` in place of CalendarDate, CalendarDelta and CalendarValue.
Evaluate Calendar.Arithmetic, Calendar.Pattern and Calendar.Evidence alongside
them. Preserve the distinction between a date, a calendar displacement and a
resolution-bearing description. This is namespace organization, not a universal
temporal value or a conversion between these domains.

Before migration, prototype real nested nominal types and their associated
constructors, literals, equality and generated documentation on the pinned
compiler. Resolve ownership of the existing Calendar profile type: it is already
imported by types that would move beneath it. A namespace wrapper importing those
same modules can introduce cycles. Establish an acyclic implementation layout;
do not assume aliases forward associated operations or that separate source
files are required for each public type.

The pinned compiler's associated aliases support method dispatch, but generated
docs display only the alias declaration: the underlying methods are absent from
the family page and search. Use actual nested nominal ownership for the public
family, or establish equally complete generated documentation before accepting
an alias-based layout. Standalone alias modules are unsupported. Include these
constraints in the migration prototype; nested spelling alone is insufficient.

Then propose a consistent family map for POSIX quantities, iCalendar values and
scheduling, using real caller applications to assess discoverability and depth.
Prefer shallow meaningful nesting; do not mechanically nest every similarly named
type. Include migration of imports, annotations, documentation links and examples
in the selected release scope. The starting-path table below describes current
APIs and must be updated when the nested API is chosen.

The [API guide](../www/content/api.md) already groups modules by task. Give each
group a recommended starting path and explain when to move to advanced APIs,
without adding an exhaustive inventory to the README.

| Caller task | Recommended starting path |
|---|---|
| Invoice dates and month-end terms | GregorianDate, then explicit CalendarArithmetic policy |
| Read or write an offset timestamp | OffsetTimestamp |
| Find free time between bookings | ExactInterval, then explicit projection to Coverage |
| Interpret a named-zone appointment | LocalDateTime and ZoneRules with an explicit occurrence policy |
| Reuse a timed schedule across queries | ScheduleDefinition construction, cursor, then TimedSchedule.collect |
| Expand date-only recurrence | DateRecurrence; do not invent midnight instants |

During [application promotion](user-time-workflows.md), replace manual date
formatting and raw date-field plumbing with existing validated literals and
text APIs. Start with Invoice and Staffing. Use inferred literals where a real
parameter establishes their nominal type; retain explicit Gregorian parsing for
LocalDateTime. Update examples only with compatible package URLs.

Give ordinary scheduling a direct definition-to-query example. Keep the
MeetingExchange export/reimport flow as an interchange example. Preserve the
whole query batch at application boundaries, including Limited reason and
resumption state; never teach conversion of incomplete results into a plain list.

## Second: implement two focused conveniences

### Source identity on a timed occurrence

Proposed `TimedOccurrence.source(item)` delegates to the existing nested
`TimedRecurrence.Occurrence.source(TimedOccurrence.start(item))` operation.
MeetingExchange, ReservationPlan and LoanSchedule provide concrete callers.

Input is a valid timed occurrence; output is its original source label. It is
total and should require no resolution or new allocation. Preserve `start` for
advanced interpretation evidence. The smallest trap is a gap-adjusted start:
the source label must remain the original label, not the adjusted local time.
Verify gap collisions and exclusions against independent recurrence fixtures,
and extend the relevant public fuzz target (R10–R12, R15–R16).

### Project a boundary through named-zone rules

Proposed `ZoneRules.project(zone, boundary, calendar)` composes the existing
`ZoneRules.offset_at` and `FixedOffset.project` operations. The named-zone
appointment application currently repeats this composition.

Prefer returning a record containing `local` and `offset`, so presentation can
use both without a second lookup. Settle the final name/result shape against
`FixedOffset.project`, which returns only the local label, before implementation.
Keep calendar explicit and preserve underlying structured errors and supported
ranges. A resolved boundary has one projection even during a fold; projection
does not choose an occurrence for an unresolved label.

Use fixed transition fixtures and an independent expected local/offset oracle.
Include both fold occurrences, a non-hour transition and the exclusive end of
zone validity, which must fail. Match existing lookup complexity, with one zone
lookup and no new cache or re-resolution of snapshots (R01, R06–R09, R15–R16).

## Resolve public preparation contracts before committing to them

The current associated methods `ICalTimedRule.prepare`, `ICalPeriod.prepare`
and `TimedSchedule.from_prepared` expose the unexported ScheduleEndings type
through inferred values. Removing exports or marking documentation “internal”
does not establish privacy. Decide between these two real costs:

1. Support the advanced preparation API deliberately. Give its checked ending
   plan a publicly nameable type and document validation, reuse and failure
   contracts. This preserves current layering but expands the supported surface.
2. Change implementation ownership so preparation is private. One candidate
   co-locates declaration and cursor implementations as distinct nominal types
   within a module. Adapters remain lower-level parsing/serialization modules;
   their upward scheduling conveniences must migrate. Prototype this with the
   pinned compiler before promising the design or compatibility wrappers.

A coordinator alone is insufficient: adapter scheduling methods would create
dependency cycles, and another module cannot construct the opaque cursor without
a bridge. Replacing prepared construction with ordinary construction would
revalidate endings per window. Include composed unit-test imports in dependency
analysis. Preserve original iCalendar declarations, PERIOD origins, cancellation
semantics and one-time validation under either option.

Recommendation: do not undertake the larger ownership change solely to shorten
the module list. Make the support-versus-consolidation decision explicit before
0.1.0; it is independent of the two small conveniences above.

Also settle `Coverage.SortedBuilder.append_retaining`: it is reachable and returns
the builder on bounded failure, which ZoneRules needs. Prefer documenting it as
an advanced checked operation over elaborate hiding. Review whether consolidating
the two bounded append methods improves caller handling enough to justify changing
pattern matches. Test Full with owned/shared builders and resumable consumption;
do not lose retained state in the name of convenience (R04, R12, R15).

## Acceptance and scope limits

- Run each revised multi-file application against local sources and both relevant
  distributable dependencies using the declared compiler, following the existing
  application promotion plan. Compare meaningful outputs and explicit errors.
- For API changes, run package check/test, affected executable fixtures, finite
  fuzz campaigns with regression replay, independent oracles and the full
  integration gate required by [AGENTS.md](../AGENTS.md). Preserve resource evidence
  where construction or query ownership changes.
- Check external applications can annotate intended public types. For anything
  made private, test both direct imports and methods reached through inferred
  return values; verify the intended diagnostic rather than any compilation failure.
- Review guides through the tasks above: a reader should identify a starting API,
  required semantic choices, successful result, failure handling and next step.
  This is a structured review criterion, not a claim of measured user usability.

Defer a generic DateTime facade, automatic policy defaults, a generic scheduling
builder and Gregorian-local arithmetic convenience until concrete callers justify
them. Do not remove calendar, evidence, standards or selector types merely to
hit an export-count target. Remove this plan when its decisions and selected
deliverables are complete; enduring API contracts belong beside the public code.
