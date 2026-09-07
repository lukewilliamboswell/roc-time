import ZoneRules
import TimedRecurrence
import TimedOccurrence
import TimedSchedule
import ICalTimedRule
import ICalPeriod
import LocalDateTime
import CalendarPattern
import GregorianDate
import Calendar
import ClockTime
import PosixDelta
import PosixBoundary
import PosixSpan
import FixedOffset

## A checked appointment declaration with immutable interpretation context.
## No series identifier, query window or evaluation progress is stored here.
## Supply an application identifier and a bounded source-label window to cursor.
## Native policies and iCalendar mode/ending intent remain distinct origins.
## Construction normalizes at most 4096 overrides and combined inclusions in
## O(n log n); it never enumerates starts or resolves zones. Native lists may
## share storage. An iCalendar origin retains its unlowered PERIOD declarations
## alongside prepared execution selectors. This is not a persistence format.
ScheduleDefinition :: { origin : Definition, rule : TimedRecurrence, endings : TimedSchedule.Endings, context : TimedRecurrence.Context }.{
	NativeSpec : { rule : TimedRecurrence, duration : TimedOccurrence.Duration, overrides : List(TimedSchedule.EndOverride), context : TimedRecurrence.Context }
	ICalSpec : { rule : ICalTimedRule, context : ICalPeriod.Context }
	Definition : [Native(NativeSpec), ICal(ICalSpec)]
	Error : [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime), TooManyPeriods, IncompatibleContext, TooManySelectors, OutOfRange]
	from_native : NativeSpec -> Try(ScheduleDefinition, Error)
	from_native = |spec| {
		endings = TimedSchedule.Endings.new(spec.duration, spec.overrides)?
		normalized = TimedSchedule.Endings.definition(endings)
		Ok({ origin: Native({ ..spec, overrides: normalized.overrides }), rule: spec.rule, endings, context: spec.context })
	}
	from_ical : ICalSpec -> Try(ScheduleDefinition, Error)
	from_ical = |spec| {
		prepared = ICalTimedRule.prepare(spec.rule, spec.context)?
		Ok({ origin: ICal(spec), rule: prepared.rule, endings: prepared.endings, context: prepared.context })
	}

	## Native overrides are normalized; iCalendar retains its mode and PERIOD
	## origins. Reading a declaration does not interpret it or create a cursor.
	definition : ScheduleDefinition -> Definition
	definition = |value| value.origin

	## Fresh execution state for each window; COUNT remains anchored at DTSTART.
	## Definition validation is not repeated. Interpretation errors remain lazy
	## checked results of TimedSchedule consumption under its normal budgets.
	cursor : id, ScheduleDefinition, TimedRecurrence.Window -> Try(TimedSchedule(id), [EmptyWindow, ReversedWindow, OutOfRange, ..])
	cursor = |series, value, window| TimedSchedule.from_prepared(series, value.rule, window, value.endings, value.context)

	## Declaration equality includes origin, retained selectors/exception labels,
	## ending intent and complete immutable context. It does not establish that
	## different recurrence declarations enumerate the same occurrence set.
	## Cost follows finite definition fields and transitions, never query extent.
	is_eq : ScheduleDefinition, ScheduleDefinition -> Bool
	is_eq = |a, b| {
		if a.context.occurrence != b.context.occurrence or a.context.gap != b.context.gap or ZoneRules.definition(a.context.rules) != ZoneRules.definition(b.context.rules) {
			return Bool.False
		}
		match (a.origin, b.origin) {
			(Native(left), Native(right)) => TimedRecurrence.definition(left.rule) == TimedRecurrence.definition(right.rule) and a.endings == b.endings
			(ICal(left), ICal(right)) => {
				x = ICalTimedRule.definition(left.rule)
				y = ICalTimedRule.definition(right.rule)
				x.mode == y.mode and x.duration == y.duration and x.periods == y.periods and TimedRecurrence.definition(x.rule) == TimedRecurrence.definition(y.rule) and (match (left.context, right.context) {
					(Utc, Utc) | (Local(_), Local(_)) => Bool.True
					_ => Bool.False
				})
			}
			_ => Bool.False
		}
	}
	to_hash : ScheduleDefinition, Hasher -> Hasher
	to_hash = |value, hasher| {
		context = { rules: ZoneRules.definition(value.context.rules), occurrence: value.context.occurrence, gap: value.context.gap }
		hash = context.to_hash(hasher)
		match value.origin {
			Native(spec) => value.endings.to_hash(TimedRecurrence.definition(spec.rule).to_hash((0.U8).to_hash(hash)))
			ICal(spec) => {
				data = ICalTimedRule.definition(spec.rule)
				key = {
					rule: TimedRecurrence.definition(data.rule),
					duration: data.duration,
					periods: data.periods,
					mode: data.mode,
					utc: match spec.context {
						Utc => Bool.True
						Local(_) => Bool.False
					},
				}
				key.to_hash((1.U8).to_hash(hash))
			}
		}
	}
	to_inspect : ScheduleDefinition -> Str
	to_inspect = |value| match value.origin {
		Native(_) => "ScheduleDefinition(native; explicit immutable context)"
		ICal(_) => "ScheduleDefinition(iCalendar; explicit immutable context)"
	}
}

