import CalendarPattern
import DateRecurrence
import GregorianDate

DateRecurrenceTests :: [].{}

date = |year, month, day| match GregorianDate.from_fields({ year, month, day }) {
	Ok(value) => value
	Err(_) => crash "Invalid test date"
}

spec : DateRecurrence.Spec
spec = { pattern: CalendarPattern.defaults(Monthly), termination: Count(3), by_set_pos: [], inclusions: [], exclusions: [] }

limits : DateRecurrence.Limits
limits = { max_steps: 10000, max_buffered: 366, max_occurrences: 1000 }

window = { start: date(2025, 1, 1), end: date(2025, 8, 1) }

complete = |rule, query| {
	cursor = DateRecurrence.cursor(rule, query)?
	batch = DateRecurrence.Cursor.collect(cursor, limits)?
	match batch.status {
		Complete => Ok(batch.dates)
		Limited(_) => crash "Unexpected limit"
	}
}

# RFC 5545 COUNT counts the series, before EXDATE and query restriction.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), spec)?
	complete(rule, window)? == [date(2025, 1, 31), date(2025, 3, 31), date(2025, 5, 31)] and
		complete(rule, { ..window, start: date(2025, 3, 1) })? == [date(2025, 3, 31), date(2025, 5, 31)]
}

expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, exclusions: [date(2025, 3, 31)] })?
	complete(rule, window)? == [date(2025, 1, 31), date(2025, 5, 31)]
}

# Inclusions are a union, not additional COUNT consumers. Exclusion wins even
# over DTSTART and an explicit duplicate; inclusions can precede the anchor.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, inclusions: [date(2025, 7, 4), date(2025, 1, 1), date(2025, 3, 31), date(2025, 7, 4)], exclusions: [date(2025, 1, 31), date(2025, 3, 31), date(2025, 3, 31)] })?
	complete(rule, window)? == [date(2025, 1, 1), date(2025, 5, 31), date(2025, 7, 4)]
}

# Select the first and last Monday of each full month, not of the query slice.
expect {
	pattern = { ..CalendarPattern.defaults(Monthly), by_day: [{ ordinal: 0, weekday: Monday }] }
	rule = DateRecurrence.new(date(2025, 1, 6), { ..spec, pattern, termination: Forever, by_set_pos: [1, -1, -1] })?
	complete(rule, { start: date(2025, 1, 10), end: date(2025, 2, 20) })? == [date(2025, 1, 27), date(2025, 2, 3)]
}

# DTSTART truncation happens after full-period BYSETPOS, including period zero.
expect {
	pattern = { ..CalendarPattern.defaults(Monthly), by_day: [{ ordinal: 0, weekday: Monday }] }
	rule = DateRecurrence.new(date(2025, 1, 27), { ..spec, pattern, by_set_pos: [-1] })?
	complete(rule, window)? == [date(2025, 1, 27), date(2025, 2, 24), date(2025, 3, 31)]
}

expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, termination: Until(date(2025, 3, 31)) })?
	earlier = DateRecurrence.new(date(2025, 1, 31), { ..spec, termination: Until(date(2025, 3, 30)) })?
	complete(rule, window)? == [date(2025, 1, 31), date(2025, 3, 31)] and
		complete(earlier, window)? == [date(2025, 1, 31)]
}

resume_all = |initial, budget| {
	var cursor = initial
	var output = []
	var batches = 0.U64
	while batches < 10000 {
		batch = DateRecurrence.Cursor.collect(cursor, budget)?
		if batch.steps > budget.max_steps or batch.buffered > budget.max_buffered or batch.dates.len() > budget.max_occurrences {
			crash "Budget exceeded"
		}
		output = output.concat(batch.dates)
		match batch.status {
			Complete => return Ok(output)
			Limited(progress) => {
				cursor = progress.cursor
			}
		}
		batches = batches + 1
	}
	crash "Resumption made no progress"
}

# Partition at every state boundary with one work step per batch. Reusing the
# original cursor also exercises immutable sharing and repeatability.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, inclusions: [date(2025, 2, 4)], exclusions: [date(2025, 3, 31)] })?
	cursor = DateRecurrence.cursor(rule, window)?
	expected = complete(rule, window)?
	resume_all(cursor, { ..limits, max_steps: 1, max_occurrences: 1 })? == expected and
		resume_all(cursor, { ..limits, max_steps: 7, max_occurrences: 1 })? == expected
}

# A buffer limit preserves the unprocessed matching date. Raising the limit
# must give the same result, including a negative position at period end.
expect {
	pattern = { ..CalendarPattern.defaults(Monthly), by_day: [{ ordinal: 0, weekday: Monday }] }
	rule = DateRecurrence.new(date(2025, 1, 27), { ..spec, pattern, by_set_pos: [-1] })?
	cursor = DateRecurrence.cursor(rule, window)?
	batch = DateRecurrence.Cursor.collect(cursor, { ..limits, max_buffered: 2 })?
	match batch.status {
		Limited(progress) => progress.reason == BufferLimit and batch.buffered == 2 and batch.dates == [] and
			resume_all(progress.cursor, limits)? == complete(rule, window)?
		Complete => False
	}
}

