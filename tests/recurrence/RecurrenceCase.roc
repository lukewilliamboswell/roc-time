import fuzz.Fuzz
import time.Explanation
import time.SemanticFact
import time.TimedSchedule
import time.ScheduleDefinition
import time.TimedOccurrence
import time.CalendarDelta
import time.TimedRecurrence
import time.CalendarDate
import time.ClockTime
import time.LocalDateTime
import time.AllDayRecurrence
import time.AllDayOccurrence
import time.Coverage
import time.PosixDelta
import time.PosixSpan
import time.PosixBoundary
import time.FixedOffset
import time.ZoneRules
import time.CalendarPattern
import time.DateRecurrence
import time.GregorianDate
import time.ICalTimedRule
import time.ICalPeriod
import time.ICalDuration
import time.ICalDateRule

# R11–R12: a finite calendar-table model, independent of CalendarPattern and
# cursor execution. Enumerate 2024–2025 before applying count/union/exclusions.
RecurrenceCase := { last_monday : Bool, interval : U8, count : U8, query_month : U8, exclude_anchor : Bool, work : U8 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(RecurrenceCase)
	generator_for = |_| {
		last_monday: Fuzz.map(Fuzz.u8_in(0, 1), |n| n == 1),
		interval: Fuzz.u8_in(1, 3),
		count: Fuzz.u8_in(1, 6),
		query_month: Fuzz.u8_in(1, 12),
		exclude_anchor: Fuzz.map(Fuzz.u8_in(0, 1), |n| n == 1),
		work: Fuzz.u8_in(1, 128),
	}.Fuzz

	check : RecurrenceCase -> Fuzz.Outcome
	check = |input| {
		anchor = date(
			2024,
			1,
			if input.last_monday {
				29
			} else {
				31
			},
		)
		pattern = if input.last_monday {
			{ ..CalendarPattern.defaults(Monthly), interval: input.interval.to_i64(), by_day: [{ ordinal: 0, weekday: Monday }] }
		} else {
			{ ..CalendarPattern.defaults(Monthly), interval: input.interval.to_i64() }
		}
		inclusions = [date(2024, 2, 4), date(2024, 3, 31), anchor, date(2024, 2, 4)]
		exclusions = if input.exclude_anchor {
			[anchor, date(2024, 3, 31)]
		} else {
			[date(2024, 3, 31)]
		}
		rule = match DateRecurrence.new(
			anchor,
			{
				pattern,
				termination: Count(input.count.to_u64()),
				by_set_pos: if input.last_monday {
					[-1]
				} else {
					[]
				},
				inclusions,
				exclusions,
			},
		) {
			Ok(value) => value
			Err(_) => crash "Valid generated recurrence rejected"
		}
		check_date_explanation(rule, input, anchor)
		check_rfc_explanation(input)
		window = { start: date(2024, input.query_month, 1), end: date(2026, 1, 1) }
		text = "FREQ=MONTHLY;COUNT=${input.count.to_str()};INTERVAL=${input.interval.to_str()}${
			if input.last_monday {
				";BYDAY=MO;BYSETPOS=-1"
			} else {
				""
			}
		}"
		anchor_text = if input.last_monday {
			"20240129"
		} else {
			"20240131"
		}
		parts = {
			start: anchor_text,
			rule: text,
			inclusions: ["20240204,20240331", anchor_text, "20240204"],
			exclusions: if input.exclude_anchor {
				[anchor_text, "20240331"]
			} else {
				["20240331"]
			},
		}
		parsed = match ICalDateRule.parse(parts) {
			Ok(value) => value
			Err(_) => crash "Valid RFC date rule rejected"
		}
		# R11/R14: independently specified canonical spelling and set ordering.
		# Reparse/export stability is paired with the finite calendar model below.
		exported = match ICalDateRule.to_parts(rule) {
			Ok(value) => value
			Err(_) => crash "Supported native DATE rule failed export"
		}
		expected_parts = {
			start: anchor_text,
			rule: "FREQ=MONTHLY;INTERVAL=${input.interval.to_str()};COUNT=${input.count.to_str()}${
				if input.last_monday {
					";BYDAY=MO;BYSETPOS=-1"
				} else {
					""
				}
			};WKST=MO",
			inclusions: [anchor_text, "20240204", "20240331"],
			exclusions: if input.exclude_anchor {
				[anchor_text, "20240331"]
			} else {
				["20240331"]
			},
		}
		if exported != expected_parts or ICalDateRule.to_parts(parsed) != Ok(expected_parts) {
			crash "DATE export differs from canonical property model"
		}
		definition = DateRecurrence.definition(rule)
		if definition.anchor != anchor or definition.spec.pattern != pattern {
			crash "DATE definition lost anchor or selectors"
		}
		oversized = match DateRecurrence.new(definition.anchor, { ..definition.spec, termination: Count(2147483648 + input.count.to_u64()) }) {
			Ok(value) => value
			Err(_) => crash "Valid native large COUNT rejected"
		}
		if ICalDateRule.to_parts(oversized) != Err(OutOfRange("COUNT")) {
			crash "DATE export narrowed native COUNT"
		}
		restored = match ICalDateRule.parse(exported) {
			Ok(value) => value
			Err(_) => crash "Canonical DATE properties failed import"
		}
		if ICalDateRule.to_parts(restored) != Ok(exported) {
			crash "DATE canonical spelling is unstable"
		}
		restored_cursor = match DateRecurrence.cursor(restored, window) {
			Ok(value) => value
			Err(_) => crash "Restored query rejected"
		}
		match ICalDateRule.parse({ ..parts, rule: "${text};COUNT=1" }) {
			Err(Duplicate("COUNT")) => {}
			_ => crash "Duplicate rule part accepted"
		}
		parsed_cursor = match DateRecurrence.cursor(parsed, window) {
			Ok(value) => value
			Err(_) => crash "Valid parsed query rejected"
		}
		cursor = match DateRecurrence.cursor(rule, window) {
			Ok(value) => value
			Err(_) => crash "Valid query rejected"
		}
		# A published fact seeds weekday walking: 2024-01-01 was Monday.
		var $elapsed = 0.U64
		var $month_index = 0.U64
		var $counted = 0.U64
		var $expected = []
		for year in [2024.I64, 2025] {
			var $month = 1.U8
			while $month <= 12 {
				length = month_length(year, $month)
				var $last_monday = 0.U8
				var $day = 1.U8
				while $day <= length {
					if U64.mod_by($elapsed + $day.to_u64() - 1, 7) == 0 {
						$last_monday = $day
					}
					$day = $day + 1
				}
				if U64.mod_by($month_index, input.interval.to_u64()) == 0 and $counted < input.count.to_u64() {
					if input.last_monday or length == 31 {
						$expected = $expected.append(
							date(
								year,
								$month,
								if input.last_monday {
									$last_monday
								} else {
									31
								},
							),
						)
						$counted = $counted + 1
					}
				}
				$elapsed = $elapsed + length.to_u64()
				$month_index = $month_index + 1
				$month = $month + 1
			}
		}
		check_boundary_cutoff(input)
		check_boundary_exclusions(input)
		check_subdaily(input)
		check_timed(input, anchor, pattern, window, $expected)
		# Direct ordered set model; deliberately not the cursor's two-stream merge.
		var $normalized = []
		for candidate in $expected.concat(inclusions).sort_with(
			|a, b| if a < b {
				Before
			} else if a > b {
				After
			} else {
				Same
			},
		) {
			if candidate >= window.start and candidate < window.end and !exclusions.contains(candidate) and !$normalized.contains(candidate) {
				$normalized = $normalized.append(candidate)
			}
		}
		limits = { max_steps: input.work.to_u64(), max_buffered: 366.U64, max_occurrences: 1.U64 }
		var $current = cursor
		var $observed = []
		var $batches = 0.U64
		while $batches < 5000 {
			batch = match DateRecurrence.Cursor.collect($current, limits) {
				Ok(value) => value
				Err(_) => crash "Supported recurrence failed"
			}
			if batch.steps > limits.max_steps or batch.buffered > limits.max_buffered or batch.dates.len() > 1 {
				crash "Recurrence exceeded budget"
			}
			$observed = $observed.concat(batch.dates)
			match batch.status {
				Complete => {
					if $observed != $normalized {
						crash "Recurrence differs from finite calendar model"
					}
					parsed_batch = match DateRecurrence.Cursor.collect(parsed_cursor, { max_steps: 10000, max_buffered: 366, max_occurrences: 100 }) {
						Ok(value) => value
						Err(_) => crash "Parsed recurrence failed"
					}
					match parsed_batch.status {
						Complete => if parsed_batch.dates != $normalized {
							crash "RFC adapter differs from calendar model"
						}
						Limited(_) => crash "Parsed recurrence unexpectedly limited"
					}
					check_consumers(cursor, limits, $normalized)
					check_consumers(restored_cursor, limits, $normalized)
					check_all_day(rule, window, $normalized)
					return Fuzz.keep
				}
				Limited(progress) => {
					$current = progress.cursor
				}
			}
			$batches = $batches + 1
		}
		crash "Recurrence resumption failed to progress"
	}
}

