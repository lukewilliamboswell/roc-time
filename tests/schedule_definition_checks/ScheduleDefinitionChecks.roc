import ScheduleFixture
import time.ScheduleDefinition
import time.ICalTimedRule
import time.ICalDuration
import time.TimedRecurrence
import time.TimedOccurrence
import time.LocalDateTime
import time.CalendarDate
import time.GregorianDate
import time.ClockTime
import time.PosixBoundary
import time.PosixSpan
import time.PosixDelta
import time.CalendarDelta
import time.FixedOffset
import time.ZoneRules
import time.CalendarPattern

## Independent synthetic model: after epoch the supplied offset is exactly +3600
## seconds. A second table with the same labels has offset zero. Weekly starts
## are Dec25, Jan1, Jan8, Jan15; removing Jan8 does not replenish COUNT.
ScheduleDefinitionChecks :: [].{
	run = |suffix| {
		check_transitions(suffix)?
		for offset in [0, 3600] {
			zone = ScheduleFixture.rules(offset)?
			original = ScheduleFixture.meeting(zone)?
			loaded = { series_id: "team${suffix}", definition: reimport(original)? }
			check_hashes(original, loaded.definition, suffix)?
			if loaded.series_id != "team${suffix}" {
				crash "Series identifier changed"
			}
			batch = ScheduleFixture.collect(loaded, "1969-12-24T00:00", "1970-01-16T00:00")?
			match batch.status {
				Complete => {}
				Limited(_) => crash "Small fixture incomplete"
			}
			# Exact epoch arithmetic, independent of date conversion and zone
			# resolution: Dec25 is day -7; Jan1/2/15 are days 0/1/14.
			shift = I32.to_i64(offset)
			expected = [(-7 * 86400 + 32400, 3600), (32400 - shift, 3600), (86400 + 32400 - shift, 7200), (14 * 86400 + 32400 - shift, 3600)]
			if batch.occurrences.len() != 4 {
				crash "COUNT/exceptions changed"
			}
			var $index = 0.U64
			for occurrence in batch.occurrences {
				(seconds, width) = expected.get($index) ?? crash "Fixture index"
				$index = $index + 1
				span = TimedOccurrence.span(occurrence)
				if PosixBoundary.to_microseconds(PosixSpan.start(span)) != seconds * 1000000 or PosixSpan.coordinate_width(span) != Ok(PosixDelta.from_microseconds(width * 1000000)) {
					crash "Declaration changed independently expected span"
				}
				identity = TimedOccurrence.id(occurrence)
				if identity.series != loaded.series_id or identity.source != TimedOccurrence.source(occurrence) {
					crash "Declaration changed occurrence identity"
				}
			}
		}
		base = parse_rule({ start: "19700101T090000Z", rule: "FREQ=DAILY;COUNT=1", duration: "PT1H", mode: Utc, inclusions: [], exclusions: [], periods: [] })?
		base_data = ICalTimedRule.definition(base)
		check_native_ending_hashes(base_data.rule, suffix)?
		for (year, micros) in [(1970, 32400000001), (10000, 32400000000)] {
			date = GregorianDate.from_fields({ year, month: 1, day: 1 })?
			clock = ClockTime.from_microseconds_since_midnight(micros)?
			anchor = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
			rule = TimedRecurrence.from_definition({ ..TimedRecurrence.definition(base_data.rule), anchor })?
			native = native_definition({ rule, duration: ICalDuration.to_duration(base_data.duration), overrides: [], context: { rules: ScheduleFixture.rules(0)?, occurrence: RequireUnique, gap: RejectGap } })?
			rebuilt = { definition: rebuild_native(native)? }
			check_hashes(native, rebuilt.definition, suffix)?
			match ScheduleDefinition.definition(rebuilt.definition) {
				Native(spec) => if TimedRecurrence.definition(spec.rule).anchor != anchor {
					crash "Native precision/year changed"
				}
				ICal(_) => crash "Native origin changed"
			}
			match ICalTimedRule.new({ ..base_data, rule }) {
				Err(PrecisionLoss(_)) => if micros == 32400000000 {
					crash "Whole-second label reported precision loss"
				}
				Err(OutOfRange(_)) => if year != 10000 {
					crash "Ordinary year reported out of range"
				}
				_ => crash "RFC export did not reject native precision/range explicitly"
			}
		}
		Ok({})
	}
}

