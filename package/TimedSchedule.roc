import TimedRecurrence
import TimedOccurrence
import LocalDateTime
import GregorianDate
import CalendarPattern
import Calendar
import ClockTime
import FixedOffset
import PosixBoundary
import PosixDelta
import PosixSpan
import ZoneRules

## Identified appointment spans in source-label order. The window selects
## starts; duration may extend beyond it. IDs preserve the series and source.
## Start and end interpretation share one zone-work budget per call.
## `new` supports source-specific duration or explicit-end overrides.
##
## Example
##
## Use this layer when each recurrence start should become an identified span.
## `Coordinate` measures POSIX microseconds; `Calendar` applies calendar components,
## resolves the end, then adds its coordinate tail. The window selects starts,
## not every appointment overlapping that window.
##
## This example supplies a finite UTC rules snapshot. Applications using named
## zones can pass rules from the optional zone-data package instead. For a complete
## application with calendar-month durations and an extra booking, see
## [equipment loans](https://github.com/lukewilliamboswell/roc-time/tree/main/examples/equipment_loans).
##
## ```roc
## import time.ScheduleDefinition
## import time.Recurrence.Timed as TimedRecurrence

## import time.ScheduleDefinition.OccurrenceCursor as OccurrenceCursor
## import time.Recurrence.CalendarPattern as CalendarPattern
## import time.GregorianDate
## import time.Calendar
## import time.ClockTime
## import time.LocalDateTime
## import time.ZoneRules
## import time.FixedOffset
## import time.PosixSpan
## import time.PosixBoundary
## import time.PosixDelta
##
## expect {
##     date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
##     end_date = GregorianDate.from_fields({ year: 1970, month: 1, day: 4 })?
##     clock = ClockTime.from_microseconds_since_midnight(0)?
##     start = LocalDateTime.new({ date: Calendar.Date.from_gregorian(date), clock })
##     end = LocalDateTime.new({ date: Calendar.Date.from_gregorian(end_date), clock })
##     validity = PosixSpan.from_seconds({ start: -1, end: 345600, rounding: RejectSubmicrosecond })?
##     rules = ZoneRules.Provider.new_bounded({ name: "UTC", version: "fixed", validity, initial: FixedOffset.from_seconds(0), transitions: [], bounds: { minimum: 0, maximum: 0 } })?
##     rule = TimedRecurrence.new({ date, clock }, {
##         calendar: CalendarPattern.defaults(Daily),
##         clocks: { hours: [], minutes: [], seconds: [] },
##         termination: Count(2),
##         by_set_pos: [],
##     })?
##     duration = Coordinate(PosixDelta.from_microseconds(3600000000))
##     schedule = ScheduleDefinition.Cursor.new({ series: 42.U64, rule, window: { start, end }, duration, context: { rules, occurrence: RequireUnique, gap: RejectGap } })?
##     work = {
##         max_steps: 100, max_buffered: 1,
##         max_zone_segments: 10, max_zone_candidates: 1,
##     }
##     result = ScheduleDefinition.Cursor.collect(schedule, {
##         work, max_occurrences: 3,
##     })
##     match result {
##         Err(_) => Bool.False
##         Ok(batch) => match batch.status {
##             Complete => batch.occurrences.len() == 2
##             Limited(_) => Bool.False
##         }
##     }
## }
## ```
##
## When a batch returns `Limited`, process its partial output and resume the returned
## cursor with sufficient budgets. Increasing only the output cap does not fix a
## work or buffer limit.
# TODO: Restore the nested nominal definitions after the compiler's nested
# method shadowing issue is fixed for our supported nightly:
# https://github.com/roc-lang/roc/issues/13077
TimedSchedule(id) :: { series : id, duration : TimedOccurrence.Duration, overrides : List(EndingEntry), starts : TimedRecurrence.Cursor, start_buffered : U64, start_zone_buffered : U64, end_buffered : U64, pending : [None, Some(TimedOccurrence.Cursor({ series : id, source : LocalDateTime }))] }.{
	# TODO: Restore Endings.Entry/ConstructionError after nested alias lookup
	# works on our compiler: https://github.com/roc-lang/roc/issues/11464

	## Checked normalized ending definitions for advanced prepared scheduling.
	## Construction validates duration and normalizes at most 4096 overrides once;
	## no zone resolution or recurrence expansion. This is not a storage format.
	EndingEntry : { source : LocalDateTime, ending : TimedOccurrence.Ending }

	## Invalid duration, excessive overrides or conflicting endings for one source label.
	EndingsError : [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime)]

	## Checked normalized default duration and source-specific ending overrides.
	Endings : TimedScheduleEndings

	## Candidate and zone budgets shared by start and end interpretation during a call; output
	## capacity is supplied separately to collect.
	Limits : TimedRecurrence.Limits

	## Which start, end or output budget stopped execution. Resume the returned cursor to retain
	## source-series and pending-ending state.
	Limit : [StartWorkLimit, StartBufferLimit, StartZoneWorkLimit, StartZoneBufferLimit, EndZoneWorkLimit, EndZoneBufferLimit, OutputLimit]

	## One complete identified appointment with its continuation, End, or a resumable limit;
	## counters include start and end work.
	Next(id) : { steps : U64, zone_segments : U64, start_buffered : U64, start_zone_buffered : U64, end_buffered : U64, status : [End, Item({ occurrence : TimedOccurrence({ series : id, source : LocalDateTime }), cursor : TimedSchedule(id) }), Limited({ cursor : TimedSchedule(id), reason : Limit })] }

	## Complete appointments emitted so far, work counters and Complete/Limited status. A Limited
	## batch is valid partial output, not a complete schedule.
	Batch(id) : { occurrences : List(TimedOccurrence({ series : id, source : LocalDateTime })), steps : U64, zone_segments : U64, status : [Complete, Limited({ cursor : TimedSchedule(id), reason : Limit })] }

	## Malformed duration, invalid window, unavailable zone interpretation or range failure.
	## Resource exhaustion is represented separately by a Limited result.
	Error : [InvalidDuration, OutOfRange, OutsideValidity, InvalidDestination(GregorianDate.Fields), Gap, Ambiguous, AmbiguousGap, OffsetConflict, UnsynchronizedStart]

	## Inputs for a query. The window selects source starts. Endings may extend beyond it.
	Options(id) := {
		series : id,
		rule : TimedRecurrence,
		window : TimedRecurrence.Window,
		duration : TimedOccurrence.Duration,
		context : TimedRecurrence.Context,
		overrides : List(EndingEntry) ?? [],
	}

	## Check ending definitions before creating a fresh query. Overrides replace
	## an ending at its original source label without adding or moving starts.
	new : Options(id) -> Try(TimedSchedule(id), [InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, TooManyOverrides, ConflictingEnding(LocalDateTime)])
	new = |{ series, rule, window, duration, context, overrides }| {
		endings = TimedScheduleEndings.new(duration, overrides)?
		from_prepared({ series, rule, window, endings, context })
	}

	## Advanced construction from checked ending definitions. Duration validation
	## and override normalization are not repeated; query state is fresh.
	## This carries no persistence semantics. Use ScheduleDefinition for ordinary
	## reusable declarations that also retain their explicit context and origin.
	from_prepared : { series : id, rule : TimedRecurrence, window : TimedRecurrence.Window, endings : TimedScheduleEndings, context : TimedRecurrence.Context } -> Try(TimedSchedule(id), [EmptyWindow, ReversedWindow, OutOfRange])
	from_prepared = |{ series, rule, window, endings, context }| {
		{ duration, overrides } = TimedScheduleEndings.definition(endings)
		starts = TimedRecurrence.cursor(rule, { window, context })?
		Ok({ series, duration, overrides, starts, start_buffered: 0, start_zone_buffered: 0, end_buffered: 0, pending: None })
	}

	## At most one start advancement and one end advancement. A pending end
	## resumes before consuming another start. Steps count source-candidate
	## work; constructing a duration adds only bounded calendar arithmetic.
	## Start buffers and the pending end's zone candidates have separate caps.
	next : TimedSchedule(id), Limits -> Try(Next(id), Error)
	next = |initial, limits| {
		var $state = initial
		var $steps = 0.U64
		var $zone_segments = 0.U64
		if $state.start_buffered > limits.max_buffered {
			return Ok({ steps: $steps, zone_segments: $zone_segments, start_buffered: $state.start_buffered, start_zone_buffered: $state.start_zone_buffered, end_buffered: $state.end_buffered, status: Limited({ cursor: $state, reason: StartBufferLimit }) })
		}
		match $state.pending {
			None => {
				batch = match TimedRecurrence.Cursor.next($state.starts, limits) {
					Ok(value) => value
					Err(error) => return Err(error)
				}
				$steps = batch.steps
				$zone_segments = batch.zone_segments
				$state = { ..$state, start_buffered: batch.buffered, start_zone_buffered: batch.zone_buffered }
				match batch.status {
					End => return Ok({ steps: $steps, zone_segments: $zone_segments, start_buffered: $state.start_buffered, start_zone_buffered: $state.start_zone_buffered, end_buffered: 0, status: End })
					Limited(progress) => {
						reason = match progress.reason {
							WorkLimit => StartWorkLimit
							BufferLimit => StartBufferLimit
							ZoneWorkLimit => StartZoneWorkLimit
							ZoneBufferLimit => StartZoneBufferLimit
							OutputLimit => crash "next has no output-cap limit"
						}
						return Ok({ steps: $steps, zone_segments: $zone_segments, start_buffered: $state.start_buffered, start_zone_buffered: $state.start_zone_buffered, end_buffered: 0, status: Limited({ cursor: { ..$state, starts: progress.cursor }, reason }) })
					}
					Item(item) => {
						identity = { series: $state.series, source: TimedRecurrence.Occurrence.source(item.occurrence) }
						pending = match TimedOccurrence.cursor_with_ending({ id: identity, start: item.occurrence, ending: ending_at($state.overrides, identity.source, $state.duration) }) {
							Ok(value) => value
							Err(error) => return Err(error)
						}
						$state = { ..$state, starts: item.cursor, pending: Some(pending) }
					}
				}
			}
			Some(_) => {}
		}
		pending = match $state.pending {
			Some(value) => value
			None => crash "start supplies a pending duration"
		}
		batch = match TimedOccurrence.Cursor.collect(pending, { max_segments: limits.max_zone_segments - $zone_segments, max_candidates: limits.max_zone_candidates }) {
			Ok(value) => value
			Err(error) => return Err(error)
		}
		$zone_segments = $zone_segments + batch.segments
		status = match batch.status {
			Complete(occurrence) => Item({ occurrence, cursor: { ..$state, pending: None, end_buffered: 0 } })
			Limited(progress) => Limited({
				cursor: { ..$state, pending: Some(progress.cursor), end_buffered: batch.buffered },
				reason: match progress.reason {
					WorkLimit => EndZoneWorkLimit
					BufferLimit => EndZoneBufferLimit
				},
			})
		}
		Ok({ steps: $steps, zone_segments: $zone_segments, start_buffered: $state.start_buffered, start_zone_buffered: $state.start_zone_buffered, end_buffered: batch.buffered, status })
	}

	## Output capacity returns Limited without looking ahead. Candidate and
	## zone budgets are totals across every start and end in this batch.
	collect : TimedSchedule(id), { work : Limits, max_occurrences : U64 } -> Try(Batch(id), Error)
	collect = |initial, limits| {
		var $current = initial
		var $occurrences = []
		var $steps = 0.U64
		var $zone_segments = 0.U64
		while $occurrences.len() < limits.max_occurrences {
			batch = next($current, { ..limits.work, max_steps: limits.work.max_steps - $steps, max_zone_segments: limits.work.max_zone_segments - $zone_segments })?
			$steps = $steps + batch.steps
			$zone_segments = $zone_segments + batch.zone_segments
			match batch.status {
				End => return Ok({ occurrences: $occurrences, steps: $steps, zone_segments: $zone_segments, status: Complete })
				Limited(progress) => return Ok({ occurrences: $occurrences, steps: $steps, zone_segments: $zone_segments, status: Limited(progress) })
				Item(item) => {
					$occurrences = $occurrences.append(item.occurrence)
					$current = item.cursor
				}
			}
		}
		Ok({ occurrences: $occurrences, steps: $steps, zone_segments: $zone_segments, status: Limited({ cursor: $current, reason: OutputLimit }) })
	}

	## End, errors and Limited are terminal items; resume a limited cursor
	## explicitly with new budgets. Each advancement uses the supplied limits.
	outcomes : TimedSchedule(id), Limits -> Iter(Try(Next(id), Error))
	outcomes = |initial, limits| Iter.custom(
		Some(initial),
		Err(Unknown),
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

	## Return a bounded diagnostic summary without advancing cursors or enumerating occurrences.
	## Use typed accessors for application logic; this text is not a storage format.
	to_inspect : TimedSchedule(id) -> Str
	to_inspect = |value| "TimedSchedule(start_buffered=${value.start_buffered.to_str()}, end_buffered=${value.end_buffered.to_str()})"
}

