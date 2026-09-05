import TimedRecurrence
import TimedOccurrence
import LocalDateTime
import GregorianDate
import CalendarPattern
import CalendarDate
import CalendarDelta
import ClockTime
import FixedOffset
import PosixBoundary
import PosixDelta
import PosixSpan
import ZoneRules

## Identified appointment spans in source-label order. The window selects
## starts; duration may extend beyond it. IDs preserve the series and source.
## Start and end interpretation share one zone-work budget per call.
TimedSchedule(id) :: { series : id, duration : TimedOccurrence.Duration, starts : TimedRecurrence.Cursor, start_buffered : U64, start_zone_buffered : U64, end_buffered : U64, pending : [None, Some(TimedOccurrence.Cursor({ series : id, source : LocalDateTime }))] }.{
	Limits : TimedRecurrence.Limits
	Limit : [StartWorkLimit, StartBufferLimit, StartZoneWorkLimit, StartZoneBufferLimit, EndZoneWorkLimit, EndZoneBufferLimit, OutputLimit]
	Next(id) : { steps : U64, zone_segments : U64, start_buffered : U64, start_zone_buffered : U64, end_buffered : U64, status : [End, Item({ occurrence : TimedOccurrence({ series : id, source : LocalDateTime }), cursor : TimedSchedule(id) }), Limited({ cursor : TimedSchedule(id), reason : Limit })] }
	Batch(id) : { occurrences : List(TimedOccurrence({ series : id, source : LocalDateTime })), steps : U64, zone_segments : U64, status : [Complete, Limited({ cursor : TimedSchedule(id), reason : Limit })] }
	Error : [InvalidDuration, OutOfRange, OutsideValidity, InvalidDestination(GregorianDate.Fields), Gap, Ambiguous, AmbiguousGap, OffsetConflict, UnsynchronizedStart]
	new : id, TimedRecurrence, TimedRecurrence.Window, TimedOccurrence.Duration, TimedRecurrence.Context -> Try(TimedSchedule(id), [InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, ..])
	new = |series, rule, window, duration, context| {
		TimedOccurrence.validate_duration(duration)?
		starts = TimedRecurrence.cursor(rule, window, context)?
		Ok({ series, duration, starts, start_buffered: 0, start_zone_buffered: 0, end_buffered: 0, pending: None })
	}

	## At most one start advancement and one end advancement. A pending end
	## resumes before consuming another start. Steps count source-candidate
	## work; constructing a duration adds only bounded calendar arithmetic.
	## Start buffers and the pending end's zone candidates have separate caps.
	next : TimedSchedule(id), Limits -> Try(Next(id), Error)
	next = |initial, limits| {
		var state = initial
		var steps = 0.U64
		var zone_segments = 0.U64
		if state.start_buffered > limits.max_buffered {
			return Ok({ steps, zone_segments, start_buffered: state.start_buffered, start_zone_buffered: state.start_zone_buffered, end_buffered: state.end_buffered, status: Limited({ cursor: state, reason: StartBufferLimit }) })
		}
		match state.pending {
			None => {
				batch = match TimedRecurrence.Cursor.next(state.starts, limits) {
					Ok(value) => value
					Err(error) => return Err(error)
				}
				steps = batch.steps
				zone_segments = batch.zone_segments
				state = { ..state, start_buffered: batch.buffered, start_zone_buffered: batch.zone_buffered }
				match batch.status {
					End => return Ok({ steps, zone_segments, start_buffered: state.start_buffered, start_zone_buffered: state.start_zone_buffered, end_buffered: 0, status: End })
					Limited(progress) => {
						reason = match progress.reason {
							WorkLimit => StartWorkLimit
							BufferLimit => StartBufferLimit
							ZoneWorkLimit => StartZoneWorkLimit
							ZoneBufferLimit => StartZoneBufferLimit
							OutputLimit => crash "next has no output-cap limit"
						}
						return Ok({ steps, zone_segments, start_buffered: state.start_buffered, start_zone_buffered: state.start_zone_buffered, end_buffered: 0, status: Limited({ cursor: { ..state, starts: progress.cursor }, reason }) })
					}
					Item(item) => {
						identity = { series: state.series, source: TimedRecurrence.Occurrence.source(item.occurrence) }
						pending = match TimedOccurrence.cursor(identity, item.occurrence, state.duration) {
							Ok(value) => value
							Err(error) => return Err(error)
						}
						state = { ..state, starts: item.cursor, pending: Some(pending) }
					}
				}
			}
			Some(_) => {}
		}
		pending = match state.pending {
			Some(value) => value
			None => crash "start supplies a pending duration"
		}
		batch = match TimedOccurrence.Cursor.collect(pending, { max_segments: limits.max_zone_segments - zone_segments, max_candidates: limits.max_zone_candidates }) {
			Ok(value) => value
			Err(error) => return Err(error)
		}
		zone_segments = zone_segments + batch.segments
		status = match batch.status {
			Complete(occurrence) => Item({ occurrence, cursor: { ..state, pending: None, end_buffered: 0 } })
			Limited(progress) => Limited({
				cursor: { ..state, pending: Some(progress.cursor), end_buffered: batch.buffered },
				reason: match progress.reason {
					WorkLimit => EndZoneWorkLimit
					BufferLimit => EndZoneBufferLimit
				},
			})
		}
		Ok({ steps, zone_segments, start_buffered: state.start_buffered, start_zone_buffered: state.start_zone_buffered, end_buffered: batch.buffered, status })
	}

	## Output capacity returns Limited without looking ahead. Candidate and
	## zone budgets are totals across every start and end in this batch.
	collect : TimedSchedule(id), { work : Limits, max_occurrences : U64 } -> Try(Batch(id), Error)
	collect = |initial, limits| {
		var current = initial
		var occurrences = []
		var steps = 0.U64
		var zone_segments = 0.U64
		while occurrences.len() < limits.max_occurrences {
			batch = next(current, { ..limits.work, max_steps: limits.work.max_steps - steps, max_zone_segments: limits.work.max_zone_segments - zone_segments })?
			steps = steps + batch.steps
			zone_segments = zone_segments + batch.zone_segments
			match batch.status {
				End => return Ok({ occurrences, steps, zone_segments, status: Complete })
				Limited(progress) => return Ok({ occurrences, steps, zone_segments, status: Limited(progress) })
				Item(item) => {
					occurrences = occurrences.append(item.occurrence)
					current = item.cursor
				}
			}
		}
		Ok({ occurrences, steps, zone_segments, status: Limited({ cursor: current, reason: OutputLimit }) })
	}

	## End, errors and Limited are terminal items; resume a limited cursor
	## explicitly with new budgets. Each advancement uses the supplied limits.
	outcomes : TimedSchedule(id), Limits -> Iter(Try(Next(id), Error))
	outcomes = |initial, limits| Iter.custom(
		Some(initial),
		Unknown,
		|state| match state {
			None => Err(NoMore)
			Some(current) => {
				result = next(current, limits)
				rest = match result {
					Ok(batch) => match batch.status {
						Item(item) => Some(item.cursor)
						_ => None
					}
					Err(_) => None
				}
				Ok((result, rest))
			}
		},
	)
	to_inspect : TimedSchedule(id) -> Str
	to_inspect = |value| "TimedSchedule(start_buffered=${value.start_buffered.to_str()}, end_buffered=${value.end_buffered.to_str()})"
}