# These semantic round trips are paired with independent models at callers.
rebuild_native = |rule| {
	definition = TimedRecurrence.definition(rule)
	restored = match TimedRecurrence.from_definition(definition) {
		Ok(value) => value
		Err(_) => crash "valid native declaration rejected"
	}
	if TimedRecurrence.definition(restored) != definition {
		crash "native declaration reconstruction lost fields"
	}
	restored
}

export_wrapper = |wrapper| {
	definition = ICalTimedRule.definition(wrapper)
	rebuilt = match ICalTimedRule.new({ ..definition, rule: rebuild_native(definition.rule) }) {
		Ok(value) => value
		Err(_) => crash "valid typed timed wrapper rejected"
	}
	parts = match ICalTimedRule.to_parts(rebuilt) {
		Ok(value) => value
		Err(_) => crash "supported timed export rejected"
	}
	restored = match ICalTimedRule.parse(parts) {
		Ok(value) => value
		Err(_) => crash "canonical timed text rejected"
	}
	if ICalTimedRule.to_parts(restored) != Ok(parts) {
		crash "timed canonical output unstable"
	}
	restored
}

export_native = |rule, mode| {
	duration : ICalDuration
	duration = "PT1H"
	wrapper = match ICalTimedRule.new({ rule, duration, periods: [], mode }) {
		Ok(value) => value
		Err(_) => crash "supported native timed rule rejected"
	}
	definition = TimedRecurrence.definition(rule)
	large = match TimedRecurrence.from_definition({ ..definition, termination: Count(2147483648) }) {
		Ok(value) => value
		Err(_) => crash "native wide count rejected"
	}
	match ICalTimedRule.new({ rule: large, duration, periods: [], mode }) {
		Err(OutOfRange("COUNT")) => {}
		_ => crash "timed export narrowed COUNT"
	}
	ICalTimedRule.definition(export_wrapper(wrapper)).rule
}