test_schedule = |count| test_schedule_until(count, 345600000000)

test_schedule_until = |count, validity_end| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = LocalDateTime.new({ date: Calendar.Date.from_gregorian(date), clock })
	end = LocalDateTime.new({ date: Calendar.Date.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 4 })?), clock })
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(count), by_set_pos: [] })?
	validity = PosixSpan.new({ start: PosixBoundary.from_microseconds(-1), end: PosixBoundary.from_microseconds(validity_end) })?
	rules = ZoneRules.Provider.new_bounded({ name: "Synthetic/UTC", version: "v1", validity, initial: FixedOffset.from_seconds(0), transitions: [], bounds: { minimum: 0, maximum: 0 } })?
	TimedSchedule.new({ series: "service", rule, window: { start, end }, duration: Calendar({ delta: Calendar.Delta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap }), context: { rules, occurrence: RequireUnique, gap: RejectGap } })
}

expect {
	initial = test_schedule(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 3.U64, max_zone_candidates: 1.U64 }
	first = TimedSchedule.collect(initial, { work, max_occurrences: 10 })?
	var $valid = first.zone_segments == 3 and first.occurrences.len() == 1
	rest = match first.status {
		Limited(progress) => {
			$valid = $valid and progress.reason == EndZoneWorkLimit
			progress.cursor
		}
		Complete => crash "three segments cannot resolve two starts and two ends"
	}
	second = TimedSchedule.collect(rest, { work: { ..work, max_steps: 0, max_zone_segments: 1 }, max_occurrences: 10 })?
	$valid = $valid and second.steps == 0 and second.zone_segments == 1 and second.occurrences.len() == 1
	var $starts = []
	for occurrence in first.occurrences.concat(second.occurrences) {
		$valid = $valid and TimedOccurrence.id(occurrence).series == "service" and PosixSpan.coordinate_width(TimedOccurrence.span(occurrence)) == Ok(PosixDelta.from_microseconds(86400000000))
		$starts = $starts.append(PosixSpan.start(TimedOccurrence.span(occurrence)))
	}
	$valid and $starts == [PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(86400000000)] and match second.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}
}

