import fuzz.Fuzz
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