expect {
	pattern = { ..CalendarPattern.defaults(Monthly), by_day: [{ ordinal: 0, weekday: Monday }] }
	rule = DateRecurrence.new(date(2025, 1, 27), { ..spec, pattern, by_set_pos: [-1] })?
	cursor = DateRecurrence.cursor(rule, window)?
	resume_all(cursor, { ..limits, max_steps: 1, max_occurrences: 1 })? == complete(rule, window)?
}

# Fully excluded results can complete with no output allowance. A zero buffer
# allowance stops at the first match and preserves it for the next batch.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, termination: Count(1), exclusions: [date(2025, 1, 31)] })?
	cursor = DateRecurrence.cursor(rule, window)?
	batch = DateRecurrence.Cursor.collect(cursor, { ..limits, max_occurrences: 0 })?
	zero = DateRecurrence.Cursor.collect(cursor, { ..limits, max_buffered: 0 })?
	match (batch.status, zero.status) {
		(Complete, Limited(progress)) => batch.dates == [] and progress.reason == BufferLimit and
			resume_all(progress.cursor, limits)? == []
		_ => False
	}
}

# UNTIL bounds only the rule; RDATE can add a later date. Retaining a cursor
# while creating a changed series leaves the original series interpretation.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, termination: Until(date(2025, 1, 31)), inclusions: [date(2025, 6, 1)] })?
	cursor = DateRecurrence.cursor(rule, window)?
	changed = DateRecurrence.new(date(2025, 1, 31), { ..spec, termination: Count(1) })?
	resume_all(cursor, { ..limits, max_steps: 1 })? == [date(2025, 1, 31), date(2025, 6, 1)] and
		complete(changed, window)? == [date(2025, 1, 31)]
}

expect {
	rule = DateRecurrence.new(date(2025, 1, 31), spec)?
	cursor = DateRecurrence.cursor(rule, window)?
	zero = DateRecurrence.Cursor.collect(cursor, { ..limits, max_steps: 0 })?
	no_output = DateRecurrence.Cursor.collect(cursor, { ..limits, max_occurrences: 0 })?
	match (zero.status, no_output.status) {
		(Limited(a), Limited(b)) => a.reason == WorkLimit and zero.steps == 0 and b.reason == OutputLimit and
			resume_all(a.cursor, limits)? == resume_all(b.cursor, limits)?
		_ => False
	}
}

# COUNT can release the period buffer while one date still awaits output.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, termination: Count(1) })?
	cursor = DateRecurrence.cursor(rule, window)?
	paused = DateRecurrence.Cursor.collect(cursor, { ..limits, max_occurrences: 0 })?
	match paused.status {
		Limited(progress) => {
			reduced = DateRecurrence.Cursor.collect(progress.cursor, { ..limits, max_buffered: 0 })?
			match reduced.status {
				Limited(next) => progress.reason == OutputLimit and paused.buffered == 1 and
					next.reason == BufferLimit and reduced.steps == 0 and reduced.buffered == 1 and
						resume_all(next.cursor, limits)? == [date(2025, 1, 31)]
				Complete => False
			}
		}
		Complete => False
	}
}

# Completing November needs no unrepresentable December exclusive endpoint.
expect {
	rule = DateRecurrence.new(date(2147483647, 11, 1), { ..spec, termination: Forever })?
	complete(rule, { start: date(2147483647, 11, 1), end: date(2147483647, 12, 1) })? == [date(2147483647, 11, 1)]
}

status = |anchor, options| match DateRecurrence.new(anchor, options) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}

# next has three outcomes: an item, proven end, or a resumable work limit.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, termination: Count(1) })?
	cursor = DateRecurrence.cursor(rule, window)?
	zero = DateRecurrence.Cursor.next(cursor, { max_steps: 0, max_buffered: 366 })?
	match zero.status {
		Limited(progress) => {
			first = DateRecurrence.Cursor.next(progress.cursor, { max_steps: 1000, max_buffered: 366 })?
			match first.status {
				Item(item) => {
					last = DateRecurrence.Cursor.next(item.cursor, { max_steps: 0, max_buffered: 366 })?
					item.date == date(2025, 1, 31) and progress.reason == WorkLimit and
						last.status == End and last.steps == 0
				}
				_ => False
			}
		}
		_ => False
	}
}