expect {
	initial = test_schedule(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 100.U64, max_zone_candidates: 1.U64 }
	zero = TimedSchedule.collect(initial, { work, max_occurrences: 0 })?
	var $valid = zero.steps == 0 and zero.zone_segments == 0 and zero.occurrences.is_empty()
	rest = match zero.status {
		Limited(progress) => {
			$valid = $valid and progress.reason == OutputLimit
			progress.cursor
		}
		Complete => crash "zero output must not look ahead"
	}
	full = TimedSchedule.collect(rest, { work, max_occurrences: 2 })?
	rest_after_full = match full.status {
		Limited(progress) => {
			$valid = $valid and progress.reason == OutputLimit
			progress.cursor
		}
		Complete => crash "exact capacity must not look ahead"
	}
	ended = TimedSchedule.collect(rest_after_full, { work: { ..work, max_steps: 0, max_zone_segments: 0 }, max_occurrences: 1 })?
	var $zero_count = 0.U64
	for result in TimedSchedule.outcomes(initial, { ..work, max_steps: 0, max_zone_segments: 0 }) {
		batch = result?
		$zero_count = $zero_count + 1
		$valid = $valid and match batch.status {
			Limited(progress) => progress.reason == StartWorkLimit
			_ => Bool.False
		}
	}
	$valid and $zero_count == 1 and full.occurrences.len() == 2 and ended.occurrences.is_empty() and match ended.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}
}