test_local = |day| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	Ok(LocalDateTime.new(Calendar.Date.from_gregorian(date), clock))
}

test_native = || {
	date : GregorianDate
	date = "1970-01-01"
	clock = ClockTime.from_microseconds_since_midnight(0)?
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(3), by_set_pos: [] })?
	excluded = TimedRecurrence.with_exclusions(rule, [test_local(2)?])?
	included = TimedRecurrence.with_inclusions(excluded, [{ date: GregorianDate.from_fields({ year: 1970, month: 1, day: 5 })?, clock }])?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(864000000000))?
	rules = ZoneRules.new_bounded("Fixture/UTC", "epoch-grid-v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	Ok({ rule: included, duration: Coordinate(PosixDelta.from_microseconds(3600000000)), overrides: [{ source: test_local(5)?, ending: After(Coordinate(PosixDelta.from_microseconds(7200000000))) }], context: { rules, occurrence: RequireUnique, gap: RejectGap } })
}

# Distinguish an explicit local ending, explicit boundary, and calendar
# duration even in fixed UTC. The independent epoch widths retain fractions:
# 1 day + 500us; 1 day + (456-123)us; 1 hour + (789-123)us.
expect {
	spec = test_native()?
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(123)?
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(3), by_set_pos: [] })?
	second = LocalDateTime.new(Calendar.Date.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 2 })?), clock)
	third = LocalDateTime.new(Calendar.Date.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 3 })?), clock)
	local_end = LocalDateTime.new(LocalDateTime.date(third), ClockTime.from_microseconds_since_midnight(456)?)
	duration = Calendar({ delta: Calendar.Delta.days(1), invalid_date: Clamp, tail: PosixDelta.from_microseconds(500), occurrence: Last, gap: UseOffsetBeforeGap })
	overrides = [{ source: second, ending: AtLocal({ source: local_end, occurrence: First, gap: RejectGap }) }, { source: third, ending: AtBoundary(PosixBoundary.from_microseconds(176400000789)) }]
	definition = ScheduleDefinition.from_native({ ..spec, rule, duration, overrides })?
	declaration_valid = match ScheduleDefinition.definition(definition) {
		Native(native) => match native.duration {
			Calendar(value) => {
				endings_valid = match native.overrides {
					[first, last] => first.source == second and last.source == third and match (first.ending, last.ending) {
						(AtLocal(local), AtBoundary(boundary)) => local.source == local_end and local.occurrence == First and local.gap == RejectGap and boundary == PosixBoundary.from_microseconds(176400000789)
						_ => Bool.False
					}
					_ => Bool.False
				}
				Calendar.Delta.to_components(value.delta) == { years: 0, months: 0, days: 1 } and value.invalid_date == Clamp and value.tail == PosixDelta.from_microseconds(500) and value.occurrence == Last and value.gap == UseOffsetBeforeGap and endings_valid
			}
			_ => Bool.False
		}
		_ => Bool.False
	}
	cursor = ScheduleDefinition.cursor("fractional", definition, { start: test_local(1)?, end: test_local(4)? })?
	batch = TimedSchedule.collect(cursor, { work: { max_steps: 100, max_buffered: 1, max_zone_segments: 20, max_zone_candidates: 1 }, max_occurrences: 4 })?
	var $valid = declaration_valid and match batch.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}
	$valid = $valid and batch.occurrences.map(|item| PosixSpan.coordinate_width(TimedOccurrence.span(item))) == [Ok(PosixDelta.from_microseconds(86400000500)), Ok(PosixDelta.from_microseconds(86400000333)), Ok(PosixDelta.from_microseconds(3600000666))]
	for item in batch.occurrences {
		identity = TimedOccurrence.id(item)
		$valid = $valid and identity.series == "fractional" and ClockTime.to_fields(LocalDateTime.clock(identity.source)).microsecond == 123
	}
	# Equal extents do not erase ending intent. Conflict wins over the invalid
	# default duration, matching the existing constructor's validation order.
	conflict = match ScheduleDefinition.from_native({ ..spec, duration: Coordinate(PosixDelta.from_microseconds(0)), overrides: [{ source: second, ending: AtBoundary(PosixBoundary.from_microseconds(90000000123)) }, { source: second, ending: After(Coordinate(PosixDelta.from_microseconds(3600000000))) }] }) {
		Err(ConflictingEnding(source)) => source == second
		_ => Bool.False
	}
	$valid and conflict
}

