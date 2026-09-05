import fuzz.Fuzz
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
import time.RfcDateRule

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
		parsed = match RfcDateRule.parse(parts) {
			Ok(value) => value
			Err(_) => crash "Valid RFC date rule rejected"
		}
		match RfcDateRule.parse({ ..parts, rule: "${text};COUNT=1" }) {
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
		var elapsed = 0.U64
		var month_index = 0.U64
		var counted = 0.U64
		var expected = []
		for year in [2024.I64, 2025] {
			var month = 1.U8
			while month <= 12 {
				length = month_length(year, month)
				var last_monday = 0.U8
				var day = 1.U8
				while day <= length {
					if U64.mod_by(elapsed + day.to_u64() - 1, 7) == 0 {
						last_monday = day
					}
					day = day + 1
				}
				if U64.mod_by(month_index, input.interval.to_u64()) == 0 and counted < input.count.to_u64() {
					if input.last_monday or length == 31 {
						expected = expected.append(
							date(
								year,
								month,
								if input.last_monday {
									last_monday
								} else {
									31
								},
							),
						)
						counted = counted + 1
					}
				}
				elapsed = elapsed + length.to_u64()
				month_index = month_index + 1
				month = month + 1
			}
		}
		check_subdaily(input)
		check_timed(input, anchor, pattern, window, expected)
		# Direct ordered set model; deliberately not the cursor's two-stream merge.
		var normalized = []
		for candidate in expected.concat(inclusions).sort_with(
			|a, b| if a < b {
				Before
			} else if a > b {
				After
			} else {
				Same
			},
		) {
			if candidate >= window.start and candidate < window.end and !exclusions.contains(candidate) and !normalized.contains(candidate) {
				normalized = normalized.append(candidate)
			}
		}
		limits = { max_steps: input.work.to_u64(), max_buffered: 366.U64, max_occurrences: 1.U64 }
		var current = cursor
		var observed = []
		var batches = 0.U64
		while batches < 5000 {
			batch = match DateRecurrence.Cursor.collect(current, limits) {
				Ok(value) => value
				Err(_) => crash "Supported recurrence failed"
			}
			if batch.steps > limits.max_steps or batch.buffered > limits.max_buffered or batch.dates.len() > 1 {
				crash "Recurrence exceeded budget"
			}
			observed = observed.concat(batch.dates)
			match batch.status {
				Complete => {
					if observed != normalized {
						crash "Recurrence differs from finite calendar model"
					}
					parsed_batch = match DateRecurrence.Cursor.collect(parsed_cursor, { max_steps: 10000, max_buffered: 366, max_occurrences: 100 }) {
						Ok(value) => value
						Err(_) => crash "Parsed recurrence failed"
					}
					match parsed_batch.status {
						Complete => if parsed_batch.dates != normalized {
							crash "RFC adapter differs from calendar model"
						}
						Limited(_) => crash "Parsed recurrence unexpectedly limited"
					}
					check_consumers(cursor, limits, normalized)
					check_all_day(rule, window, normalized)
					return Fuzz.keep
				}
				Limited(progress) => {
					current = progress.cursor
				}
			}
			batches = batches + 1
		}
		crash "Recurrence resumption failed to progress"
	}
}