# Independent offset equations around epoch zero. A fold from +3600 to zero
# gives 00:30 two positions: -1800s and +1800s. A gap from zero to +3600
# has no exact 00:30; explicit before-gap interpretation gives +1800s.
check_transitions = |suffix| {
	anchor = LocalDateTime.parse_gregorian("1970-01-01T00:30") ?? crash "Transition source"
	date = CalendarDate.as_gregorian(LocalDateTime.date(anchor))?
	rule = TimedRecurrence.new(
		{ date, clock: LocalDateTime.clock(anchor) },
		{
			calendar: CalendarPattern.defaults(Daily),
			clocks: { hours: [], minutes: [], seconds: [] },
			termination: Count(1),
			by_set_pos: [],
		},
	)?
	validity = PosixSpan.from_seconds(-86400, 86400, RejectSubmicrosecond)?
	for case in [
		{ name: "fold-first", initial: 3600, offset: 0, occurrence: First, gap: RejectGap, expected: Start(-1800000000.I64) },
		{ name: "fold-last", initial: 3600, offset: 0, occurrence: Last, gap: RejectGap, expected: Start(1800000000.I64) },
		{ name: "fold-unique", initial: 3600, offset: 0, occurrence: RequireUnique, gap: RejectGap, expected: Ambiguous },
		{ name: "gap-before", initial: 0, offset: 3600, occurrence: RequireUnique, gap: UseOffsetBeforeGap, expected: Start(1800000000.I64) },
		{ name: "gap-reject", initial: 0, offset: 3600, occurrence: RequireUnique, gap: RejectGap, expected: Gap },
	] {
		zone = ZoneRules.new_bounded("Synthetic/Declaration", "epoch-transition-v1", validity, FixedOffset.from_seconds(case.initial), [{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(case.offset) }], { minimum: 0, maximum: 3600 })?
		original = native_definition({ rule, duration: Coordinate(PosixDelta.from_microseconds(1)), overrides: [], context: { rules: zone, occurrence: case.occurrence, gap: case.gap } })?
		series = "${case.name}${suffix}"
		rebuilt = { series_id: series, definition: rebuild_native(original)? }
		check_hashes(original, rebuilt.definition, suffix)?
		match ScheduleDefinition.definition(rebuilt.definition) {
			Native(spec) => if ZoneRules.definition(spec.context.rules) != ZoneRules.definition(zone) or spec.context.occurrence != case.occurrence or spec.context.gap != case.gap {
				crash "Transition declaration lost context or policy"
			}
			ICal(_) => crash "Transition declaration changed origin"
		}
		match ScheduleFixture.collect(rebuilt, "1970-01-01T00:00", "1970-01-02T00:00") {
			Err(Evaluation(Gap)) => if case.expected != Gap {
				crash "Unexpected declarationd gap rejection"
			}
			Err(Evaluation(Ambiguous)) => if case.expected != Ambiguous {
				crash "Unexpected declarationd fold ambiguity"
			}
			Err(_) => crash "Unexpected declarationd transition failure"
			Ok(batch) => {
				expected = match case.expected {
					Start(value) => value
					_ => crash "Declaration silently chose a transition interpretation"
				}
				match batch.status {
					Complete => {}
					Limited(_) => crash "Transition declaration fixture incomplete"
				}
				if batch.occurrences.len() != 1 {
					crash "Transition declaration occurrence count"
				}
				item = batch.occurrences.get(0) ?? crash "Transition occurrence"
				identity = TimedOccurrence.id(item)
				span = TimedOccurrence.span(item)
				if identity.series != series or identity.source != anchor or PosixBoundary.to_microseconds(PosixSpan.start(span)) != expected or PosixSpan.coordinate_width(span) != Ok(PosixDelta.from_microseconds(1)) {
					crash "Transition declaration differs from independent offset model"
				}
				match TimedRecurrence.Occurrence.adjustment(TimedOccurrence.start(item)) {
					Exact => if case.gap == UseOffsetBeforeGap {
						crash "Declarationd gap adjustment evidence lost"
					}
					BeforeGap(_) => if case.gap != UseOffsetBeforeGap {
						crash "Declaration invented gap adjustment"
					}
				}
			}
		}
	}
	Ok({})
}