# R12: every start/end budget boundary is resumable without losing identity.
expect {
	initial = test_schedule(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 100.U64, max_zone_candidates: 1.U64 }
	full = TimedSchedule.collect(initial, { work, max_occurrences: 3 })?
	var $valid = Bool.True
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
		$valid = $valid and resumed.occurrences.len() == full.occurrences.len()
		var $index = 0.U64
		for occurrence in resumed.occurrences {
			expected = full.occurrences.get($index)?
			$valid = $valid and TimedOccurrence.id(occurrence) == TimedOccurrence.id(expected)
			$valid = $valid and TimedOccurrence.span(occurrence) == TimedOccurrence.span(expected)
			$index = $index + 1
		}
		$valid = $valid and match resumed.status {
			Complete => Bool.True
			_ => Bool.False
		}
	}
	$valid
}

# A valid start must not turn a failed calendar end into an empty success.
expect {
	initial = test_schedule_until(1, 86400000000)?
	match TimedSchedule.collect(initial, { work: { max_steps: 100, max_buffered: 1, max_zone_segments: 100, max_zone_candidates: 1 }, max_occurrences: 2 }) {
		Err(OutsideValidity) => Bool.True
		_ => Bool.False
	}
}

ending_at : List(TimedSchedule.EndingEntry), LocalDateTime, TimedOccurrence.Duration -> TimedOccurrence.Ending
ending_at = |overrides, source, fallback| {
	var $lower = 0.U64
	var $upper = overrides.len()
	while $lower < $upper {
		middle = $lower + U64.div_trunc_by($upper - $lower, 2)
		entry = match overrides.get(middle) {
			Ok(value) => value
			Err(_) => crash "override binary search invariant"
		}
		match LocalDateTime.compare_position({ left: entry.source, right: source }) {
			Same => return entry.ending
			Before => {
				$lower = middle + 1
			}
			After => {
				$upper = middle
			}
		}
	}
	After(fallback)
}

