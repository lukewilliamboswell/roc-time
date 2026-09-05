app [main!] { pf: platform "../platform/main.roc", time: "../../package/main.roc" }
import pf.Host
import time.CalendarPattern
import time.TimedRecurrence
import time.CalendarDate
import time.LocalDateTime
import time.DateRecurrence
import time.GregorianDate
import time.AllDayRecurrence
import time.AllDayOccurrence
import time.PosixSpan
import time.PosixBoundary
import time.FixedOffset
import time.ZoneRules
import time.ClockPattern
import time.ClockTime

# R12/R15: runtime horizon, shared cursor, bounded prefix. Hundreds of billions
# of logical days must never become an eagerly materialized intermediate list.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	year = I64.from_str(args.get(1) ?? "2000000000") ?? 2000000000
	ceiling = U64.from_str(args.get(2) ?? "4096") ?? 4096
	start_year = I64.from_str(args.get(3) ?? "2000") ?? 2000
	anchor = fixture_date(start_year, 1)
	end = match GregorianDate.from_fields({ year, month: 1, day: 1 }) {
		Ok(value) => value
		Err(_) => crash "fixture horizon"
	}
	rule = match DateRecurrence.new(anchor, { pattern: CalendarPattern.defaults(Daily), termination: Forever, by_set_pos: [], inclusions: [], exclusions: [] }) {
		Ok(value) => value
		Err(_) => crash "fixture rule"
	}
	cursor = match DateRecurrence.cursor(rule, { start: anchor, end }) {
		Ok(value) => value
		Err(_) => crash "fixture cursor"
	}
	before = Host.allocated_bytes!({})
	stream = DateRecurrence.Cursor.chunks(cursor, { max_steps: 8, max_buffered: 1, max_occurrences: 1 })
	constructed = Host.allocated_bytes!({})
	Host.assert!(constructed - before <= ceiling)
	count = stream.take_first(1).fold(
		0.U64,
		|_, result| match result {
			Err(_) => crash "prefix failed"
			Ok(batch) => {
				if batch.dates != [anchor] or batch.steps > 8 {
					crash "incorrect prefix"
				}
				batch.dates.len()
			}
		},
	)
	consumed = Host.allocated_bytes!({})
	Host.assert!(count == 1 and consumed - constructed <= ceiling)
	folded = match DateRecurrence.Cursor.fold(
		cursor,
		{ max_steps: 8, max_buffered: 1, max_occurrences: 1 },
		0.U64,
		|n, date| {
			if date != anchor {
				crash "incorrect stopped date"
			}
			Stop(n + 1)
		},
	) {
		Ok(value) => value
		Err(_) => crash "stopping fold failed"
	}
	after = Host.allocated_bytes!({})
	Host.assert!(folded.value == 1 and folded.occurrences == 1 and after - consumed <= ceiling)
	match folded.status {
		Stopped(rest) => {
			next = match DateRecurrence.Cursor.next(rest, { max_steps: 8, max_buffered: 1 }) {
				Ok(value) => value
				Err(_) => crash "resume failed"
			}
			match next.status {
				Item(item) => {
					expected = fixture_date(start_year, 2)
					Host.assert!(item.date == expected)
				}
				_ => Host.assert!(False)
			}
		}
		_ => Host.assert!(False)
	}
	# Query far after DTSTART: budget candidate work even when no result is
	# nearby. Searching for the first visible date must not hide a long scan.
	later = fixture_date(year - 1, 2)
	delayed = match DateRecurrence.cursor(rule, { start: later, end }) {
		Ok(value) => value
		Err(_) => crash "delayed cursor"
	}
	search_before = Host.allocated_bytes!({})
	searched = match DateRecurrence.Cursor.next(delayed, { max_steps: 1, max_buffered: 1 }) {
		Ok(value) => value
		Err(_) => crash "bounded search failed"
	}
	search_after = Host.allocated_bytes!({})
	Host.assert!(searched.steps == 1 and search_after - search_before <= ceiling)
	match searched.status {
		Limited(progress) => Host.assert!(progress.reason == WorkLimit)
		_ => Host.assert!(False)
	}
	# Consume the entire zero-work stream. It must expose one incomplete
	# outcome, then stop; endlessly retrying its cursor would hit the deadline.
	zero_before = Host.allocated_bytes!({})
	zero_count = DateRecurrence.Cursor.chunks(delayed, { max_steps: 0, max_buffered: 1, max_occurrences: 1 }).fold(
		0.U64,
		|n, result| {
			match result {
				Ok(batch) => {
					if batch.steps != 0 or batch.dates != [] {
						crash "zero-work cursor advanced"
					}
					match batch.status {
						Limited(progress) => if progress.reason != WorkLimit {
							crash "wrong zero-work outcome"
						}
						Complete => crash "zero-work query falsely completed"
					}
				}
				Err(_) => crash "zero-work stream failed"
			}
			n + 1
		},
	)
	zero_after = Host.allocated_bytes!({})
	Host.assert!(zero_count == 1 and zero_after - zero_before <= ceiling)
	rules = fixture_rules(2000000000000000)
	composition_before = Host.allocated_bytes!({})
	composed = match AllDayRecurrence.new("service", rule, { start: anchor, end }, 1, rules) {
		Ok(value) => value
		Err(_) => crash "composed cursor"
	}
	resolved = match AllDayRecurrence.next(composed, { max_date_steps: 8, max_date_buffered: 1, max_zone_segments: 1, max_zone_members: 1 }) {
		Ok(value) => value
		Err(_) => crash "composed next"
	}
	composition_after = Host.allocated_bytes!({})
	match resolved.status {
		Item(item) => Host.assert!(AllDayOccurrence.id(item.occurrence) == { series: "service", date: anchor })
		_ => Host.assert!(False)
	}
	Host.assert!(composition_after - composition_before <= ceiling)
	# Construct the input table outside the measured classification scope.
	var transitions = []
	var index = 1.I64
	last = if year > 2001 {
		8192.I64
	} else {
		16.I64
	}
	while index <= last {
		transitions = transitions.append({
			at: PosixBoundary.from_microseconds(index * 1000000),
			offset: FixedOffset.from_seconds(fixture_offset(-index)),
		})
		index = index + 1
	}
	zone_rules = classification_rules(transitions, 10000000000)
	local = classification_label(500000)
	classification_before = Host.allocated_bytes!({})
	classification_cursor = match ZoneRules.classification_cursor(zone_rules, local) {
		Ok(value) => value
		Err(_) => crash "classification cursor"
	}
	classified = match ZoneRules.ClassificationCursor.collect(classification_cursor, { max_segments: 1, max_candidates: 1 }) {
		Ok(value) => value
		Err(_) => crash "classification step"
	}
	classification_after = Host.allocated_bytes!({})
	Host.assert!(classified.segments == 1 and classified.buffered == 1 and classification_after - classification_before <= ceiling)
	match classified.status {
		Limited(progress) => Host.assert!(progress.reason == WorkLimit)
		_ => Host.assert!(False)
	}
	full = match ZoneRules.ClassificationCursor.collect(classification_cursor, { max_segments: 10000, max_candidates: 10000 }) {
		Ok(value) => value
		Err(_) => crash "full classification"
	}
	completed = match full.status {
		Complete(value) => value
		Limited(_) => crash "full classification limited"
	}
	asserted = FixedOffset.from_seconds(fixture_offset(-last))
	choice_before = Host.allocated_bytes!({})
	choice = match ZoneRules.Classification.choose(completed, { occurrence: MatchingOffset(asserted), gap: RejectGap }) {
		Ok(value) => value
		Err(_) => crash "fold choice"
	}
	choice_after = Host.allocated_bytes!({})
	Host.assert!(choice.boundary == PosixBoundary.from_microseconds(last * 1000000 + 500000) and choice_after == choice_before)
	var hours = []
	var parts = []
	var part = 0.U8
	while part < 60 {
		parts = parts.append(part)
		if part < 24 {
			hours = hours.append(part)
		}
		part = part + 1
	}
	clock_anchor = clock_fixture(I64.rem_by(year, 1000000))
	clock_pattern = match ClockPattern.new(clock_anchor, { hours, minutes: parts, seconds: parts }) {
		Ok(value) => value
		Err(_) => crash "full clock pattern"
	}
	clock_before = Host.allocated_bytes!({})
	first_clock = ClockPattern.iter(clock_pattern).take_first(1).fold(None, |_, value| Some(value))
	clock_after = Host.allocated_bytes!({})
	Host.assert!(ClockPattern.count(clock_pattern) == 86400 and first_clock == Some(clock_anchor) and clock_after - clock_before <= ceiling)
	# All 86400 daily clocks over the vast domain remain candidates, not a
	# materialized product. Construction is outside this consumption scope.
	timed_rule = match TimedRecurrence.new(
		{ date: anchor, clock: clock_anchor },
		{
			calendar: CalendarPattern.defaults(Daily),
			clocks: { hours, minutes: parts, seconds: parts },
			termination: Forever,
			by_set_pos: [],
		},
	) {
		Ok(value) => value
		Err(_) => crash "timed resource rule"
	}
	timed_start = LocalDateTime.new(CalendarDate.from_gregorian(anchor), clock_anchor)
	timed_end = LocalDateTime.new(CalendarDate.from_gregorian(end), clock_anchor)
	timed_before = Host.allocated_bytes!({})
	timed_cursor = match TimedRecurrence.cursor(timed_rule, { start: timed_start, end: timed_end }, { rules, occurrence: RequireUnique, gap: RejectGap }) {
		Ok(value) => value
		Err(_) => crash "timed resource cursor"
	}
	timed_first = match TimedRecurrence.Cursor.next(timed_cursor, { max_steps: 8, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 1 }) {
		Ok(value) => value
		Err(_) => crash "timed resource prefix"
	}
	timed_after = Host.allocated_bytes!({})
	Host.assert!(timed_first.steps <= 8 and timed_first.zone_segments == 1 and timed_after - timed_before <= ceiling)
	match timed_first.status {
		Item(item) => Host.assert!(TimedRecurrence.Occurrence.source(item.occurrence) == timed_start)
		_ => Host.assert!(False)
	}
	timed_stream_before = Host.allocated_bytes!({})
	timed_count = TimedRecurrence.Cursor.outcomes(timed_cursor, { max_steps: 8, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 1 }).take_first(1).fold(
		0.U64,
		|_, result| {
			batch = match result {
				Ok(value) => value
				Err(_) => crash "timed stream"
			}
			match batch.status {
				Item(item) => if TimedRecurrence.Occurrence.source(item.occurrence) != timed_start {
					crash "timed stream source"
				}
				_ => crash "timed stream prefix"
			}
			1
		},
	)
	timed_stream_after = Host.allocated_bytes!({})
	# The pinned timed iterator has higher measured traffic than next. Allow
	# 8 KiB traffic for this stage at the standard 4 KiB base ceiling;
	# the short/vast comparison still rejects horizon-dependent allocation.
	Host.assert!(timed_count == 1 and timed_stream_after - timed_stream_before <= ceiling * 2)
	timed_zero_before = Host.allocated_bytes!({})
	timed_zero_count = TimedRecurrence.Cursor.outcomes(timed_cursor, { max_steps: 0, max_buffered: 1, max_zone_segments: 0, max_zone_candidates: 1 }).fold(
		0.U64,
		|count_so_far, result| {
			batch = match result {
				Ok(value) => value
				Err(_) => crash "zero-work timed stream"
			}
			match batch.status {
				Limited(progress) => if progress.reason != WorkLimit {
					crash "zero-work timed reason"
				}
				_ => crash "zero-work timed outcome"
			}
			if batch.steps != 0 or batch.zone_segments != 0 {
				crash "zero-work timed execution"
			}
			count_so_far + 1
		},
	)
	timed_zero_after = Host.allocated_bytes!({})
	Host.assert!(timed_zero_count == 1 and timed_zero_after - timed_zero_before <= ceiling)
	{ bytes: "prefix=1,resume=2,limited=1,zero=1\n".to_utf8(), work: [constructed - before, consumed - constructed, after - consumed, search_after - search_before, zero_after - zero_before, composition_after - composition_before, classification_after - classification_before, choice_after - choice_before, clock_after - clock_before, timed_after - timed_before, timed_stream_after - timed_stream_before, timed_zero_after - timed_zero_before] }
}

fixture_date = |year, day| match GregorianDate.from_fields({ year, month: 1, day }) {
	Ok(value) => value
	Err(_) => crash "fixture date"
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

classification_rules = |transitions, upper| {
	validity = match PosixSpan.new(PosixBoundary.from_microseconds(-2000000), PosixBoundary.from_microseconds(upper)) {
		Ok(value) => value
		Err(_) => crash "classification validity"
	}
	match ZoneRules.new_bounded("Synthetic/Long", "v1", validity, FixedOffset.from_seconds(0), transitions, { minimum: -8192, maximum: 0 }) {
		Ok(value) => value
		Err(_) => crash "classification rules"
	}
}

classification_label = |micros| match FixedOffset.project(FixedOffset.from_seconds(0), PosixBoundary.from_microseconds(micros), Gregorian) {
	Ok(value) => value
	Err(_) => crash "classification label"
}

fixture_offset = |number| match I64.to_i32_try(number) {
	Ok(value) => value
	Err(_) => crash "fixture offset"
}

clock_fixture = |microseconds| match ClockTime.from_microseconds_since_midnight(microseconds) {
	Ok(value) => value
	Err(_) => crash "clock fixture"
}