test_schedule = |count| test_schedule_until(count, 345600000000)

test_schedule_until = |count, validity_end| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 4 })?), clock)
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(count), by_set_pos: [] })?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-1), PosixBoundary.from_microseconds(validity_end))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	TimedSchedule.new("service", rule, { start, end }, Calendar({ delta: CalendarDelta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap }), { rules, occurrence: RequireUnique, gap: RejectGap })
}

expect {
	initial = test_schedule(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 3.U64, max_zone_candidates: 1.U64 }
	first = TimedSchedule.collect(initial, { work, max_occurrences: 10 })?
	var valid = first.zone_segments == 3 and first.occurrences.len() == 1
	rest = match first.status {
		Limited(progress) => {
			valid = valid and progress.reason == EndZoneWorkLimit
			progress.cursor
		}
		Complete => crash "three segments cannot resolve two starts and two ends"
	}
	second = TimedSchedule.collect(rest, { work: { ..work, max_steps: 0, max_zone_segments: 1 }, max_occurrences: 10 })?
	valid = valid and second.steps == 0 and second.zone_segments == 1 and second.occurrences.len() == 1
	var starts = []
	for occurrence in first.occurrences.concat(second.occurrences) {
		valid = valid and TimedOccurrence.id(occurrence).series == "service" and PosixSpan.coordinate_width(TimedOccurrence.span(occurrence)) == Ok(PosixDelta.from_microseconds(86400000000))
		starts = starts.append(PosixSpan.start(TimedOccurrence.span(occurrence)))
	}
	valid and starts == [PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(86400000000)] and match second.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}
}