test_override_sources = |_| {
	clock = ClockTime.from_microseconds_since_midnight(0)?
	var $sources = []
	for day in [1.U8, 2, 3, 4] {
		date = GregorianDate.from_fields({ year: 1970, month: 1, day })?
		$sources = $sources.append(LocalDateTime.new({ date: Calendar.Date.from_gregorian(date), clock }))
	}
	Ok($sources)
}

# R11/R12: an extra start uses its own duration, a rule start is overridden
# once despite duplicates, and exclusions/query restriction preserve COUNT.
test_overrides = |exclude, window_day, work| {
	sources = test_override_sources({})?
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	base = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(2), by_set_pos: [] })?
	included = TimedRecurrence.with_inclusions(base, [{ date: GregorianDate.from_fields({ year: 1970, month: 1, day: 3 })?, clock }])?
	rule = TimedRecurrence.with_exclusions(
		included,
		if exclude {
			[sources.get(1)?]
		} else {
			[]
		},
	)?
	validity = PosixSpan.new({ start: PosixBoundary.from_microseconds(-1), end: PosixBoundary.from_microseconds(518400000000) })?
	rules = ZoneRules.Provider.new_bounded({ name: "Synthetic/UTC", version: "v1", validity, initial: FixedOffset.from_seconds(0), transitions: [], bounds: { minimum: 0, maximum: 0 } })?
	calendar : TimedOccurrence.Duration
	calendar = Calendar({ delta: Calendar.Delta.days(2), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
	short : TimedOccurrence.Duration
	short = Coordinate(PosixDelta.from_microseconds(7200000000))
	var $cursor = TimedSchedule.new({ series: 42.U64, rule, window: { start: sources.get(window_day - 1)?, end: sources.get(3)? }, duration: Coordinate(PosixDelta.from_microseconds(86400000000)), overrides: [{ source: sources.get(2)?, ending: After(calendar) }, { source: sources.get(1)?, ending: After(short) }, { source: sources.get(1)?, ending: After(short) }], context: { rules, occurrence: RequireUnique, gap: RejectGap } })?
	var $observed = []
	var $calls = 0.U64
	while $calls < 1000 {
		batch = match TimedSchedule.collect($cursor, { work, max_occurrences: 1 }) {
			Ok(value) => value
			Err(error) => return Err(Interpretation(error))
		}
		if batch.steps > work.max_steps or batch.zone_segments > work.max_zone_segments {
			return Ok(Bool.False)
		}
		for occurrence in batch.occurrences {
			identity = TimedOccurrence.id(occurrence)
			if identity.series != 42 or identity.source != TimedRecurrence.Occurrence.source(TimedOccurrence.start(occurrence)) {
				return Ok(Bool.False)
			}
			$observed = $observed.append(PosixDelta.to_microseconds(PosixSpan.coordinate_width(TimedOccurrence.span(occurrence))?))
		}
		match batch.status {
			Complete => {
				var $expected = []
				if window_day == 1 {
					$expected = $expected.append(86400000000.I64)
				}
				if !exclude {
					$expected = $expected.append(7200000000)
				}
				$expected = $expected.append(172800000000)
				return Ok($observed == $expected)
			}
			Limited(progress) => {
				$cursor = progress.cursor
			}
		}
		$calls = $calls + 1
	}
	Ok(Bool.False)
}

expect test_overrides(Bool.False, 1, { max_steps: 1, max_buffered: 2, max_zone_segments: 1, max_zone_candidates: 1 }) == Ok(Bool.True)
expect test_overrides(Bool.True, 1, { max_steps: 100, max_buffered: 2, max_zone_segments: 100, max_zone_candidates: 1 }) == Ok(Bool.True)
expect test_overrides(Bool.False, 2, { max_steps: 1, max_buffered: 2, max_zone_segments: 1, max_zone_candidates: 1 }) == Ok(Bool.True)

expect {
	source = test_override_sources({})?.get(0)?
	one : TimedOccurrence.Duration
	one = Coordinate(PosixDelta.from_microseconds(86400000000))
	calendar : TimedOccurrence.Duration
	calendar = Calendar({ delta: Calendar.Delta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
	match TimedScheduleEndings.normalize([{ source, ending: After(one) }, { source, ending: After(calendar) }]) {
		Err(ConflictingEnding(value)) => value == source
		_ => Bool.False
	}
}

expect {
	source = test_override_sources({})?.get(0)?
	match TimedScheduleEndings.normalize([{ source, ending: After(Coordinate(PosixDelta.from_microseconds(0))) }]) {
		Err(InvalidDuration) => Bool.True
		_ => Bool.False
	}
}

expect {
	source = test_override_sources({})?.get(0)?
	entry : TimedSchedule.EndingEntry
	entry = { source, ending: After(Coordinate(PosixDelta.from_microseconds(1))) }
	match TimedScheduleEndings.normalize(List.repeat(entry, 4097)) {
		Err(TooManyOverrides) => Bool.True
		_ => Bool.False
	}
}

# Gap adjustment can map two sources to one boundary. Duration overrides
# follow the original source identity, never the coincident timeline position.
expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_fields({ hour: 2, minute: 30, second: 0, microsecond: 0 })?
	source = LocalDateTime.new({ date: Calendar.Date.from_gregorian(date), clock })
	end = LocalDateTime.new({ date: Calendar.Date.from_gregorian(date), clock: ClockTime.from_fields({ hour: 4, minute: 0, second: 0, microsecond: 0 })? })
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [2, 3], minutes: [], seconds: [] }, termination: Count(2), by_set_pos: [] })?
	validity = PosixSpan.new({ start: PosixBoundary.from_microseconds(-86400000000), end: PosixBoundary.from_microseconds(172800000000) })?
	rules = ZoneRules.Provider.new_bounded({ name: "Synthetic/Gap", version: "v1", validity, initial: FixedOffset.from_seconds(0), transitions: [{ at: PosixBoundary.from_microseconds(7200000000), offset: FixedOffset.from_seconds(3600) }], bounds: { minimum: 0, maximum: 3600 } })?
	initial = TimedSchedule.new({ series: 42.U64, rule, window: { start: source, end }, duration: Coordinate(PosixDelta.from_microseconds(3600000000)), overrides: [{ source, ending: After(Coordinate(PosixDelta.from_microseconds(7200000000))) }], context: { rules, occurrence: First, gap: UseOffsetBeforeGap } })?
	batch = match TimedSchedule.collect(initial, { work: { max_steps: 100, max_buffered: 1, max_zone_segments: 100, max_zone_candidates: 2 }, max_occurrences: 3 }) {
		Ok(value) => value
		Err(_) => crash "unexpected gap schedule error"
	}
	first = batch.occurrences.get(0)?
	second = batch.occurrences.get(1)?
	batch.occurrences.len() == 2 and TimedOccurrence.id(first).source == source and TimedOccurrence.id(second).source != source and PosixSpan.start(TimedOccurrence.span(first)) == PosixBoundary.from_microseconds(9000000000) and PosixSpan.start(TimedOccurrence.span(first)) == PosixSpan.start(TimedOccurrence.span(second)) and PosixSpan.coordinate_width(TimedOccurrence.span(first)) == Ok(PosixDelta.from_microseconds(7200000000)) and PosixSpan.coordinate_width(TimedOccurrence.span(second)) == Ok(PosixDelta.from_microseconds(3600000000))
}