# Stop on an inclusion before the anchor, then a duplicate inclusion/rule
# date. Both merge inputs must advance exactly once before yielding control.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, inclusions: [date(2025, 1, 1), date(2025, 1, 31)] })?
	cursor = DateRecurrence.cursor(rule, window)?
	first = DateRecurrence.Cursor.fold(cursor, limits, "", |text, value| Stop("${text}${GregorianDate.to_fields(value).day.to_str()}"))?
	match first.status {
		Stopped(after_first) => {
			second = DateRecurrence.Cursor.fold(after_first, limits, first.value, |text, value| Stop("${text},${GregorianDate.to_fields(value).day.to_str()}"))?
			match second.status {
				Stopped(after_second) => first.value == "1" and second.value == "1,31" and
					first.occurrences == 1 and second.occurrences == 1 and
						resume_all(after_second, limits)? == [date(2025, 3, 31), date(2025, 5, 31)]
				_ => False
			}
		}
		_ => False
	}
}

# A stopped final callback does not claim completion by looking ahead.
# Resuming the exhausted cursor must not invoke the visitor again.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, termination: Count(1) })?
	cursor = DateRecurrence.cursor(rule, window)?
	batch = DateRecurrence.Cursor.fold(cursor, limits, 10.U64, |total, _| Stop(total + 1))?
	match batch.status {
		Stopped(remaining) => {
			last = DateRecurrence.Cursor.fold(remaining, limits, batch.value, |_, _| crash "Visitor called after exhaustion")?
			match last.status {
				Complete => batch.value == 11 and last.value == 11 and last.occurrences == 0
				_ => False
			}
		}
		_ => False
	}
}

# A non-list accumulator and one-step budgets preserve visitor state; limits
# count engine work and visitor calls separately from the series COUNT.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), { ..spec, exclusions: [date(2025, 3, 31)] })?
	var current = DateRecurrence.cursor(rule, window)?
	var sum = 100.U64
	var finished = False
	var batches = 0.U64
	while finished == False and batches < 1000 {
		batch = DateRecurrence.Cursor.fold(current, { ..limits, max_steps: 1, max_occurrences: 1 }, sum, |total, value| Continue(total + GregorianDate.to_fields(value).month.to_u64()))?
		sum = batch.value
		if batch.steps > 1 or batch.occurrences > 1 {
			crash "Fold exceeded budget"
		}
		match batch.status {
			Complete => {
				finished = True
			}
			Limited(progress) => {
				current = progress.cursor
			}
			Stopped(_) => crash "Visitor never stops"
		}
		batches = batches + 1
	}
	finished and sum == 106
}

# Iter chunks preserve partial/complete outcomes and standard Iter composition.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), spec)?
	cursor = DateRecurrence.cursor(rule, window)?
	var dates = []
	var completed = False
	for result in DateRecurrence.Cursor.chunks(cursor, { ..limits, max_steps: 7, max_occurrences: 1 }) {
		batch = result?
		if completed == True {
			crash "Item emitted after Complete"
		}
		dates = dates.concat(batch.dates)
		match batch.status {
			Complete => {
				completed = True
			}
			Limited(_) => {}
		}
	}
	completed == True and dates == complete(rule, window)?
}

# An insufficient budget produces a visible terminal Limited item, not an
# endlessly repeated empty chunk or apparent successful exhaustion.
expect {
	rule = DateRecurrence.new(date(2025, 1, 31), spec)?
	cursor = DateRecurrence.cursor(rule, window)?
	var count = 0.U64
	var retained = None
	for result in DateRecurrence.Cursor.chunks(cursor, { ..limits, max_buffered: 0 }) {
		batch = result?
		match batch.status {
			Limited(progress) => {
				retained = Some(progress.cursor)
			}
			Complete => crash "Buffer exhaustion reported as complete"
		}
		count = count + 1
	}
	match retained {
		Some(remaining) => count == 1 and resume_all(remaining, limits)? == complete(rule, window)?
		None => False
	}
}

# take_first(0) must not execute a range-failing future period. Consuming the
# iterator exposes that failure exactly once after its preceding date batch.
expect {
	rule = DateRecurrence.new(date(2147483647, 11, 1), { ..spec, termination: Forever })?
	cursor = DateRecurrence.cursor(rule, { start: date(2147483647, 11, 1), end: date(2147483647, 12, 2) })?
	stream = DateRecurrence.Cursor.chunks(cursor, { ..limits, max_steps: 35 })
	empty_count = stream.take_first(0).fold(0.U64, |n, _| n + 1)
	var failures = 0.U64
	for result in stream {
		match result {
			Err(OutOfRange) => {
				failures = failures + 1
			}
			Ok(batch) => match batch.status {
				Limited(_) => {}
				Complete => crash "Out-of-range query reported as complete"
			}
		}
	}
	empty_count == 0 and failures == 1
}

expect {
	anchor = date(2025, 1, 20)
	pattern = { ..spec.pattern, by_day: [{ ordinal: 0, weekday: Monday }] }
	status(anchor, { ..spec, termination: Count(0) }) == Err(InvalidCount) and
		status(anchor, { ..spec, termination: Until(date(2025, 1, 19)) }) == Err(InvalidUntil) and
			status(anchor, { ..spec, by_set_pos: [0] }) == Err(InvalidSelector("BYSETPOS")) and
				status(anchor, { ..spec, pattern, by_set_pos: [-1] }) == Err(UnsynchronizedStart)
}