check_consumers = |initial, limits, expected| {
	var $current = initial
	var $observed = []
	var $calls = 0.U64
	var $done = False
	while $done == False and $calls < 5000 {
		result = match DateRecurrence.Cursor.next($current, { max_steps: limits.max_steps, max_buffered: limits.max_buffered }) {
			Ok(value) => value
			Err(_) => crash "Next failed within the reference range"
		}
		if result.steps > limits.max_steps or result.buffered > limits.max_buffered {
			crash "Next exceeded its budget"
		}
		match result.status {
			End => {
				$done = True
			}
			Item(item) => {
				$observed = $observed.append(item.date)
				$current = item.cursor
			}
			Limited(progress) => {
				$current = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	if $done == False or $observed != expected {
		crash "Next differs from finite calendar model"
	}
	$current = initial
	$calls = 0
	$done = False
	var $value = { count: 0.U64, weighted: 0.U64 }
	while $done == False and $calls < 5000 {
		result = match DateRecurrence.Cursor.fold(
			$current,
			limits,
			$value,
			|acc, candidate| {
				fields = GregorianDate.to_fields(candidate)
				count = acc.count + 1
				updated = { count, weighted: acc.weighted + count * (fields.month.to_u64() * 31 + fields.day.to_u64()) }
				if U64.mod_by(count, 2) == 0 {
					Stop(updated)
				} else {
					Continue(updated)
				}
			},
		) {
			Ok(batch) => batch
			Err(_) => crash "Fold failed within the reference range"
		}
		if result.steps > limits.max_steps or result.occurrences > limits.max_occurrences or result.buffered > limits.max_buffered {
			crash "Fold exceeded its budget"
		}
		$value = result.value
		match result.status {
			Complete => {
				$done = True
			}
			Stopped(remaining) => {
				$current = remaining
			}
			Limited(progress) => {
				$current = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	var $weighted = 0.U64
	var $index = 1.U64
	for candidate in expected {
		fields = GregorianDate.to_fields(candidate)
		$weighted = $weighted + $index * (fields.month.to_u64() * 31 + fields.day.to_u64())
		$index = $index + 1
	}
	if $done == False or $value.count != expected.len() or $value.weighted != $weighted {
		crash "Stopped fold differs from calendar model"
	}
	var $chunked = []
	var $complete = False
	var $chunks = 0.U64
	for result in DateRecurrence.Cursor.chunks(initial, limits) {
		batch = match result {
			Ok(chunk) => chunk
			Err(_) => crash "Chunk iterator failed in reference range"
		}
		if $complete == True or $chunks >= 5000 {
			crash "Invalid chunk iterator termination"
		}
		$chunked = $chunked.concat(batch.dates)
		match batch.status {
			Complete => {
				$complete = True
			}
			Limited(_) => {}
		}
		$chunks = $chunks + 1
	}
	if $complete == False or $chunked != expected {
		crash "Chunk iterator differs from calendar model"
	}
}

date = |year, month, day| match GregorianDate.from_fields({ year, month, day }) {
	Ok(value) => value
	Err(_) => crash "Invalid model date"
}

month_length = |year, month| match month {
	2 => if year == 2024 {
		29.U8
	} else {
		28
	}
	4 | 6 | 9 | 11 => 30
	_ => 31
}

# The date oracle above remains independent; fixed UTC supplies exactly one
# 86400-second selection for each generated date, with a stable source ID.
check_all_day = |rule, window, expected| {
	rules = fixture_rules(2000000000000000)
	var $current = match AllDayRecurrence.new(42.U64, rule, window, 1, rules) {
		Ok(value) => value
		Err(_) => crash "all-day construction"
	}
	var $observed = []
	var $calls = 0.U64
	while $calls < 5000 {
		batch = match AllDayRecurrence.next($current, { max_date_steps: 7, max_date_buffered: 366, max_zone_segments: 1, max_zone_members: 1 }) {
			Ok(value) => value
			Err(_) => crash "all-day next"
		}
		if batch.date_steps > 7 or batch.zone_segments > 1 {
			crash "all-day budget exceeded"
		}
		match batch.status {
			End => {
				if $observed != expected {
					crash "all-day dates differ from calendar oracle"
				}
				return {}
			}
			Limited(progress) => {
				$current = progress.cursor
			}
			Item(item) => {
				identity = AllDayOccurrence.id(item.occurrence)
				if identity.series != 42 or Coverage.coordinate_width(AllDayOccurrence.coverage(item.occurrence)) != Ok(PosixDelta.from_microseconds(86400000000)) {
					crash "all-day identity or width"
				}
				$observed = $observed.append(identity.date)
				$current = item.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "all-day resumption did not finish"
}

fixture_rules = |upper| {
	validity = match PosixSpan.new(PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(upper)) {
		Ok(value) => value
		Err(_) => crash "validity"
	}
	match ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 }) {
		Ok(value) => value
		Err(_) => crash "rules"
	}
}

# This model expands a fixed two-clock grid over the independently calculated
# dates. COUNT is applied before the query window. Last-Monday BYSETPOS selects
# the last clock of the last Monday, rather than both clocks on that date.
check_timed = |input, anchor, pattern, window, dates| {
	anchor_clock = clock(
		if input.last_monday {
			17
		} else {
			9
		},
	)
	base_rule = match TimedRecurrence.new(
		{ date: anchor, clock: anchor_clock },
		{
			calendar: pattern,
			clocks: { hours: [17, 9, 17], minutes: [], seconds: [] },
			termination: Count(input.count.to_u64()),
			by_set_pos: if input.last_monday {
				[-1]
			} else {
				[]
			},
		},
	) {
		Ok(value) => value
		Err(_) => crash "timed construction"
	}
	excluded_label = LocalDateTime.new(CalendarDate.from_gregorian(anchor), anchor_clock)
	rule = match TimedRecurrence.with_exclusions(
		base_rule,
		if input.exclude_anchor {
			[excluded_label, excluded_label]
		} else {
			[]
		},
	) {
		Ok(value) => value
		Err(_) => crash "timed exclusions"
	}
	check_timed_explanation(rule, input, excluded_label)
	start = local(window.start, 0)
	end = local(window.end, 0)
	rules = fixture_rules(2000000000000000)
	var $current = match TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: RequireUnique, gap: RejectGap }) {
		Ok(value) => value
		Err(_) => crash "timed window"
	}
	var $expected_sources = []
	var $expected_boundaries = []
	var $count = 0.U64
	for candidate in dates {
		hours = if input.last_monday {
			[17.U8]
		} else {
			[9.U8, 17]
		}
		for hour in hours {
			if $count < input.count.to_u64() {
				$count = $count + 1
				if candidate >= window.start and candidate < window.end and (!input.exclude_anchor or !LocalDateTime.same_position(local(candidate, hour), excluded_label)) {
					$expected_sources = $expected_sources.append(local(candidate, hour))
					fields = GregorianDate.to_fields(candidate)
					var $days = if fields.year == 2024 {
						0.I64
					} else {
						366.I64
					}
					var $month = 1.U8
					while $month < fields.month {
						$days = $days + month_length(fields.year, $month).to_i64()
						$month = $month + 1
					}
					$days = $days + fields.day.to_i64() - 1
					# 2024-01-01T00:00Z is Unix second 1704067200.
					$expected_boundaries = $expected_boundaries.append(PosixBoundary.from_microseconds((1704067200 + $days * 86400 + hour.to_i64() * 3600) * 1000000))
				}
			}
		}
	}
	check_timed_batches($current, input.work.to_u64(), $expected_sources, $expected_boundaries)
	# R11/R14: restored definitions are evaluated against the independently
	# walked calendar/clock grid, not merely against their own serialization.
	restored = export_native(rule, Utc)
	restored_cursor = match TimedRecurrence.cursor(restored, { start, end }, { rules, occurrence: RequireUnique, gap: RejectGap }) {
		Ok(value) => value
		Err(_) => crash "restored timed window"
	}
	check_timed_batches(restored_cursor, input.work.to_u64(), $expected_sources, $expected_boundaries)
	check_schedule(rule, { start, end }, rules, input.work.to_u64(), $expected_sources, $expected_boundaries, anchor, anchor_clock, input.exclude_anchor, input)

	var $sources = []
	var $boundaries = []
	var $calls = 0.U64
	while $calls < 10000 {
		batch = match TimedRecurrence.Cursor.next($current, { max_steps: input.work.to_u64(), max_buffered: 10, max_zone_segments: 1, max_zone_candidates: 1 }) {
			Ok(value) => value
			Err(_) => crash "timed interpretation"
		}
		if batch.steps > input.work.to_u64() or batch.zone_segments > 1 or batch.buffered > 10 or batch.zone_buffered > 1 {
			crash "timed budget exceeded"
		}
		match batch.status {
			End => {
				if $sources != $expected_sources or $boundaries != $expected_boundaries {
					crash "timed recurrence differs from independent clock/calendar grid"
				}
				return {}
			}
			Limited(progress) => {
				$current = progress.cursor
			}
			Item(item) => {
				check_duration(item.occurrence, input.work)
				$sources = $sources.append(TimedRecurrence.Occurrence.source(item.occurrence))
				$boundaries = $boundaries.append(TimedRecurrence.Occurrence.boundary(item.occurrence))
				match TimedRecurrence.Occurrence.adjustment(item.occurrence) {
					Exact => {}
					BeforeGap(_) => crash "UTC adjustment"
				}
				$current = item.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "timed resumption did not finish"
}

clock = |hour| match ClockTime.from_fields({ hour, minute: 0, second: 0, microsecond: 0 }) {
	Ok(value) => value
	Err(_) => crash "model clock"
}

local = |date_value, hour| LocalDateTime.new(CalendarDate.from_gregorian(date_value), clock(hour))

check_timed_batches = |initial, work, expected_sources, expected_boundaries| {
	var $current = initial
	var $sources = []
	var $boundaries = []
	var $calls = 0.U64
	while $calls < 10000 {
		batch = match TimedRecurrence.Cursor.collect(
			$current,
			{
				work: { max_steps: work, max_buffered: 10, max_zone_segments: 2, max_zone_candidates: 1 },
				max_occurrences: 2,
			},
		) {
			Ok(value) => value
			Err(_) => crash "timed collection failed"
		}
		if batch.steps > work or batch.zone_segments > 2 or batch.occurrences.len() > 2 {
			crash "timed batch exceeded shared work or output budget"
		}
		for occurrence in batch.occurrences {
			$sources = $sources.append(TimedRecurrence.Occurrence.source(occurrence))
			$boundaries = $boundaries.append(TimedRecurrence.Occurrence.boundary(occurrence))
		}
		match batch.status {
			Complete => {
				if $sources != expected_sources or $boundaries != expected_boundaries {
					crash "timed batches differ from calendar grid"
				}
				return {}
			}
			Limited(progress) => {
				$current = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "timed batches did not finish"
}

# A finite integer-second grid, independent of SubdailyPattern's clock seeks.
# Expand lower fields, filter seconds at SECONDLY frequency, then apply source
# truncation, COUNT and a later query. The epoch day makes UTC boundaries direct.
check_subdaily = |input| {
	mode = U8.rem_by(input.query_month, 3)
	frequency = match mode {
		0 => Hourly
		1 => Minutely
		_ => Secondly
	}
	unit = match mode {
		0 => 3600.I64
		1 => 60.I64
		_ => 1.I64
	}
	anchor_second = if mode == 0 {
		84650.I64
	} else {
		86390.I64
	}
	fraction = input.work.to_i64()
	anchor_clock = match ClockTime.from_microseconds_since_midnight(anchor_second * 1000000 + fraction) {
		Ok(value) => value
		Err(_) => crash "subdaily anchor clock"
	}
	anchor = date(1970, 1, 1)
	start = LocalDateTime.new(CalendarDate.from_gregorian(anchor), anchor_clock)
	query = match FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds((anchor_second + 30) * 1000000), Gregorian) {
		Ok(value) => value
		Err(_) => crash "subdaily query"
	}
	end = local(date(1970, 1, 3), 0)
	base_rule = match TimedRecurrence.new_subdaily(
		{ date: anchor, clock: anchor_clock },
		{
			pattern: {
				frequency,
				interval: input.interval.to_i64(),
				calendar: { by_month: [], by_month_day: [], by_year_day: [], by_day: [] },
				clocks: {
					hours: [],
					minutes: if mode == 0 {
						[0, 30]
					} else {
						[]
					},
					seconds: [10, 50],
				},
			},
			termination: Count(input.count.to_u64()),
			by_set_pos: [],
		},
	) {
		Ok(value) => value
		Err(_) => crash "subdaily grid construction"
	}
	rule = match TimedRecurrence.with_exclusions(base_rule, [start]) {
		Ok(value) => value
		Err(_) => crash "subdaily exclusions"
	}
	check_subdaily_explanation(rule, input, start, mode)
	declaration = TimedRecurrence.definition(rule)
	rebuilt = rebuild_native(rule)
	duration = match ICalDuration.parse("PT${input.work.to_str()}H") {
		Ok(value) => value
		Err(_) => crash "fixed duration"
	}
	match ICalTimedRule.new({ rule: rebuilt, duration, periods: [], mode: Utc }) {
		Err(PrecisionLoss("DTSTART")) => {}
		_ => crash "subdaily export silently discarded generated microseconds"
	}
	whole_anchor = match ClockTime.from_microseconds_since_midnight(anchor_second * 1000000) {
		Ok(value) => value
		Err(_) => crash "whole second anchor"
	}
	whole_start = LocalDateTime.new(CalendarDate.from_gregorian(anchor), whole_anchor)
	whole = match TimedRecurrence.from_definition({ ..declaration, anchor: whole_start, exclusions: [whole_start] }) {
		Ok(value) => export_native(value, Utc)
		Err(_) => crash "whole second edited declaration"
	}
	window_start = if input.exclude_anchor {
		query
	} else {
		start
	}
	var $current = match TimedRecurrence.cursor(rebuilt, { start: window_start, end }, { rules: fixture_rules(259200000000), occurrence: RequireUnique, gap: RejectGap }) {
		Ok(value) => value
		Err(_) => crash "subdaily grid cursor"
	}
	var $expected = []
	var $count = 0.U64
	var $index = 0.I64
	while $index < 1000 and $count < input.count.to_u64() {
		base = I64.div_trunc_by(anchor_second, unit) * unit + $index * input.interval.to_i64() * unit
		offsets = match mode {
			0 => [10.I64, 50, 1810, 1850]
			1 => [10.I64, 50]
			_ => [0.I64]
		}
		for offset in offsets {
			candidate = base + offset
			seconds = I64.mod_by(candidate, 60)
			if candidate >= anchor_second and (mode != 2 or seconds == 10 or seconds == 50) and $count < input.count.to_u64() {
				$count = $count + 1
				if candidate != anchor_second and (!input.exclude_anchor or candidate >= anchor_second + 30) {
					$expected = $expected.append(candidate * 1000000 + fraction)
				}
			}
		}
		$index = $index + 1
	}
	if $count != input.count.to_u64() {
		crash "finite subdaily model too short"
	}
	whole_window = {
		start: if input.exclude_anchor {
			query
		} else {
			whole_start
		},
		end,
	}
	whole_cursor = match TimedRecurrence.cursor(whole, whole_window, { rules: fixture_rules(259200000000), occurrence: RequireUnique, gap: RejectGap }) {
		Ok(value) => value
		Err(_) => crash "restored whole-second subdaily cursor"
	}
	whole_boundaries = $expected.map(|micros| PosixBoundary.from_microseconds(micros - fraction))
	whole_sources = whole_boundaries.map(
		|boundary| match FixedOffset.project(FixedOffset.from_seconds(0), boundary, Gregorian) {
			Ok(value) => value
			Err(_) => crash "bounded expected source"
		},
	)
	check_timed_batches(whole_cursor, input.work.to_u64(), whole_sources, whole_boundaries)
	# Preparation must preserve the native microsecond remainder even when
	# RFC interchange correctly rejects it. Compare actual appointment starts
	# against the same independent integer grid, with a one-microsecond ending.
	fractional_context = { rules: fixture_rules(259200000000), occurrence: RequireUnique, gap: RejectGap }
	fractional_window = { start: window_start, end }
	fractional_duration = Coordinate(PosixDelta.from_microseconds(1))
	fractional_definition = checked_definition(ScheduleDefinition.from_native({ rule: rebuilt, duration: fractional_duration, overrides: [], context: fractional_context }) ?? crash "fractional schedule preparation")
	fractional_cursor = ScheduleDefinition.cursor(73.U64, fractional_definition, fractional_window) ?? crash "fractional prepared cursor"
	check_fractional_schedule(fractional_cursor, input.work.to_u64(), $expected)
	fractional_direct = TimedSchedule.new(73.U64, rebuilt, fractional_window, fractional_duration, fractional_context) ?? crash "fractional direct cursor"
	check_fractional_schedule(fractional_direct, input.work.to_u64(), $expected)
	var $observed = []
	var $calls = 0.U64
	while $calls < 10000 {
		batch = match TimedRecurrence.Cursor.collect($current, { work: { max_steps: input.work.to_u64(), max_buffered: 1, max_zone_segments: 2, max_zone_candidates: 1 }, max_occurrences: 2 }) {
			Ok(value) => value
			Err(_) => crash "subdaily grid execution"
		}
		if batch.steps > input.work.to_u64() or batch.zone_segments > 2 or batch.occurrences.len() > 2 {
			crash "subdaily grid budget"
		}
		for occurrence in batch.occurrences {
			$observed = $observed.append(PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(occurrence)))
		}
		match batch.status {
			Complete => {
				if $observed != $expected {
					crash "subdaily differs from integer-second model"
				}
				return {}
			}
			Limited(progress) => {
				$current = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "subdaily grid resumption did not terminate"
}

# Prepared definitions remain usable as keys independently of query cursors.
checked_definition = |definition| {
	keyed = Dict.insert(Dict.empty(), definition, 71.U8)
	if Dict.get(keyed, definition) != Ok(71) {
		crash "schedule definition hash equality"
	}
	definition
}

check_fractional_schedule = |initial, work, expected| {
	var $cursor = initial
	var $observed = []
	var $calls = 0.U64
	while $calls < 10000 {
		batch = TimedSchedule.collect($cursor, { work: { max_steps: work, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 1 }, max_occurrences: 1 }) ?? crash "fractional schedule execution"
		if batch.steps > work or batch.zone_segments > 1 or batch.occurrences.len() > 1 {
			crash "fractional schedule budget"
		}
		for item in batch.occurrences {
			span = TimedOccurrence.span(item)
			if TimedOccurrence.id(item).series != 73 or PosixSpan.coordinate_width(span) != Ok(PosixDelta.from_microseconds(1)) {
				crash "fractional schedule identity or width"
			}
			$observed = $observed.append(PosixBoundary.to_microseconds(PosixSpan.start(span)))
		}
		match batch.status {
			Complete => {
				if $observed != expected {
					crash "fractional schedule differs from integer model"
				}
				return {}
			}
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "fractional schedule resumption did not terminate"
}

# In fixed UTC, one calendar day plus one coordinate hour is exactly 25
# coordinate hours. The same source with a fixed one-hour duration stays 1h.
check_duration = |start, amount| {
	# Generated H/M/S fields use an independent integer-second oracle. Parse,
	# canonical reparse and shared occurrence execution all retain that width.
	weeks = match ICalDuration.parse("P${amount.to_str()}W") {
		Ok(value) => value
		Err(_) => crash "valid generated weeks rejected"
	}
	if ICalDuration.components(weeks) != { days: amount.to_i64() * 7, seconds: 0.I64 } or ICalDuration.parse(ICalDuration.to_text(weeks)) != Ok(weeks) {
		crash "nominal weeks differ from seven-day model"
	}
	text = "PT${amount.to_str()}H${amount.to_str()}M${amount.to_str()}S"
	parsed = match ICalDuration.parse(text) {
		Ok(value) => value
		Err(_) => crash "valid generated duration rejected"
	}
	if ICalDuration.parse(ICalDuration.to_text(parsed)) != Ok(parsed) or ICalDuration.parse("${text}S") != Err(Malformed) {
		crash "duration grammar or semantic round trip"
	}
	parsed_cursor = match TimedOccurrence.cursor(42.U64, start, ICalDuration.to_duration(parsed)) {
		Ok(value) => value
		Err(_) => crash "parsed duration construction"
	}
	parsed_batch = match TimedOccurrence.Cursor.collect(parsed_cursor, { max_segments: 0, max_candidates: 0 }) {
		Ok(value) => value
		Err(_) => crash "parsed duration execution"
	}
	expected_width = amount.to_i64() * 3661000000
	match parsed_batch.status {
		Complete(value) => if PosixSpan.coordinate_width(TimedOccurrence.span(value)) != Ok(PosixDelta.from_microseconds(expected_width)) {
			crash "parsed duration differs from integer-second oracle"
		}
		Limited(_) => crash "coordinate duration used zone budget"
	}

	base = PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(start))
	for duration in [Coordinate(PosixDelta.from_microseconds(3600000000)), Calendar({ delta: CalendarDelta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(3600000000), occurrence: RequireUnique, gap: RejectGap })] {
		cursor = match TimedOccurrence.cursor(42.U64, start, duration) {
			Ok(value) => value
			Err(_) => crash "duration construction"
		}
		batch = match TimedOccurrence.Cursor.collect(cursor, { max_segments: 1, max_candidates: 1 }) {
			Ok(value) => value
			Err(_) => crash "duration resolution"
		}
		value = match batch.status {
			Complete(completed) => completed
			Limited(_) => crash "UTC duration should complete"
		}
		expected = match duration {
			Coordinate(_) => 3600000000.I64
			Calendar(_) => 90000000000.I64
		}
		if TimedOccurrence.id(value) != 42 or PosixSpan.coordinate_width(TimedOccurrence.span(value)) != Ok(PosixDelta.from_microseconds(expected)) or PosixSpan.start(TimedOccurrence.span(value)) != PosixBoundary.from_microseconds(base) {
			crash "duration differs from UTC grid"
		}
	}
}

# Independent UTC grid: calendar day plus hour has a 25-hour coordinate width.
# One shared zone step forces a pause between start and end interpretation.
check_schedule = |base_rule, window, rules, work, base_sources, base_boundaries, anchor, anchor_clock, exclude_anchor, input| {
	inclusions = [{ date: date(2024, 1, 1), clock: clock(9) }, { date: date(2024, 2, 4), clock: clock(9) }, { date: anchor, clock: anchor_clock }, { date: date(2024, 2, 4), clock: clock(9) }]
	rule = match TimedRecurrence.with_inclusions(base_rule, inclusions) {
		Ok(value) => value
		Err(_) => crash "schedule inclusions"
	}
	var $expected = []
	var $position = 0.U64
	for source in base_sources {
		boundary = match base_boundaries.get($position) {
			Ok(value) => value
			Err(_) => crash "model boundary"
		}
		$expected = $expected.append({ source, boundary })
		$position = $position + 1
	}
	for inclusion in inclusions {
		source = LocalDateTime.new(CalendarDate.from_gregorian(inclusion.date), inclusion.clock)
		var $duplicate = Bool.False
		for item in $expected {
			$duplicate = $duplicate or LocalDateTime.same_position(item.source, source)
		}
		removed = exclude_anchor and inclusion.date == anchor and inclusion.clock == anchor_clock
		if !$duplicate and !removed and LocalDateTime.compare_position(source, window.start) != LT and LocalDateTime.compare_position(source, window.end) == LT {
			fields = GregorianDate.to_fields(inclusion.date)
			days = if fields.month == 1 {
				fields.day.to_i64() - 1
			} else {
				31 + fields.day.to_i64() - 1
			}
			micros = (1704067200 + days * 86400) * 1000000 + ClockTime.to_microseconds_since_midnight(inclusion.clock)
			$expected = $expected.append({ source, boundary: PosixBoundary.from_microseconds(micros) })
		}
	}
	$expected = $expected.sort_with(
		|a, b| if a.boundary < b.boundary {
			Before
		} else if a.boundary > b.boundary {
			After
		} else {
			Same
		},
	)
	expected_sources = $expected.map(|item| item.source)
	expected_boundaries = $expected.map(|item| item.boundary)
	anchor_source = LocalDateTime.new(CalendarDate.from_gregorian(anchor), anchor_clock)
	extra_source = local(date(2024, 2, 4), 9)
	# The generator constrains work to 1..128.
	short : TimedOccurrence.Duration
	short = Coordinate(PosixDelta.from_microseconds(work.to_i64_wrap() * 3600000000))
	extra : TimedOccurrence.Duration
	extra = Calendar({ delta: CalendarDelta.days(2), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
	anchor_boundary = match FixedOffset.resolve(FixedOffset.from_seconds(0), anchor_source) {
		Ok(value) => value
		Err(_) => crash "fixture anchor"
	}
	anchor_end = match PosixBoundary.shift(anchor_boundary, PosixDelta.from_microseconds(work.to_i64_wrap() * 3600000000)) {
		Ok(value) => value
		Err(_) => crash "fixture end"
	}
	# Explicit endpoint overrides retain the same independent UTC widths.
	# Alternate duration and explicit forms; duplicates are one definition.
	short_ending = if exclude_anchor {
		After(short)
	} else {
		AtBoundary(anchor_end)
	}
	extra_ending = if exclude_anchor {
		After(extra)
	} else {
		AtLocal({ source: local(date(2024, 2, 6), 9), occurrence: First, gap: UseOffsetBeforeGap })
	}
	overrides = [{ source: anchor_source, ending: short_ending }, { source: extra_source, ending: extra_ending }, { source: anchor_source, ending: short_ending }]
	(direct, prepared) = if exclude_anchor {
		default_duration = Calendar({ delta: CalendarDelta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(3600000000), occurrence: RequireUnique, gap: RejectGap })
		context = { rules, occurrence: RequireUnique, gap: RejectGap }
		declaration = checked_definition(ScheduleDefinition.from_native({ rule, duration: default_duration, overrides, context }) ?? crash "native schedule definition")
		prepared_cursor = ScheduleDefinition.cursor(42.U64, declaration, window) ?? crash "native definition cursor"
		direct_cursor = match TimedSchedule.new_with_endings(42.U64, rule, window, default_duration, overrides, context) {
			Ok(value) => value
			Err(_) => crash "schedule construction"
		}
		(direct_cursor, prepared_cursor)
	} else {
		fields = GregorianDate.to_fields(anchor)
		hour = ClockTime.to_fields(anchor_clock).hour
		hour_text = if hour < 10 {
			"0${hour.to_str()}"
		} else {
			hour.to_str()
		}
		start_text = "202401${fields.day.to_str()}T${hour_text}0000"
		anchor_text = "${start_text}/PT${work.to_str()}H"
		anchor_period = match ICalPeriod.parse(anchor_text) {
			Ok(value) => value
			Err(_) => crash "generated anchor period"
		}
		if ICalPeriod.parse(ICalPeriod.to_text(anchor_period)) != Ok(anchor_period) {
			crash "period semantic text round trip"
		}
		selectors = if input.last_monday {
			";BYDAY=MO;BYSETPOS=-1"
		} else {
			""
		}
		parsed = match ICalTimedRule.parse({ start: start_text, rule: "FREQ=MONTHLY;INTERVAL=${input.interval.to_str()};COUNT=${input.count.to_str()};BYHOUR=9,17${selectors}", mode: Zoned, duration: "P1DT1H", inclusions: ["20240101T090000", "20240204T090000", start_text, "20240204T090000"], exclusions: [], periods: [anchor_text, "20240204T090000/20240206T090000", anchor_text] }) {
			Ok(value) => value
			Err(_) => crash "generated timed RFC rule rejected"
		}
		# Preserve PERIOD ending intent and duplicate definitions across exchange;
		# the existing independent grid below checks restored identities/widths.
		restored = export_wrapper(parsed)
		declaration = checked_definition(ScheduleDefinition.from_ical({ rule: restored, context: Local(rules) }) ?? crash "iCalendar schedule definition")
		prepared_cursor = ScheduleDefinition.cursor(42.U64, declaration, window) ?? crash "iCalendar definition cursor"
		direct_cursor = match ICalTimedRule.schedule(42.U64, restored, window, Local(rules)) {
			Ok(value) => value
			Err(_) => crash "timed RFC schedule adaptation"
		}
		(direct_cursor, prepared_cursor)
	}
	var $current = prepared
	var $direct = direct

	var $index = 0.U64
	var $calls = 0.U64
	while $calls < 10000 {
		batch = match TimedSchedule.collect($current, { work: { max_steps: work, max_buffered: 11, max_zone_segments: 1, max_zone_candidates: 1 }, max_occurrences: 1 }) {
			Ok(value) => value
			Err(_) => crash "schedule collection"
		}
		direct_batch = TimedSchedule.collect($direct, { work: { max_steps: work, max_buffered: 11, max_zone_segments: 1, max_zone_candidates: 1 }, max_occurrences: 1 }) ?? crash "direct schedule collection"
		if direct_batch.occurrences.map(|item| { id: TimedOccurrence.id(item), span: TimedOccurrence.span(item) }) != batch.occurrences.map(|item| { id: TimedOccurrence.id(item), span: TimedOccurrence.span(item) }) {
			crash "prepared schedule changed direct identities or spans"
		}
		match (direct_batch.status, batch.status) {
			(Complete, Complete) => {}
			(Limited(direct_progress), Limited(_)) => {
				$direct = direct_progress.cursor
			}
			_ => crash "prepared schedule changed bounded completion"
		}
		if batch.steps > work or batch.zone_segments > 1 or batch.occurrences.len() > 1 {
			crash "schedule exceeded shared budget"
		}
		for occurrence in batch.occurrences {
			expected_source = match expected_sources.get($index) {
				Ok(value) => value
				Err(_) => crash "extra schedule occurrence"
			}
			expected_boundary = match expected_boundaries.get($index) {
				Ok(value) => value
				Err(_) => crash "missing expected boundary"
			}
			expected_width = if expected_source == anchor_source {
				work.to_i64_wrap() * 3600000000
			} else if expected_source == extra_source {
				172800000000.I64
			} else {
				90000000000.I64
			}
			identity = TimedOccurrence.id(occurrence)
			if identity.series != 42 or identity.source != expected_source or PosixSpan.start(TimedOccurrence.span(occurrence)) != expected_boundary or PosixSpan.coordinate_width(TimedOccurrence.span(occurrence)) != Ok(PosixDelta.from_microseconds(expected_width)) {
				crash "schedule differs from independent UTC grid"
			}
			$index = $index + 1
		}
		match batch.status {
			Complete => {
				if $index != expected_sources.len() {
					crash "schedule lost occurrences"
				}
				return {}
			}
			Limited(progress) => {
				$current = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "schedule failed to make bounded progress"
}

# Independent small source grid, with one explicitly modeled offset jump.
# Filter by resolved boundary without assuming that source order is UTC order.
check_boundary_cutoff = |input| {
	d = date(1970, 1, 1)
	cutoff = input.count.to_i64() * 1800000000
	rule = match TimedRecurrence.new({ date: d, clock: clock(0) }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [0, 1, 2, 3, 4, 5], minutes: [0, 30], seconds: [] }, termination: UntilBoundary(PosixBoundary.from_microseconds(cutoff)), by_set_pos: [] }) {
		Ok(value) => value
		Err(_) => crash "cutoff grid rule"
	}
	validity = cutoff_span(-86400000000, 172800000000)
	offset = if input.exclude_anchor {
		-3600.I32
	} else {
		3600.I32
	}
	rules = match ZoneRules.new_bounded(
		"Synthetic/Grid",
		"v1",
		validity,
		FixedOffset.from_seconds(0),
		[{ at: PosixBoundary.from_microseconds(7200000000), offset: FixedOffset.from_seconds(offset) }],
		{
			minimum: if offset < 0 {
				offset
			} else {
				0
			},
			maximum: if offset > 0 {
				offset
			} else {
				0
			},
		},
	) {
		Ok(value) => value
		Err(_) => crash "grid rules"
	}
	var $expected = []
	for half_hour in [0.I64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] {
		source = half_hour * 1800000000
		boundary = if offset > 0 and source >= 10800000000 {
			source - 3600000000
		} else if offset < 0 and source >= 7200000000 {
			source + 3600000000
		} else {
			source
		}
		if boundary <= cutoff {
			$expected = $expected.append({ source, boundary })
		}
	}
	var $cursor = match TimedRecurrence.cursor(rule, { start: local(d, 0), end: local(date(1970, 1, 2), 0) }, { rules, occurrence: First, gap: UseOffsetBeforeGap }) {
		Ok(value) => value
		Err(_) => crash "grid cursor"
	}
	var $observed = []
	var $calls = 0.U64
	while $calls < 500 {
		batch = match TimedRecurrence.Cursor.collect($cursor, { work: { max_steps: input.work.to_u64(), max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 2 }, max_occurrences: 1 }) {
			Ok(value) => value
			Err(_) => crash "grid cutoff execution"
		}
		for value in batch.occurrences {
			$observed = $observed.append({ source: ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(TimedRecurrence.Occurrence.source(value))), boundary: PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(value)) })
		}
		match batch.status {
			Complete => {
				if $observed != $expected {
					crash "UTC cutoff differs from piecewise offset grid"
				}
				return {}
			}
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "cutoff grid did not terminate under finite resumption budget"
}

cutoff_span = |lower, upper| match PosixSpan.new(PosixBoundary.from_microseconds(lower), PosixBoundary.from_microseconds(upper)) {
	Ok(value) => value
	Err(_) => crash "valid cutoff fixture span"
}

# R11/R12/R14: declaration facts are compared with the generator inputs and
# independently known sorted exception dates, never the emitted result count.
# The calendar-table occurrence model above separately validates COUNT before
# exclusions. Explanation must keep that same declared COUNT even when the
# anchor is excluded, and must never enumerate an unbounded series.
recurrence_fact = |source, index| match Explanation.fact_at(source, index) {
	Item(fact) => SemanticFact.kind(fact)
	End => crash "Missing recurrence declaration fact"
}

check_recurrence_rendering = |source| {
	full = Explanation.plain(source, { max_facts: 128, max_utf8_bytes: 32768 })
	zero = Explanation.plain(source, { max_facts: 0, max_utf8_bytes: 32768 })
	tiny = Explanation.plain(source, { max_facts: 128, max_utf8_bytes: 1 })
	if full.status != Complete or full.visited_facts != Explanation.fact_count(source) or
		zero.status != Limited(FactLimit) or zero.visited_facts != 0 or !zero.text.is_empty() or
			tiny.status != Limited(ByteLimit) or tiny.text.count_utf8_bytes() > 1 {
		crash "Recurrence declaration rendering ignored budgets"
	}
	match Explanation.fact_at(source, U64.highest) {
		End => {}
		_ => crash "Huge recurrence fact index fabricated a fact"
	}
}

check_date_explanation = |rule, input, anchor| {
	source = Explanation.new(DateRecurrence(rule))
	selectors = if input.last_monday {
		[Weekday({ ordinal: 0, weekday: Monday }), SetPosition(-1)]
	} else {
		[]
	}
	inclusions = [anchor, date(2024, 2, 4), date(2024, 3, 31)]
	exclusions = if input.exclude_anchor {
		[anchor, date(2024, 3, 31)]
	} else {
		[date(2024, 3, 31)]
	}
	if recurrence_fact(source, 0) != RecurrenceDescription({ kind: DateRecurrence, anchor: Date(anchor), frequency: Monthly, interval: input.interval.to_i64(), week_start: Some(Monday), selector_count: selectors.len(), inclusion_count: 3, exclusion_count: exclusions.len() }) or
		recurrence_fact(source, 1) != RecurrenceTermination(Count(input.count.to_u64())) {
		crash "Date recurrence explanation lost source semantics or pre-exclusion COUNT"
	}
	var $index = 2.U64
	for selector in selectors {
		if recurrence_fact(source, $index) != RecurrenceSelector(selector) {
			crash "Date recurrence selector changed"
		}
		$index = $index + 1
	}
	for exception in inclusions {
		if recurrence_fact(source, $index) != RecurrenceException({ kind: Inclusion, source: Date(exception) }) {
			crash "Normalized date inclusion changed"
		}
		$index = $index + 1
	}
	for exception in exclusions {
		if recurrence_fact(source, $index) != RecurrenceException({ kind: Exclusion, source: Date(exception) }) {
			crash "Normalized date exclusion changed"
		}
		$index = $index + 1
	}
	if Explanation.fact_count(source) != $index {
		crash "Unexpected date recurrence facts"
	}
	check_recurrence_rendering(source)
}

check_timed_explanation = |rule, input, anchor| {
	source = Explanation.new(TimedRecurrence(rule))
	calendar_selectors = if input.last_monday {
		[Weekday({ ordinal: 0, weekday: Monday }), SetPosition(-1)]
	} else {
		[]
	}
	selectors = calendar_selectors.concat([Hour(9), Hour(17), Minute(0), Second(0), Microsecond(0)])
	exclusions = if input.exclude_anchor {
		[anchor]
	} else {
		[]
	}
	if recurrence_fact(source, 0) != RecurrenceDescription({ kind: TimedRecurrence, anchor: Local(anchor), frequency: Monthly, interval: input.interval.to_i64(), week_start: Some(Monday), selector_count: selectors.len(), inclusion_count: 0, exclusion_count: exclusions.len() }) or
		recurrence_fact(source, 1) != RecurrenceTermination(Count(input.count.to_u64())) {
		crash "Timed recurrence explanation changed anchor or pre-exclusion COUNT"
	}
	if recurrence_fact(source, 2) != RecurrencePolicy({ context: Required, occurrence: CallerSupplied, gap: CallerSupplied }) {
		crash "Native timed recurrence invented interpretation policies"
	}
	var $index = 3.U64
	for selector in selectors {
		if recurrence_fact(source, $index) != RecurrenceSelector(selector) {
			crash "Effective sorted clock/calendar selector changed"
		}
		$index = $index + 1
	}
	for exception in exclusions {
		if recurrence_fact(source, $index) != RecurrenceException({ kind: Exclusion, source: Local(exception) }) {
			crash "Normalized local exclusion changed"
		}
		$index = $index + 1
	}
	if Explanation.fact_count(source) != $index {
		crash "Unexpected timed recurrence facts"
	}
	check_recurrence_rendering(source)
}

# RFC 5545 extracted-property mode rules: floating UNTIL is a local label;
# UTC/zoned UNTIL is a POSIX cutoff. 1970-01-02T00:00:00Z = 86400000000us
# is an independent epoch anchor. No zone context is supplied for explanation.
check_rfc_explanation = |input| {
	for mode in [Floating, Zoned, Utc] {
		start_text = if mode == Utc {
			"19700101T000000Z"
		} else {
			"19700101T000000"
		}
		until_text = if mode == Floating {
			"19700102T000000"
		} else {
			"19700102T000000Z"
		}
		rule_text = if input.exclude_anchor {
			"FREQ=DAILY;UNTIL=${until_text}"
		} else {
			"FREQ=DAILY"
		}
		parsed = match ICalTimedRule.parse({ start: start_text, rule: rule_text, mode, duration: "P1D", inclusions: [start_text, start_text], exclusions: [start_text], periods: ["${start_text}/PT1H"] }) {
			Ok(value) => value
			Err(_) => crash "Valid RFC explanation fixture rejected"
		}
		source = Explanation.new(ICalTimedRule(parsed))
		anchor = local(date(1970, 1, 1), 0)
		termination = if input.exclude_anchor {
			if mode == Floating {
				UntilLocal(local(date(1970, 1, 2), 0))
			} else {
				UntilBoundary(PosixBoundary.from_microseconds(86400000000))
			}
		} else {
			Forever
		}
		if recurrence_fact(source, 0) != ICalTimedRuleDescription({ mode, period_count: 1 }) or
			recurrence_fact(source, 1) != RecurrencePolicy({
				context: if mode == Utc {
					FixedUtc
				} else {
					Required
				},
				occurrence: First,
				gap: UseOffsetBeforeGap,
			}) or
				recurrence_fact(source, 2) != ICalDurationDescription({ role: RecurrenceEnding, days: 1, seconds: 0 }) or
					recurrence_fact(source, 3) != ICalPeriodDescription({
						form: if mode == Utc {
							Utc
						} else {
							Local
						},
						start: anchor,
						ending: Duration({ days: 0, seconds: 3600 }),
					}) or
						recurrence_fact(source, 4) != RecurrenceDescription({ kind: TimedRecurrence, anchor: Local(anchor), frequency: Daily, interval: 1, week_start: Some(Monday), selector_count: 4, inclusion_count: 1, exclusion_count: 1 }) or
							recurrence_fact(source, 5) != RecurrenceTermination(termination) {
			crash "RFC explanation confused declared mode, duration, period or local/POSIX termination"
		}
		if recurrence_fact(source, 10) != RecurrenceException({ kind: Inclusion, source: Local(anchor) }) or
			recurrence_fact(source, 11) != RecurrenceException({ kind: Exclusion, source: Local(anchor) }) or Explanation.fact_count(source) != 12 {
			crash "RFC explicit inclusion and exclusion declaration lost"
		}
		var $selector_index = 6.U64
		for selector in [Hour(0), Minute(0), Second(0), Microsecond(0)] {
			if recurrence_fact(source, $selector_index) != RecurrenceSelector(selector) {
				crash "RFC inherited clock fields changed"
			}
			$selector_index = $selector_index + 1
		}
		check_recurrence_rendering(source)
	}
}

check_subdaily_explanation = |rule, input, anchor, mode| {
	frequency : SemanticFact.RecurrenceFrequency
	frequency = match mode {
		0 => Hourly
		1 => Minutely
		_ => Secondly
	}
	source = Explanation.new(TimedRecurrence(rule))
	# Subdaily limiting hours are unrestricted when omitted; minutes expand
	# [0,30] for hourly periods and are unrestricted for smaller periods.
	minute_count = if mode == 0 {
		2.U64
	} else {
		60.U64
	}
	count = 24 + minute_count + 2 + 1
	if recurrence_fact(source, 0) != RecurrenceDescription({ kind: TimedRecurrence, anchor: Local(anchor), frequency, interval: input.interval.to_i64(), week_start: None, selector_count: count, inclusion_count: 0, exclusion_count: 1 }) or
		recurrence_fact(source, 1) != RecurrenceTermination(Count(input.count.to_u64())) {
		crash "Subdaily explanation changed anchored grid, microseconds or COUNT"
	}
	var $index = 3.U64
	var $hour = 0.U8
	while $hour < 24 {
		if recurrence_fact(source, $index) != RecurrenceSelector(Hour($hour)) {
			crash "Omitted subdaily hour must allow every hour"
		}
		$hour = $hour + 1
		$index = $index + 1
	}
	var $minute = 0.U8
	while $minute < 60 {
		if mode != 0 or $minute == 0 or $minute == 30 {
			if recurrence_fact(source, $index) != RecurrenceSelector(Minute($minute)) {
				crash "Subdaily minute limitation/expansion changed"
			}
			$index = $index + 1
		}
		$minute = $minute + 1
	}
	for second in [10.U8, 50] {
		if recurrence_fact(source, $index) != RecurrenceSelector(Second(second)) {
			crash "Subdaily second selectors changed"
		}
		$index = $index + 1
	}
	if recurrence_fact(source, $index) != RecurrenceSelector(Microsecond(input.work.to_u32())) or
		recurrence_fact(source, $index + 1) != RecurrenceException({ kind: Exclusion, source: Local(anchor) }) or
			Explanation.fact_count(source) != $index + 2 {
		crash "Subdaily explanation lost exact anchor fraction or source exclusion"
	}
	check_recurrence_rendering(source)
}

# R01/R02/R07/R11/R12: independent piecewise offset model at epoch day.
# A +1h jump at 02:00Z makes 02:00/03:00 and 02:30/03:30 collide.
# A -1h jump tests first-fold selection and a nonselected boundary exclusion.
# COUNT applies to the source grid before either exclusion domain, and explicit
# inclusions survive COUNT but remain subject to both exclusion domains.
check_boundary_exclusions = |input| {
	d = date(1970, 1, 1)
	offset = if input.exclude_anchor {
		-3600.I32
	} else {
		3600.I32
	}
	rules = ZoneRules.new_bounded(
		"Synthetic/ExclusionGrid",
		"v1",
		cutoff_span(-86400000000, 172800000000),
		FixedOffset.from_seconds(0),
		[{ at: PosixBoundary.from_microseconds(7200000000), offset: FixedOffset.from_seconds(offset) }],
		{
			minimum: if offset < 0 {
				offset
			} else {
				0
			},
			maximum: if offset > 0 {
				offset
			} else {
				0
			},
		},
	) ?? crash "exclusion grid rules"
	count = input.count.to_u64() + 3
	base = TimedRecurrence.new({ date: d, clock: clock(0) }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [0, 1, 2, 3, 4, 5], minutes: [0, 30], seconds: [] }, termination: Count(count), by_set_pos: [] }) ?? crash "exclusion grid base"
	included = TimedRecurrence.with_inclusions(base, [{ date: d, clock: clock(3) }, { date: d, clock: clock(5) }]) ?? crash "exclusion grid inclusions"
	source_excluded = if input.last_monday {
		[local(d, 2)]
	} else {
		[]
	}
	sourced = TimedRecurrence.with_exclusions(included, source_excluded) ?? crash "exclusion source set"
	excluded = if input.last_monday {
		9000000000.I64
	} else {
		7200000000.I64
	}
	boundaries = [PosixBoundary.from_microseconds(excluded), PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(excluded), PosixBoundary.from_microseconds(I64.highest)]
	rule = TimedRecurrence.with_boundary_exclusions(sourced, boundaries) ?? crash "exclusion boundary set"
	if TimedRecurrence.definition(rule).boundary_exclusions != [PosixBoundary.from_microseconds(I64.lowest), PosixBoundary.from_microseconds(excluded), PosixBoundary.from_microseconds(I64.highest)] {
		crash "boundary normalization changed exact values"
	}
	var $expected = []
	for half_hour in [0.U64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] {
		source = half_hour.to_i64_wrap() * 1800000000
		boundary = if offset > 0 and source >= 10800000000 {
			source - 3600000000
		} else if offset < 0 and source >= 7200000000 {
			source + 3600000000
		} else {
			source
		}
		if (half_hour < count or half_hour == 6 or half_hour == 10) and boundary != excluded and !(input.last_monday and half_hour == 4) {
			$expected = $expected.append({ source, boundary })
		}
	}
	var $cursor = TimedRecurrence.cursor(rule, { start: local(d, 0), end: local(date(1970, 1, 2), 0) }, { rules, occurrence: First, gap: UseOffsetBeforeGap }) ?? crash "exclusion cursor"
	# One slot may expose a non-progressing merge BufferLimit when an explicit
	# inclusion precedes a held rule item. Resume that exact state with the two
	# slots required by the merge; work and zone budgets remain unchanged.
	var $buffer_limit = 1.U64
	var $observed = []
	var $calls = 0.U64
	while $calls < 500 {
		batch = TimedRecurrence.Cursor.collect($cursor, { work: { max_steps: input.work.to_u64(), max_buffered: $buffer_limit, max_zone_segments: 1, max_zone_candidates: 2 }, max_occurrences: 1 }) ?? crash "exclusion collection"
		if batch.steps > input.work.to_u64() or batch.zone_segments > 1 or batch.occurrences.len() > 1 {
			crash "exclusion execution exceeded budget"
		}
		for value in batch.occurrences {
			$observed = $observed.append({ source: ClockTime.to_microseconds_since_midnight(LocalDateTime.clock(TimedRecurrence.Occurrence.source(value))), boundary: PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(value)) })
		}
		match batch.status {
			Complete => {
				if $observed != $expected {
					crash "boundary exclusions differ from independent piecewise grid"
				}
				return {}
			}
			Limited(progress) => {
				if progress.reason == BufferLimit {
					if $buffer_limit != 1 {
						crash "two-slot inclusion merge cannot progress"
					}
					$buffer_limit = 2
				}
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	crash "boundary exclusions failed finite resumption"
}