expect {
	source = test_override_sources({})?.get(0)?
	boundary = PosixBoundary.from_microseconds(86400000000)
	# Definitions stay distinct even if a particular interpretation could
	# give them equal extents; conflicting inputs do not silently pick one.
	conflict = match TimedScheduleEndings.normalize([{ source, ending: AtBoundary(boundary) }, { source, ending: After(Coordinate(PosixDelta.from_microseconds(86400000000))) }]) {
		Err(ConflictingEnding(position)) => position == source
		_ => Bool.False
	}
	invalid = match TimedScheduleEndings.normalize([{ source, ending: After(Coordinate(PosixDelta.from_microseconds(0))) }]) {
		Err(InvalidDuration) => Bool.True
		_ => Bool.False
	}
	entry = { source, ending: AtBoundary(boundary) }
	too_many = match TimedScheduleEndings.normalize(List.repeat(entry, 4097)) {
		Err(TooManyOverrides) => Bool.True
		_ => Bool.False
	}
	conflict and invalid and too_many and TimedScheduleEndings.normalize([entry, entry])?.len() == 1
}

schedule_endings_normalize_endings : List(TimedSchedule.EndingEntry) -> Try(List(TimedSchedule.EndingEntry), [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime)])
schedule_endings_normalize_endings = |inputs| {
	if inputs.len() > 4096 {
		return Err(TooManyOverrides)
	}
	for input in inputs {
		match input.ending {
			After(duration) => {
				TimedOccurrence.validate_duration(duration)?
			}
			_ => {}
		}
	}
	sorted = inputs.sort_with(
		|a, b| LocalDateTime.compare_position({ left: a.source, right: b.source }),
	)
	var $result = []
	var $previous = None
	for input in sorted {
		distinct = match $previous {
			None => Bool.True
			Some(value) => if LocalDateTime.same_position(value.source, input.source) {
				if !schedule_endings_same_ending_definition(value.ending, input.ending) {
					return Err(ConflictingEnding(input.source))
				}
				Bool.False
			} else {
				Bool.True
			}
		}
		if distinct {
			$result = $result.append(input)
		}
		$previous = Some(input)
	}
	Ok($result)
}