expect {
	initial = test_schedule(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 100.U64, max_zone_candidates: 1.U64 }
	zero = TimedSchedule.collect(initial, { work, max_occurrences: 0 })?
	var valid = zero.steps == 0 and zero.zone_segments == 0 and zero.occurrences.is_empty()
	rest = match zero.status {
		Limited(progress) => {
			valid = valid and progress.reason == OutputLimit
			progress.cursor
		}
		Complete => crash "zero output must not look ahead"
	}
	full = TimedSchedule.collect(rest, { work, max_occurrences: 2 })?
	rest_after_full = match full.status {
		Limited(progress) => {
			valid = valid and progress.reason == OutputLimit
			progress.cursor
		}
		Complete => crash "exact capacity must not look ahead"
	}
	ended = TimedSchedule.collect(rest_after_full, { work: { ..work, max_steps: 0, max_zone_segments: 0 }, max_occurrences: 1 })?
	var zero_count = 0.U64
	for result in TimedSchedule.outcomes(initial, { ..work, max_steps: 0, max_zone_segments: 0 }) {
		batch = result?
		zero_count = zero_count + 1
		valid = valid and match batch.status {
			Limited(progress) => progress.reason == StartWorkLimit
			_ => Bool.False
		}
	}
	valid and zero_count == 1 and full.occurrences.len() == 2 and ended.occurrences.is_empty() and match ended.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}
}

# R12: every start/end budget boundary is resumable without losing identity.
expect {
	initial = test_schedule(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 100.U64, max_zone_candidates: 1.U64 }
	full = TimedSchedule.collect(initial, { work, max_occurrences: 3 })?
	var valid = Bool.True
	for constrained in [
		{ ..work, max_steps: 0 },
		{ ..work, max_buffered: 0 },
		{ ..work, max_zone_segments: 0 },
		{ ..work, max_zone_candidates: 0 },
		{ ..work, max_zone_segments: 1 },
	] {
		paused = TimedSchedule.next(initial, constrained)?
		rest = match paused.status {
			Limited(progress) => progress.cursor
			_ => crash "constrained schedule must pause"
		}
		resumed = TimedSchedule.collect(rest, { work, max_occurrences: 3 })?
		valid = valid and resumed.occurrences.len() == full.occurrences.len()
		var index = 0.U64
		for occurrence in resumed.occurrences {
			expected = full.occurrences.get(index)?
			valid = valid and TimedOccurrence.id(occurrence) == TimedOccurrence.id(expected)
			valid = valid and TimedOccurrence.span(occurrence) == TimedOccurrence.span(expected)
			index = index + 1
		}
		valid = valid and match resumed.status {
			Complete => Bool.True
			_ => Bool.False
		}
	}
	valid
}

# A valid start must not turn a failed calendar end into an empty success.
expect {
	initial = test_schedule_until(1, 86400000000)?
	match TimedSchedule.collect(initial, { work: { max_steps: 100, max_buffered: 1, max_zone_segments: 100, max_zone_candidates: 1 }, max_occurrences: 2 }) {
		Err(OutsideValidity) => Bool.True
		_ => Bool.False
	}
}