# Independent epoch grid: daily COUNT=3 counts Jan 2 before exclusion; explicit
# Jan 5 is outside COUNT. Overlapping windows retain the same Jan 3 identity.
expect {
	definition = ScheduleDefinition.from_native(test_native()?)?
	var $valid = Bool.True
	for case in [{ first: 1.U8, end: 4.U8, expected: [0.I64, 172800000000] }, { first: 3, end: 6, expected: [172800000000, 345600000000] }] {
		cursor = ScheduleDefinition.cursor("series", definition, { start: test_local(case.first)?, end: test_local(case.end)? })?
		batch = TimedSchedule.collect(cursor, { work: { max_steps: 100, max_buffered: 1, max_zone_segments: 20, max_zone_candidates: 1 }, max_occurrences: 4 })?
		$valid = $valid and match batch.status {
			Complete => Bool.True
			Limited(_) => Bool.False
		}
		$valid = $valid and batch.occurrences.map(|item| PosixBoundary.to_microseconds(PosixSpan.start(TimedOccurrence.span(item)))) == case.expected
		for item in batch.occurrences {
			identity = TimedOccurrence.id(item)
			$valid = $valid and identity.series == "series"
			expected_width = if identity.source == test_local(5)? {
				7200000000.I64
			} else {
				3600000000.I64
			}
			$valid = $valid and PosixSpan.coordinate_width(TimedOccurrence.span(item)) == Ok(PosixDelta.from_microseconds(expected_width))
		}
	}
	$valid and ScheduleDefinition.to_inspect(definition).count_utf8_bytes() < 128
}

# Malformed definition errors precede any query. No artificial window is
# invented to check duration or conflicts, including an excluded source.
expect {
	spec = test_native()?
	source = test_local(2)?
	invalid = match ScheduleDefinition.from_native({ ..spec, duration: Coordinate(PosixDelta.from_microseconds(0)) }) {
		Err(InvalidDuration) => Bool.True
		_ => Bool.False
	}
	conflict = match ScheduleDefinition.from_native({ ..spec, overrides: [{ source, ending: AtBoundary(PosixBoundary.from_microseconds(172800000000)) }, { source, ending: After(Coordinate(PosixDelta.from_microseconds(3600000000))) }] }) {
		Err(ConflictingEnding(label)) => label == source
		_ => Bool.False
	}
	invalid and conflict
}

expect {
	rule = ICalTimedRule.parse({ start: "19700101T000000Z", rule: "FREQ=DAILY;COUNT=1", duration: "PT1H", inclusions: [], exclusions: [], periods: ["19700101T000000Z/PT2H", "19700101T000000Z/PT3H"], mode: Utc })?
	conflict = match ScheduleDefinition.from_ical({ rule, context: Utc }) {
		Err(ConflictingEnding(label)) => label == test_local(1)?
		_ => Bool.False
	}
	wrong_context = match ScheduleDefinition.from_ical({ rule, context: Local(test_native()?.context.rules) }) {
		Err(IncompatibleContext) => Bool.True
		_ => Bool.False
	}
	conflict and wrong_context
}