schedule_endings_same_ending_definition : TimedOccurrence.Ending, TimedOccurrence.Ending -> Bool
schedule_endings_same_ending_definition = |a, b| match (a, b) {
	(After(left), After(right)) => schedule_endings_same_duration_definition(left, right)
	(AtBoundary(left), AtBoundary(right)) => left == right
	(AtLocal(left), AtLocal(right)) => left.source == right.source and left.occurrence == right.occurrence and left.gap == right.gap
	_ => Bool.False
}

# Compare input meaning, not the extent of a particular resolved occurrence.
schedule_endings_same_duration_definition : TimedOccurrence.Duration, TimedOccurrence.Duration -> Bool
schedule_endings_same_duration_definition = |left, right| match (left, right) {
	(Coordinate(a), Coordinate(b)) => PosixDelta.to_microseconds(a) == PosixDelta.to_microseconds(b)
	(Calendar(a), Calendar(b)) => {
		x = Calendar.Delta.to_components(a.delta)
		y = Calendar.Delta.to_components(b.delta)
		x.years == y.years and x.months == y.months and x.days == y.days and a.invalid_date == b.invalid_date and a.tail == b.tail and a.occurrence == b.occurrence and a.gap == b.gap
	}
	_ => Bool.False
}

# Tagged field hashing mirrors declaration equality without materializing keys.
schedule_endings_hash_duration : TimedOccurrence.Duration, Hasher -> Hasher
schedule_endings_hash_duration = |duration, hasher| match duration {
	Coordinate(value) => PosixDelta.to_microseconds(value).to_hash((0.U8).to_hash(hasher))
	Calendar(value) => {
		parts = Calendar.Delta.to_components(value.delta)
		base = parts.days.to_hash(parts.months.to_hash(parts.years.to_hash((1.U8).to_hash(hasher))))
		policy : U8
		policy = match value.invalid_date {
			Reject => 0
			Clamp => 1
			Carry => 2
		}
		tail = PosixDelta.to_microseconds(value.tail).to_hash(policy.to_hash(base))
		schedule_endings_hash_gap(value.gap, schedule_endings_hash_occurrence(value.occurrence, tail))
	}
}

