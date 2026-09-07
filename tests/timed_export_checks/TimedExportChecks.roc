import time.ICalTimedRule
import time.ICalDateTime
import time.TimedSchedule
import time.TimedOccurrence
import time.TimedRecurrence
import time.PosixBoundary
import time.PosixSpan
import time.ZoneRules
import time.FixedOffset
import time.LocalDateTime
import time.GregorianDate
import time.CalendarDate
import time.ClockTime
import time.ICalDuration
import time.ScheduleDefinition
import time.PosixDelta

# R07/R11/R12/R14: the native executable receives inputs only. Expected text
# and coordinates are authored independently in reference.py/cases.jsonl.
TimedExportChecks :: [].{
	run = |args| {
		if at(args, 0).starts_with("native-") {
			return native(at(args, 0))
		}
		parts = {
			start: at(args, 0),
			rule: at(args, 1),
			mode: match at(args, 2) {
				"Utc" => Utc
				"Floating" => Floating
				"Zoned" => Zoned
				_ => crash "Unknown fixture mode"
			},
			duration: at(args, 3),
			inclusions: values(at(args, 4)),
			exclusions: values(at(args, 5)),
			periods: values(at(args, 6)),
		}
		original = match ICalTimedRule.parse(parts) {
			Ok(value) => value
			Err(error) => return Str.inspect(error)
		}
		definition = ICalTimedRule.definition(original)
		native_rule = TimedRecurrence.from_definition(TimedRecurrence.definition(definition.rule)) ?? crash "Native definition rejected"
		rebuilt = ICalTimedRule.new({ ..definition, rule: native_rule }) ?? crash "Definition rejected"
		exported = ICalTimedRule.to_parts(rebuilt) ?? crash "Export rejected"
		restored = ICalTimedRule.parse(exported) ?? crash "Export cannot be imported"
		window = { start: label(at(args, 7)), end: label(at(args, 8)) }
		context = if at(args, 9) == "utc" {
			Utc
		} else {
			Local(rules(at(args, 9)))
		}
		saved = match ScheduleDefinition.from_ical({ rule: restored, context }) {
			Ok(value) => value
			Err(IncompatibleContext) => return "IncompatibleContext"
			Err(_) => crash "Window-free ICal definition rejected"
		}
		match ICalTimedRule.schedule(42.U64, restored, window, context) {
			Ok(_) => {}
			Err(IncompatibleContext) => return "IncompatibleContext"
			Err(_) => crash "Schedule rejected"
		}
		first = collect(original, window, context, Bool.True)
		second = collect(restored, window, context, Bool.False)
		third = collect_cursor(ScheduleDefinition.cursor(42.U64, saved, window) ?? crash "Definition cursor rejected", Bool.True)
		if first != second or first != third {
			crash "Export changed bounded execution"
		}
		# All period-free cases can also be described directly in the native
		# API, using explicit equivalent RFC policies and the same fixed data.
		if definition.periods.is_empty() {
			native_context = { rules: context_rules(context), occurrence: First, gap: UseOffsetBeforeGap }
			spec = { rule: definition.rule, duration: ICalDuration.to_duration(definition.duration), overrides: [], context: native_context }
			native_saved = ScheduleDefinition.from_native(spec) ?? crash "Native definition rejected"
			fourth = collect_cursor(ScheduleDefinition.cursor(42.U64, native_saved, window) ?? crash "Native cursor rejected", Bool.False)
			if first != fourth {
				crash "Native definition changed independent expected execution"
			}
			zero = I64.from_str(args.get(10) ?? "0") ?? 0
			match ScheduleDefinition.from_native({ ..spec, duration: Coordinate(PosixDelta.from_microseconds(zero)) }) {
				Err(InvalidDuration) => {}
				_ => crash "Zero duration accepted"
			}
			source = TimedRecurrence.definition(definition.rule).anchor
			match ScheduleDefinition.from_native({
				..spec,
				overrides: [
					{ source, ending: After(Coordinate(PosixDelta.from_microseconds(zero + 1))) },
					{ source, ending: After(Coordinate(PosixDelta.from_microseconds(zero + 2))) },
				],
			}) {
				Err(ConflictingEnding(label_value)) => if label_value != source {
					crash "Conflict lost source"
				}
				_ => crash "Conflicting endings accepted"
			}
		}
		Json.to_str({ parts: { start: exported.start, rule: exported.rule, duration: exported.duration, inclusions: exported.inclusions, exclusions: exported.exclusions, periods: exported.periods, mode: Str.inspect(exported.mode) }, occurrences: first })
	}
}

