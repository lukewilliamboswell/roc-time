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
## `new_with_endings` supports source-specific duration or explicit-end overrides.
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
## import time.TimedSchedule
## import time.TimedRecurrence
## import time.TimedOccurrence
## import time.CalendarPattern
## import time.GregorianDate
## import time.CalendarDate
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
##     start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
##     end = LocalDateTime.new(CalendarDate.from_gregorian(end_date), clock)
##     validity = PosixSpan.from_seconds(-1, 345600, RejectSubmicrosecond)?
##     rules = ZoneRules.new_bounded(
##         "UTC", "fixed", validity,
##         FixedOffset.from_seconds(0), [],
##         { minimum: 0, maximum: 0 },
##     )?
##     rule = TimedRecurrence.new({ date, clock }, {
##         calendar: CalendarPattern.defaults(Daily),
##         clocks: { hours: [], minutes: [], seconds: [] },
##         termination: Count(2),
##         by_set_pos: [],
##     })?
##     duration = Coordinate(PosixDelta.from_microseconds(3600000000))
##     schedule = TimedSchedule.new(
##         42.U64, rule, { start, end }, duration,
##         { rules, occurrence: RequireUnique, gap: RejectGap },
##     )?
##     work = {
##         max_steps: 100, max_buffered: 1,
##         max_zone_segments: 10, max_zone_candidates: 1,
##     }
##     result = TimedSchedule.collect(schedule, {
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
TimedSchedule(id) :: { series : id, duration : TimedOccurrence.Duration, overrides : List(EndOverride), starts : TimedRecurrence.Cursor, start_buffered : U64, start_zone_buffered : U64, end_buffered : U64, pending : [None, Some(TimedOccurrence.Cursor({ series : id, source : LocalDateTime }))] }.{
	EndOverride : { source : LocalDateTime, ending : TimedOccurrence.Ending }
	Override : { source : LocalDateTime, duration : TimedOccurrence.Duration }
	Limits : TimedRecurrence.Limits
	Limit : [StartWorkLimit, StartBufferLimit, StartZoneWorkLimit, StartZoneBufferLimit, EndZoneWorkLimit, EndZoneBufferLimit, OutputLimit]
	Next(id) : { steps : U64, zone_segments : U64, start_buffered : U64, start_zone_buffered : U64, end_buffered : U64, status : [End, Item({ occurrence : TimedOccurrence({ series : id, source : LocalDateTime }), cursor : TimedSchedule(id) }), Limited({ cursor : TimedSchedule(id), reason : Limit })] }
	Batch(id) : { occurrences : List(TimedOccurrence({ series : id, source : LocalDateTime })), steps : U64, zone_segments : U64, status : [Complete, Limited({ cursor : TimedSchedule(id), reason : Limit })] }
	Error : [InvalidDuration, OutOfRange, OutsideValidity, InvalidDestination(GregorianDate.Fields), Gap, Ambiguous, AmbiguousGap, OffsetConflict, UnsynchronizedStart]
	new : id, TimedRecurrence, TimedRecurrence.Window, TimedOccurrence.Duration, TimedRecurrence.Context -> Try(TimedSchedule(id), [InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, ..])
	new = |series, rule, window, duration, context| {
		TimedOccurrence.validate_duration(duration)?
		starts = TimedRecurrence.cursor(rule, window, context)?
		Ok({ series, duration, overrides: [], starts, start_buffered: 0, start_zone_buffered: 0, end_buffered: 0, pending: None })
	}

	## Override durations at original source positions, including explicit
	## inclusions. This does not add starts: configure those on the rule.
	## Exclusions still win; overrides do not replenish COUNT or change IDs.
	## At most 4096 inputs, sorted once in O(n log n), then O(log n) lookup.
	## Identical definitions coalesce; conflicting definitions at one position
	## return ConflictingDuration, even outside the query or at excluded starts.
	## Calendar and coordinate definitions remain distinct despite equal widths.
	new_with_overrides : id, TimedRecurrence, TimedRecurrence.Window, TimedOccurrence.Duration, List(Override), TimedRecurrence.Context -> Try(TimedSchedule(id), [InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, TooManyOverrides, ConflictingDuration(LocalDateTime), ..])
	new_with_overrides = |series, rule, window, duration, inputs, context| {
		overrides = normalize_overrides(inputs)?
		base = new(series, rule, window, duration, context)?
		Ok({ ..base, overrides })
	}

	## Override a source with a duration or explicit end, without adding starts.
	## The same 4096-entry limit and positional lookup apply. Equal definitions
	## coalesce; different definitions at one position return ConflictingEnding.
	## Endpoint order is checked after the start and end are interpreted.
	new_with_endings : id, TimedRecurrence, TimedRecurrence.Window, TimedOccurrence.Duration, List(EndOverride), TimedRecurrence.Context -> Try(TimedSchedule(id), [InvalidDuration, EmptyWindow, ReversedWindow, OutOfRange, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
	new_with_endings = |series, rule, window, duration, inputs, context| {
		overrides = normalize_endings(inputs)?
		base = new(series, rule, window, duration, context)?
		Ok({ ..base, overrides })
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
						pending = match TimedOccurrence.cursor_with_ending(identity, item.occurrence, ending_at($state.overrides, identity.source, $state.duration)) {
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

normalize_overrides : List(TimedSchedule.Override) -> Try(List(TimedSchedule.EndOverride), [InvalidDuration, TooManyOverrides, ConflictingDuration(LocalDateTime), ..])
normalize_overrides = |inputs| {
	if inputs.len() > 4096 {
		return Err(TooManyOverrides)
	}
	match normalize_endings(inputs.map(|input| { source: input.source, ending: After(input.duration) })) {
		Ok(value) => Ok(value)
		Err(InvalidDuration) => Err(InvalidDuration)
		Err(TooManyOverrides) => Err(TooManyOverrides)
		Err(ConflictingEnding(source)) => Err(ConflictingDuration(source))
	}
}

normalize_endings : List(TimedSchedule.EndOverride) -> Try(List(TimedSchedule.EndOverride), [InvalidDuration, TooManyOverrides, ConflictingEnding(LocalDateTime), ..])
normalize_endings = |inputs| {
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
		|a, b| match LocalDateTime.compare_position(a.source, b.source) {
			LT => Before
			EQ => Same
			GT => After
		},
	)
	var $result = []
	var $previous = None
	for input in sorted {
		distinct = match $previous {
			None => Bool.True
			Some(value) => if LocalDateTime.same_position(value.source, input.source) {
				if !same_ending_definition(value.ending, input.ending) {
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

ending_at : List(TimedSchedule.EndOverride), LocalDateTime, TimedOccurrence.Duration -> TimedOccurrence.Ending
ending_at = |overrides, source, fallback| {
	var $lower = 0.U64
	var $upper = overrides.len()
	while $lower < $upper {
		middle = $lower + U64.div_trunc_by($upper - $lower, 2)
		entry = match overrides.get(middle) {
			Ok(value) => value
			Err(_) => crash "override binary search invariant"
		}
		match LocalDateTime.compare_position(entry.source, source) {
			EQ => return entry.ending
			LT => {
				$lower = middle + 1
			}
			GT => {
				$upper = middle
			}
		}
	}
	After(fallback)
}

same_ending_definition : TimedOccurrence.Ending, TimedOccurrence.Ending -> Bool
same_ending_definition = |a, b| match (a, b) {
	(After(left), After(right)) => same_duration_definition(left, right)
	(AtBoundary(left), AtBoundary(right)) => left == right
	(AtLocal(left), AtLocal(right)) => left.source == right.source and left.occurrence == right.occurrence and left.gap == right.gap
	_ => Bool.False
}

# Compare input meaning, not the extent of a particular resolved occurrence.
same_duration_definition : TimedOccurrence.Duration, TimedOccurrence.Duration -> Bool
same_duration_definition = |left, right| match (left, right) {
	(Coordinate(a), Coordinate(b)) => PosixDelta.to_microseconds(a) == PosixDelta.to_microseconds(b)
	(Calendar(a), Calendar(b)) => {
		x = CalendarDelta.to_components(a.delta)
		y = CalendarDelta.to_components(b.delta)
		x.years == y.years and x.months == y.months and x.days == y.days and a.invalid_date == b.invalid_date and a.tail == b.tail and a.occurrence == b.occurrence and a.gap == b.gap
	}
	_ => Bool.False
}

test_override_sources = |_| {
	clock = ClockTime.from_microseconds_since_midnight(0)?
	var $sources = []
	for day in [1.U8, 2, 3, 4] {
		date = GregorianDate.from_fields({ year: 1970, month: 1, day })?
		$sources = $sources.append(LocalDateTime.new(CalendarDate.from_gregorian(date), clock))
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
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-1), PosixBoundary.from_microseconds(518400000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	calendar : TimedOccurrence.Duration
	calendar = Calendar({ delta: CalendarDelta.days(2), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
	short : TimedOccurrence.Duration
	short = Coordinate(PosixDelta.from_microseconds(7200000000))
	var $cursor = TimedSchedule.new_with_overrides(42.U64, rule, { start: sources.get(window_day - 1)?, end: sources.get(3)? }, Coordinate(PosixDelta.from_microseconds(86400000000)), [{ source: sources.get(2)?, duration: calendar }, { source: sources.get(1)?, duration: short }, { source: sources.get(1)?, duration: short }], { rules, occurrence: RequireUnique, gap: RejectGap })?
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
	calendar = Calendar({ delta: CalendarDelta.days(1), invalid_date: Reject, tail: PosixDelta.from_microseconds(0), occurrence: RequireUnique, gap: RejectGap })
	match normalize_overrides([{ source, duration: one }, { source, duration: calendar }]) {
		Err(ConflictingDuration(value)) => value == source
		_ => Bool.False
	}
}

expect {
	source = test_override_sources({})?.get(0)?
	match normalize_overrides([{ source, duration: Coordinate(PosixDelta.from_microseconds(0)) }]) {
		Err(InvalidDuration) => Bool.True
		_ => Bool.False
	}
}

expect {
	source = test_override_sources({})?.get(0)?
	entry : TimedSchedule.Override
	entry = { source, duration: Coordinate(PosixDelta.from_microseconds(1)) }
	match normalize_overrides(List.repeat(entry, 4097)) {
		Err(TooManyOverrides) => Bool.True
		_ => Bool.False
	}
}

# Gap adjustment can map two sources to one boundary. Duration overrides
# follow the original source identity, never the coincident timeline position.
expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_fields({ hour: 2, minute: 30, second: 0, microsecond: 0 })?
	source = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(date), ClockTime.from_fields({ hour: 4, minute: 0, second: 0, microsecond: 0 })?)
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [2, 3], minutes: [], seconds: [] }, termination: Count(2), by_set_pos: [] })?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(172800000000))?
	rules = ZoneRules.new_bounded("Synthetic/Gap", "v1", validity, FixedOffset.from_seconds(0), [{ at: PosixBoundary.from_microseconds(7200000000), offset: FixedOffset.from_seconds(3600) }], { minimum: 0, maximum: 3600 })?
	initial = TimedSchedule.new_with_overrides(42.U64, rule, { start: source, end }, Coordinate(PosixDelta.from_microseconds(3600000000)), [{ source, duration: Coordinate(PosixDelta.from_microseconds(7200000000)) }], { rules, occurrence: First, gap: UseOffsetBeforeGap })?
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
	conflict = match normalize_endings([{ source, ending: AtBoundary(boundary) }, { source, ending: After(Coordinate(PosixDelta.from_microseconds(86400000000))) }]) {
		Err(ConflictingEnding(position)) => position == source
		_ => Bool.False
	}
	invalid = match normalize_endings([{ source, ending: After(Coordinate(PosixDelta.from_microseconds(0))) }]) {
		Err(InvalidDuration) => Bool.True
		_ => Bool.False
	}
	entry = { source, ending: AtBoundary(boundary) }
	too_many = match normalize_endings(List.repeat(entry, 4097)) {
		Err(TooManyOverrides) => Bool.True
		_ => Bool.False
	}
	conflict and invalid and too_many and normalize_endings([entry, entry])?.len() == 1
}