schedule_endings_hash_ending : TimedOccurrence.Ending, Hasher -> Hasher
schedule_endings_hash_ending = |ending, hasher| match ending {
	After(duration) => schedule_endings_hash_duration(duration, (0.U8).to_hash(hasher))
	AtBoundary(point) => point.to_hash((1.U8).to_hash(hasher))
	AtLocal(value) => schedule_endings_hash_gap(value.gap, schedule_endings_hash_occurrence(value.occurrence, value.source.to_hash((2.U8).to_hash(hasher))))
}

schedule_endings_hash_occurrence : ZoneRules.OccurrencePolicy, Hasher -> Hasher
schedule_endings_hash_occurrence = |policy, hasher| match policy {
	RequireUnique => (0.U8).to_hash(hasher)
	First => (1.U8).to_hash(hasher)
	Last => (2.U8).to_hash(hasher)
	MatchingOffset(offset) => FixedOffset.to_seconds(offset).to_hash((3.U8).to_hash(hasher))
}

schedule_endings_hash_gap : [RejectGap, UseOffsetBeforeGap], Hasher -> Hasher
schedule_endings_hash_gap = |policy, hasher| match policy {
	RejectGap => (0.U8).to_hash(hasher)
	UseOffsetBeforeGap => (1.U8).to_hash(hasher)
}

TimedScheduleEndings :: { duration : TimedOccurrence.Duration, overrides : List(TimedSchedule.EndingEntry) }.{

	## One source-label-specific ending. The original source identifies the override,
	## even when another source resolves to the same boundary.

	## Rejected default duration, excessive entries or conflicting endings for a source.

	## Check and normalize up to 4096 source-specific ending overrides. Duplicate equal endings
	## collapse; conflicting endings for one source return ConflictingEnding.
	normalize : List(TimedSchedule.EndingEntry) -> Try(List(TimedSchedule.EndingEntry), [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime)])
	normalize = schedule_endings_normalize_endings

	## Validate the positive default duration and normalize ending overrides once for reuse
	## across queries. Does not resolve zones or enumerate starts.
	new : TimedOccurrence.Duration, List(TimedSchedule.EndingEntry) -> Try(TimedScheduleEndings, [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime)])
	new = |duration, inputs| {
		overrides = schedule_endings_normalize_endings(inputs)?
		TimedOccurrence.validate_duration(duration)?
		Ok({ duration, overrides })
	}

	## Compare retained duration and normalized source-ending intent. This is declaration
	## equality, not equivalence of resulting appointment spans.
	is_eq : TimedScheduleEndings, TimedScheduleEndings -> Bool
	is_eq = |a, b| {
		if !schedule_endings_same_duration_definition(a.duration, b.duration) or a.overrides.len() != b.overrides.len() {
			return Bool.False
		}
		var $index = 0.U64
		while $index < a.overrides.len() {
			left = a.overrides.get($index) ?? crash "validated equal list lengths"
			right = b.overrides.get($index) ?? crash "validated equal list lengths"
			if left.source != right.source or !schedule_endings_same_ending_definition(left.ending, right.ending) {
				return Bool.False
			}
			$index = $index + 1
		}
		Bool.True
	}

	## Hash the same declaration fields used by equality, including policies and original
	## override sources, for dictionary keys.
	to_hash : TimedScheduleEndings, Hasher -> Hasher
	to_hash = |value, hasher| {
		var $hash = value.overrides.len().to_hash(schedule_endings_hash_duration(value.duration, hasher))
		for entry in value.overrides {
			$hash = schedule_endings_hash_ending(entry.ending, entry.source.to_hash($hash))
		}
		$hash
	}

	## Read the checked default duration and normalized overrides for editing or inspection. The
	## returned fields are not a persistence format.
	definition : TimedScheduleEndings -> { duration : TimedOccurrence.Duration, overrides : List(TimedSchedule.EndingEntry) }
	definition = |value| { duration: value.duration, overrides: value.overrides }
}