native = |name| {
	if name == "native-exact-cap" or name == "native-over-cap" {
		return exact_cap(name)
	}
	original = ICalTimedRule.parse({ start: "19700101T090000Z", rule: "FREQ=DAILY", duration: "PT1H", mode: Utc, inclusions: [], exclusions: [], periods: [] }) ?? crash "Native base"
	wrapped = ICalTimedRule.definition(original)
	definition = TimedRecurrence.definition(wrapped.rule)
	year = if name == "native-year-zero" {
		0
	} else if name == "native-year-high" {
		10000
	} else {
		1970
	}
	date = GregorianDate.from_fields({ year, month: 1, day: 1 }) ?? crash "Native date"
	clock = ClockTime.from_microseconds_since_midnight(
		if name == "native-fraction" {
			32400000001
		} else {
			32400000000
		},
	) ?? crash "Native clock"
	anchor = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	var $exceptions = []
	if name == "native-size" {
		var $second = 0.I64
		while $second < 4096 {
			item_clock = ClockTime.from_microseconds_since_midnight($second * 1000000) ?? crash "Exception clock"
			$exceptions = $exceptions.append(LocalDateTime.new(CalendarDate.from_gregorian(date), item_clock))
			$second = $second + 1
		}
	} else if name == "native-rdate-fraction" or name == "native-exdate-fraction" {
		item_clock = ClockTime.from_microseconds_since_midnight(1) ?? crash "Fractional exception clock"
		$exceptions = [LocalDateTime.new(CalendarDate.from_gregorian(date), item_clock)]
	} else if name == "native-julian-exdate" {
		julian = CalendarDate.from_fields(Julian, { year: 1969, month: 12, day: 19 }) ?? crash "Julian fixture"
		julian_label = LocalDateTime.new(julian, clock)
		if !LocalDateTime.same_position(julian_label, anchor) or julian_label == anchor {
			crash "Julian fixture distinction"
		}
		$exceptions = [julian_label]
	}
	changed = TimedRecurrence.from_definition({
		..definition,
		anchor,
		inclusions: if name == "native-exdate-fraction" or name == "native-julian-exdate" {
			[]
		} else {
			$exceptions
		},
		exclusions: if name == "native-rdate-fraction" {
			[]
		} else {
			$exceptions
		},
		termination: if name == "native-count" {
			Count(2147483648)
		} else if name == "native-until-fraction" {
			UntilBoundary(PosixBoundary.from_microseconds(32400000001))
		} else {
			Forever
		},
	}) ?? crash "Native construction rejected"
	# A native definition is valid independently of RFC text precision/year
	# restrictions and of whether its source can resolve within the timeline.
	native_saved = ScheduleDefinition.from_native({
		rule: changed,
		duration: Coordinate(PosixDelta.from_microseconds(1)),
		overrides: [],
		context: { rules: context_rules(Utc), occurrence: RequireUnique, gap: RejectGap },
	}) ?? crash "Native schedule narrowed the native domain"
	match ScheduleDefinition.definition(native_saved) {
		Native(spec) => {
			original_native = TimedRecurrence.definition(changed)
			restored_native = TimedRecurrence.definition(spec.rule)
			if restored_native.anchor != original_native.anchor or restored_native.exclusions != original_native.exclusions or restored_native.inclusions != original_native.inclusions or spec.duration != Coordinate(PosixDelta.from_microseconds(1)) {
				crash "Native schedule definition lost exact fields"
			}
		}
		ICal(_) => crash "Native schedule changed variant"
	}
	if name == "native-julian-exdate" {
		rebuilt = TimedRecurrence.definition(changed)
		if rebuilt.exclusions != $exceptions {
			crash "Native rebuild changed exclusion calendar"
		}
	}
	match ICalTimedRule.new({ ..wrapped, rule: changed }) {
		Ok(value) => match ICalTimedRule.to_parts(value) {
			Ok(_) => crash "Native unsupported value exported"
			Err(error) => Str.inspect(error)
		}
		Err(error) => Str.inspect(error)
	}
}