# Dictionary lookup exercises real nominal equality/hash dispatch in native
# builds. Equal rebuilt declarations must retrieve direct definition keys.
check_hashes = |original, rebuilt, suffix| {
	if original != rebuilt or Dict.get(Dict.insert(Dict.empty(), original, suffix), rebuilt) != Ok(suffix) {
		crash "Rebuilt schedule definition dictionary key changed"
	}
	Ok({})
}

# No evaluation is needed to compare ending declarations. Include every ending
# form and all occurrence policies, plus each calendar invalid-date policy.
# Explicit boundary extrema and fractional local endings retain their domains.
check_native_ending_hashes = |rule, suffix| {
	var $definitions = Dict.empty()
	var $index = 0.U64
	for occurrence in [RequireUnique, First, Last, MatchingOffset(FixedOffset.from_seconds(3600))] {
		invalid_date = match $index {
			0 => Reject
			1 => Clamp
			_ => Carry
		}
		gap = if $index == 0 {
			RejectGap
		} else {
			UseOffsetBeforeGap
		}
		duration = Calendar({ delta: CalendarDelta.from_components({ years: 1, months: 2, days: 3 }), invalid_date, tail: PosixDelta.from_microseconds(17), occurrence, gap })
		overrides = [
			{ source: ending_label(1, 1)?, ending: After(Coordinate(PosixDelta.from_microseconds(7))) },
			{ source: ending_label(2, 2)?, ending: AtBoundary(PosixBoundary.from_microseconds(I64.lowest)) },
			{ source: ending_label(3, 3)?, ending: AtLocal({ source: ending_label(4, 33)?, occurrence, gap }) },
			{ source: ending_label(4, 4)?, ending: After(duration) },
		]
		original = native_definition({ rule, duration, overrides, context: { rules: ScheduleFixture.rules(0)?, occurrence, gap } })?
		rebuilt = { definition: rebuild_native(original)? }
		check_hashes(original, rebuilt.definition, suffix)?
		$definitions = Dict.insert($definitions, original, $index)
		if Dict.get($definitions, rebuilt.definition) != Ok($index) {
			crash "Native ending policy dictionary lookup changed"
		}
		$index = $index + 1
	}
	if $definitions.len() != 4 {
		crash "Distinct ending policies collapsed into one key"
	}
	Ok({})
}

ending_label = |day, microsecond| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day })?
	clock = ClockTime.from_fields({ hour: 9, minute: 0, second: 0, microsecond })?
	Ok(LocalDateTime.new(CalendarDate.from_gregorian(date), clock))
}

parse_rule = |parts| match ICalTimedRule.parse(parts) {
	Ok(value) => Ok(value)
	Err(error) => Err(Interchange(error))
}

native_definition = |parts| match ScheduleDefinition.from_native(parts) {
	Ok(value) => Ok(value)
	Err(error) => Err(Definition(error))
}

# RFC property values carry the supported temporal declaration; interpretation
# data is supplied explicitly again by the caller, not encoded as an archive.
reimport = |definition| match ScheduleDefinition.definition(definition) {
	ICal(spec) => {
		parts = match ICalTimedRule.to_parts(spec.rule) {
			Ok(value) => value
			Err(error) => return Err(Interchange(error))
		}
		rule = parse_rule(parts)?
		match ScheduleDefinition.from_ical({ rule, context: spec.context }) {
			Ok(value) => Ok(value)
			Err(error) => Err(Definition(error))
		}
	}
	Native(_) => crash "RFC fixture requires an ICal declaration"
}

# Native definitions have no general standard serialization. This independently
# exercises checked semantic reconstruction, including precision and policies.
rebuild_native = |definition| match ScheduleDefinition.definition(definition) {
	Native(spec) => native_definition(spec)
	ICal(_) => crash "Native fixture requires a native declaration"
}