check_consumers = |initial, limits, expected| {
	var current = initial
	var observed = []
	var calls = 0.U64
	var done = False
	while done == False and calls < 5000 {
		result = match DateRecurrence.Cursor.next(current, { max_steps: limits.max_steps, max_buffered: limits.max_buffered }) {
			Ok(value) => value
			Err(_) => crash "Next failed within the reference range"
		}
		if result.steps > limits.max_steps or result.buffered > limits.max_buffered {
			crash "Next exceeded its budget"
		}
		match result.status {
			End => {
				done = True
			}
			Item(item) => {
				observed = observed.append(item.date)
				current = item.cursor
			}
			Limited(progress) => {
				current = progress.cursor
			}
		}
		calls = calls + 1
	}
	if done == False or observed != expected {
		crash "Next differs from finite calendar model"
	}
	current = initial
	calls = 0
	done = False
	var value = { count: 0.U64, weighted: 0.U64 }
	while done == False and calls < 5000 {
		result = match DateRecurrence.Cursor.fold(
			current,
			limits,
			value,
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
		value = result.value
		match result.status {
			Complete => {
				done = True
			}
			Stopped(remaining) => {
				current = remaining
			}
			Limited(progress) => {
				current = progress.cursor
			}
		}
		calls = calls + 1
	}
	var weighted = 0.U64
	var index = 1.U64
	for candidate in expected {
		fields = GregorianDate.to_fields(candidate)
		weighted = weighted + index * (fields.month.to_u64() * 31 + fields.day.to_u64())
		index = index + 1
	}
	if done == False or value.count != expected.len() or value.weighted != weighted {
		crash "Stopped fold differs from calendar model"
	}
	var chunked = []
	var complete = False
	var chunks = 0.U64
	for result in DateRecurrence.Cursor.chunks(initial, limits) {
		batch = match result {
			Ok(chunk) => chunk
			Err(_) => crash "Chunk iterator failed in reference range"
		}
		if complete == True or chunks >= 5000 {
			crash "Invalid chunk iterator termination"
		}
		chunked = chunked.concat(batch.dates)
		match batch.status {
			Complete => {
				complete = True
			}
			Limited(_) => {}
		}
		chunks = chunks + 1
	}
	if complete == False or chunked != expected {
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
	var current = match AllDayRecurrence.new(42.U64, rule, window, 1, rules) {
		Ok(value) => value
		Err(_) => crash "all-day construction"
	}
	var observed = []
	var calls = 0.U64
	while calls < 5000 {
		batch = match AllDayRecurrence.next(current, { max_date_steps: 7, max_date_buffered: 366, max_zone_segments: 1, max_zone_members: 1 }) {
			Ok(value) => value
			Err(_) => crash "all-day next"
		}
		if batch.date_steps > 7 or batch.zone_segments > 1 {
			crash "all-day budget exceeded"
		}
		match batch.status {
			End => {
				if observed != expected {
					crash "all-day dates differ from calendar oracle"
				}
				return {}
			}
			Limited(progress) => {
				current = progress.cursor
			}
			Item(item) => {
				identity = AllDayOccurrence.id(item.occurrence)
				if identity.series != 42 or Coverage.coordinate_width(AllDayOccurrence.coverage(item.occurrence)) != Ok(PosixDelta.from_microseconds(86400000000)) {
					crash "all-day identity or width"
				}
				observed = observed.append(identity.date)
				current = item.cursor
			}
		}
		calls = calls + 1
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
	start = local(window.start, 0)
	end = local(window.end, 0)
	rules = fixture_rules(2000000000000000)
	var current = match TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: RequireUnique, gap: RejectGap }) {
		Ok(value) => value
		Err(_) => crash "timed window"
	}
	var expected_sources = []
	var expected_boundaries = []
	var count = 0.U64
	for candidate in dates {
		hours = if input.last_monday {
			[17.U8]
		} else {
			[9.U8, 17]
		}
		for hour in hours {
			if count < input.count.to_u64() {
				count = count + 1
				if candidate >= window.start and candidate < window.end and (!input.exclude_anchor or !LocalDateTime.same_position(local(candidate, hour), excluded_label)) {
					expected_sources = expected_sources.append(local(candidate, hour))
					fields = GregorianDate.to_fields(candidate)
					var days = if fields.year == 2024 {
						0.I64
					} else {
						366.I64
					}
					var month = 1.U8
					while month < fields.month {
						days = days + month_length(fields.year, month).to_i64()
						month = month + 1
					}
					days = days + fields.day.to_i64() - 1
					# 2024-01-01T00:00Z is Unix second 1704067200.
					expected_boundaries = expected_boundaries.append(PosixBoundary.from_microseconds((1704067200 + days * 86400 + hour.to_i64() * 3600) * 1000000))
				}
			}
		}
	}
	check_timed_batches(current, input.work.to_u64(), expected_sources, expected_boundaries)

	var sources = []
	var boundaries = []
	var calls = 0.U64
	while calls < 10000 {
		batch = match TimedRecurrence.Cursor.next(current, { max_steps: input.work.to_u64(), max_buffered: 10, max_zone_segments: 1, max_zone_candidates: 1 }) {
			Ok(value) => value
			Err(_) => crash "timed interpretation"
		}
		if batch.steps > input.work.to_u64() or batch.zone_segments > 1 or batch.buffered > 10 or batch.zone_buffered > 1 {
			crash "timed budget exceeded"
		}
		match batch.status {
			End => {
				if sources != expected_sources or boundaries != expected_boundaries {
					crash "timed recurrence differs from independent clock/calendar grid"
				}
				return {}
			}
			Limited(progress) => {
				current = progress.cursor
			}
			Item(item) => {
				sources = sources.append(TimedRecurrence.Occurrence.source(item.occurrence))
				boundaries = boundaries.append(TimedRecurrence.Occurrence.boundary(item.occurrence))
				match TimedRecurrence.Occurrence.adjustment(item.occurrence) {
					Exact => {}
					BeforeGap(_) => crash "UTC adjustment"
				}
				current = item.cursor
			}
		}
		calls = calls + 1
	}
	crash "timed resumption did not finish"
}

clock = |hour| match ClockTime.from_fields({ hour, minute: 0, second: 0, microsecond: 0 }) {
	Ok(value) => value
	Err(_) => crash "model clock"
}

local = |date_value, hour| LocalDateTime.new(CalendarDate.from_gregorian(date_value), clock(hour))

check_timed_batches = |initial, work, expected_sources, expected_boundaries| {
	var current = initial
	var sources = []
	var boundaries = []
	var calls = 0.U64
	while calls < 10000 {
		batch = match TimedRecurrence.Cursor.collect(
			current,
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
			sources = sources.append(TimedRecurrence.Occurrence.source(occurrence))
			boundaries = boundaries.append(TimedRecurrence.Occurrence.boundary(occurrence))
		}
		match batch.status {
			Complete => {
				if sources != expected_sources or boundaries != expected_boundaries {
					crash "timed batches differ from calendar grid"
				}
				return {}
			}
			Limited(progress) => {
				current = progress.cursor
			}
		}
		calls = calls + 1
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
	window_start = if input.exclude_anchor {
		query
	} else {
		start
	}
	var current = match TimedRecurrence.cursor(rule, { start: window_start, end }, { rules: fixture_rules(259200000000), occurrence: RequireUnique, gap: RejectGap }) {
		Ok(value) => value
		Err(_) => crash "subdaily grid cursor"
	}
	var expected = []
	var count = 0.U64
	var index = 0.I64
	while index < 1000 and count < input.count.to_u64() {
		base = I64.div_trunc_by(anchor_second, unit) * unit + index * input.interval.to_i64() * unit
		offsets = match mode {
			0 => [10.I64, 50, 1810, 1850]
			1 => [10.I64, 50]
			_ => [0.I64]
		}
		for offset in offsets {
			candidate = base + offset
			seconds = I64.mod_by(candidate, 60)
			if candidate >= anchor_second and (mode != 2 or seconds == 10 or seconds == 50) and count < input.count.to_u64() {
				count = count + 1
				if candidate != anchor_second and (!input.exclude_anchor or candidate >= anchor_second + 30) {
					expected = expected.append(candidate * 1000000 + fraction)
				}
			}
		}
		index = index + 1
	}
	if count != input.count.to_u64() {
		crash "finite subdaily model too short"
	}
	var observed = []
	var calls = 0.U64
	while calls < 10000 {
		batch = match TimedRecurrence.Cursor.collect(current, { work: { max_steps: input.work.to_u64(), max_buffered: 1, max_zone_segments: 2, max_zone_candidates: 1 }, max_occurrences: 2 }) {
			Ok(value) => value
			Err(_) => crash "subdaily grid execution"
		}
		if batch.steps > input.work.to_u64() or batch.zone_segments > 2 or batch.occurrences.len() > 2 {
			crash "subdaily grid budget"
		}
		for occurrence in batch.occurrences {
			observed = observed.append(PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(occurrence)))
		}
		match batch.status {
			Complete => {
				if observed != expected {
					crash "subdaily differs from integer-second model"
				}
				return {}
			}
			Limited(progress) => {
				current = progress.cursor
			}
		}
		calls = calls + 1
	}
	crash "subdaily grid resumption did not terminate"
}