exact_cap = |name| {
	# Independent byte equation: 4091 * 16 date-time bytes + 16 DTSTART
	# + 60 RRULE bytes + 4 PT1S bytes = 65536. PT10S adds exactly one.
	base = ICalTimedRule.parse({ start: "19700101T090000Z", rule: "FREQ=DAILY", duration: "PT1S", mode: Utc, inclusions: [], exclusions: [], periods: [] }) ?? crash "Cap base"
	wrapped = ICalTimedRule.definition(base)
	definition = TimedRecurrence.definition(wrapped.rule)
	var $exceptions = []
	var $second = 0.I64
	while $second < 4091 {
		clock = ClockTime.from_microseconds_since_midnight($second * 1000000) ?? crash "Cap clock"
		$exceptions = $exceptions.append(LocalDateTime.new(LocalDateTime.date(definition.anchor), clock))
		$second = $second + 1
	}
	rule = TimedRecurrence.from_definition({ ..definition, exclusions: $exceptions }) ?? crash "Cap native rule"
	duration = ICalDuration.parse(
		if name == "native-exact-cap" {
			"PT1S"
		} else {
			"PT10S"
		},
	) ?? crash "Cap duration"
	value = match ICalTimedRule.new({ ..wrapped, rule, duration }) {
		Ok(constructed) => constructed
		Err(error) => return Str.inspect(error)
	}
	parts = ICalTimedRule.to_parts(value) ?? crash "Accepted cap export failed"
	var $bytes = parts.start.count_utf8_bytes() + parts.rule.count_utf8_bytes() + parts.duration.count_utf8_bytes()
	for text in parts.exclusions {
		$bytes = $bytes + text.count_utf8_bytes()
	}
	reloaded = ICalTimedRule.parse(parts) ?? crash "Exact cap import failed"
	if ICalTimedRule.to_parts(reloaded) != Ok(parts) {
		crash "Exact cap semantic roundtrip changed output"
	}
	Json.to_str({ bytes: $bytes, exclusions: parts.exclusions.len() })
}

at = |items, index| items.get(index) ?? crash "Fixture arity"

context_rules = |context| match context {
	Local(value) => value
	Utc => {
		validity = PosixSpan.new(PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(I64.highest)) ?? crash "UTC fixture validity"
		ZoneRules.new_bounded("UTC", "fixed-test", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 }) ?? crash "UTC fixture rules"
	}
}

values = |text| if text == "-" {
	[]
} else {
	text.split_on("|")
}

timestamp = |text| ICalDateTime.parse(text) ?? crash "Invalid fixture timestamp"

label = |text| ICalDateTime.local_label(timestamp(text))

rules = |name| {
	# This deliberately tiny synthetic clock changes at the Unix epoch.
	# It is not an IANA database. Explicit offsets make the model independent
	# of installed tzdata, transition lookup, and Gregorian conversion code.
	initial = if name == "gap" {
		0
	} else if name == "fold" {
		3600
	} else {
		7200
	}
	final = if name == "gap" {
		3600
	} else {
		0
	}
	transitions = if name == "fixed" {
		[]
	} else {
		[{ at: PosixBoundary.from_microseconds(0), offset: FixedOffset.from_seconds(final) }]
	}
	validity = PosixSpan.from_seconds(-1000000, 1000000, RejectSubmicrosecond) ?? crash "Fixture validity"
	ZoneRules.new_bounded("Synthetic/Export", name, validity, FixedOffset.from_seconds(initial), transitions, { minimum: 0, maximum: 7200 }) ?? crash "Fixture zone rejected"
}

collect = |rule, window, context, tiny| {
	cursor = match ICalTimedRule.schedule(42.U64, rule, window, context) {
		Ok(value) => value
		Err(_) => crash "Schedule rejected"
	}
	collect_cursor(cursor, tiny)
}

collect_cursor = |cursor, tiny| {
	var $cursor = cursor
	var $output = []
	var $calls = 0.U64
	while $calls < 10000 {
		batch = TimedSchedule.collect(
			$cursor,
			{
				work: {
					max_steps: if tiny {
						3
					} else {
						10000
					},
					max_buffered: 366,
					max_zone_segments: if tiny {
						1
					} else {
						10000
					},
					max_zone_candidates: 2,
				},
				max_occurrences: if tiny {
					1
				} else {
					100
				},
			},
		) ?? crash "Execution rejected"
		for value in batch.occurrences {
			span = TimedOccurrence.span(value)
			identity = TimedOccurrence.id(value)
			if identity.series != 42 or identity.source != TimedOccurrence.source(value) {
				crash "Schedule changed series or source identity"
			}
			$output = $output.append({
				source: LocalDateTime.to_gregorian_text(TimedOccurrence.source(value)) ?? crash "Source calendar",
				start: PosixBoundary.to_microseconds(PosixSpan.start(span)),
				end: PosixBoundary.to_microseconds(PosixSpan.end(span)),
			})
		}
		match batch.status {
			Complete => return $output
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "Bounded fixture did not terminate"
}
