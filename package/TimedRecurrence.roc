import CalendarDate
import CalendarPattern
import CivilDay
import ClockPattern
import ClockTime
import GregorianDate
import LocalDateTime
import PosixBoundary
import PosixSpan
import FixedOffset
import ZoneRules

## Native Gregorian timed series, in source-label order. Distinct source labels
## retain their identity even if gap adjustment maps them to one boundary.
## Windows select source labels, not timeline overlaps. This is not an RRULE parser.
## COUNT includes chosen source occurrences before the query window; UNTIL is
## inclusive in local position. Daily through yearly periods use Gregorian
## selectors; subdaily frequencies, exceptions and durations are not exposed.
## Clock candidates are ordered by source label. BYSETPOS indexes that full
## period after explicit interpretation, without deduplicating equal boundaries.
## Construction retains at most 4096 positions and bounded field selectors.
## Cursor work follows examined days/clocks and separately budgeted zone
## segments. Position selection scans at most 4096 supplied positions per item.
## Without positions, buffering holds one occurrence. With positions it holds
## the whole interpreted period, subject to max_buffered. Retained cursors can
## share buffers; resuming a shared buffer can copy it on append.
TimedRecurrence :: { anchor : LocalDateTime, calendar : CalendarPattern, clocks : ClockPattern, termination : Termination, positions : List(I16) }.{
	Termination : [Forever, Count(U64), Until(LocalDateTime)]
	Spec : { calendar : CalendarPattern.Spec, clocks : ClockPattern.Spec, termination : Termination, by_set_pos : List(I16) }
	new : { date : GregorianDate, clock : ClockTime }, Spec -> Try(TimedRecurrence, [InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), OutOfRange, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidCount, InvalidUntil, InvalidSetPosition, UnsynchronizedStart, ..])
	new = |start, spec| {
		anchor = LocalDateTime.new(CalendarDate.from_gregorian(start.date), start.clock)
		match spec.termination {
			Count(0) => return Err(InvalidCount)
			Until(end) => if before(end, anchor) {
				return Err(InvalidUntil)
			}
			_ => {}
		}
		if spec.by_set_pos.len() > 4096 {
			return Err(TooManySelectors)
		}
		for position in spec.by_set_pos {
			if position == 0 or position < -366 or position > 366 {
				return Err(InvalidSetPosition)
			}
		}
		calendar = CalendarPattern.new(start.date, spec.calendar)?
		clocks = ClockPattern.new(start.clock, spec.clocks)?
		if !CalendarPattern.matches(calendar, 0, start.date)? or !clock_matches(clocks, start.clock) {
			return Err(UnsynchronizedStart)
		}
		Ok({ anchor, calendar, clocks, termination: spec.termination, positions: spec.by_set_pos })
	}
	Window : { start : LocalDateTime, end : LocalDateTime }
	Context : { rules : ZoneRules, occurrence : ZoneRules.OccurrencePolicy, gap : [RejectGap, UseOffsetBeforeGap] }
	Limits : { max_steps : U64, max_buffered : U64, max_zone_segments : U64, max_zone_candidates : U64 }
	Limit : [WorkLimit, BufferLimit, ZoneWorkLimit, ZoneBufferLimit]
	Occurrence :: { source : LocalDateTime, choice : ZoneRules.BoundaryChoice, rules : ZoneRules }.{
		source : Occurrence -> LocalDateTime
		source = |value| value.source
		boundary : Occurrence -> PosixBoundary
		boundary = |value| value.choice.boundary
		adjustment : Occurrence -> [Exact, BeforeGap(ZoneRules.GapTransition)]
		adjustment = |value| value.choice.adjustment
		rules : Occurrence -> ZoneRules
		rules = |value| value.rules
		to_inspect : Occurrence -> Str
		to_inspect = |value| "TimedRecurrence.Occurrence(${Str.inspect(value.source)}, ${Str.inspect(value.choice.boundary)})"
	}
	Next : { steps : U64, zone_segments : U64, buffered : U64, zone_buffered : U64, status : [End, Item({ occurrence : Occurrence, cursor : Cursor }), Limited({ cursor : Cursor, reason : Limit })] }
	cursor : TimedRecurrence, Window, Context -> Try(Cursor, [EmptyWindow, ReversedWindow, OutOfRange, ..])
	cursor = |rule, window, context| {
		match LocalDateTime.compare_position(window.start, window.end) {
			EQ => return Err(EmptyWindow)
			GT => return Err(ReversedWindow)
			LT => {}
		}
		frame = CalendarPattern.period(rule.calendar, 0)?
		Ok({ rule, window, context, period: 0, day: day_number(frame.start), end_day: day_number(frame.end), day_selected: Unknown, clock_index: 0, buffer: [], phase: Build, pending: None, anchor_index: None, count: 0, zone_buffered: 0 })
	}
	Cursor :: {
		rule : TimedRecurrence,
		window : Window,
		context : Context,
		period : U64,
		day : I64,
		end_day : I64,
		day_selected : [Unknown, Yes, No],
		clock_index : U64,
		buffer : List(Occurrence),
		phase : [Build, Emit({ index : U64, advance : Bool }), Advance],
		pending : [None, Some({ source : LocalDateTime, cursor : ZoneRules.ClassificationCursor })],
		anchor_index : [None, Some(U64)],
		count : U64,
		zone_buffered : U64,
	}.{

		## Work counts date tests, clock candidates, period boundaries and
		## emitted/filtered candidates. Zone work has a separate total budget.
		## BYSETPOS buffers the whole period and validates DTSTART's position
		## before any first-period output. Without BYSETPOS, only one pending
		## occurrence is retained. Caller-retained cursors may share buffers.
		next : Cursor, Limits -> Try(Next, [OutOfRange, OutsideValidity, Gap, Ambiguous, AmbiguousGap, OffsetConflict, UnsynchronizedStart, ..])
		next = |initial, limits| {
			var state = initial
			var steps = 0.U64
			var zone_segments = 0.U64
			while True {
				if buffered_count(state) > limits.max_buffered {
					return Ok(limited(state, steps, zone_segments, BufferLimit))
				}
				match state.rule.termination {
					Count(maximum) => if state.count == maximum {
						return Ok(ended(state, steps, zone_segments))
					}
					_ => {}
				}
				match state.pending {
					Some(pending) => {
						batch = ZoneRules.ClassificationCursor.collect(pending.cursor, { max_segments: limits.max_zone_segments - zone_segments, max_candidates: limits.max_zone_candidates })?
						zone_segments = zone_segments + batch.segments
						state = { ..state, zone_buffered: batch.buffered }
						match batch.status {
							Limited(progress) => {
								reason = match progress.reason {
									WorkLimit => ZoneWorkLimit
									BufferLimit => ZoneBufferLimit
								}
								return Ok(limited({ ..state, pending: Some({ ..pending, cursor: progress.cursor }) }, steps, zone_segments, reason))
							}
							Complete(classification) => {
								choice = ZoneRules.Classification.choose(classification, { occurrence: state.context.occurrence, gap: state.context.gap })?
								occurrence : Occurrence
								occurrence = { source: pending.source, choice, rules: state.context.rules }
								anchor_index = if pending.source == state.rule.anchor {
									Some(state.buffer.len())
								} else {
									state.anchor_index
								}
								phase = if state.rule.positions.is_empty() {
									Emit({ index: 0, advance: Bool.False })
								} else {
									Build
								}
								state = { ..state, buffer: state.buffer.append(occurrence), anchor_index, pending: None, zone_buffered: 0, phase }
							}
						}
					}
					None => {}
				}
				if steps == limits.max_steps {
					return Ok(limited(state, steps, zone_segments, WorkLimit))
				}
				steps = steps + 1
				match state.phase {
					Emit(emission) => {
						if emission.index == state.buffer.len() {
							state = {
								..state,
								buffer: [],
								phase: if emission.advance {
									Advance
								} else {
									Build
								},
							}
						} else {
							occurrence = buffer_at(state.buffer, emission.index)
							state = { ..state, phase: Emit({ ..emission, index: emission.index + 1 }) }
							if selected(state.rule.positions, emission.index, state.buffer.len()) and !before(occurrence.source, state.rule.anchor) {
								match state.rule.termination {
									Until(end) => if before(end, occurrence.source) {
										return Ok(ended(state, steps, zone_segments))
									}
									_ => {}
								}
								if !before(occurrence.source, state.window.end) {
									return Ok(ended(state, steps, zone_segments))
								}
								state = { ..state, count: state.count + 1 }
								if !before(occurrence.source, state.window.start) {
									return Ok({ steps, zone_segments, buffered: buffered_count(state), zone_buffered: state.zone_buffered, status: Item({ occurrence, cursor: state }) })
								}
							}
						}
					}
					Advance => {
						boundary = local_at(state.end_day, midnight({}))?
						if !before(boundary, state.window.end) {
							return Ok(ended(state, steps, zone_segments))
						}
						match state.rule.termination {
							Until(end) => if before(end, boundary) {
								return Ok(ended(state, steps, zone_segments))
							}
							_ => {}
						}
						frame = CalendarPattern.period(state.rule.calendar, state.period + 1)?
						state = { ..state, period: state.period + 1, day: day_number(frame.start), end_day: day_number(frame.end), day_selected: Unknown, clock_index: 0, phase: Build, anchor_index: None }
					}
					Build => {
						if state.day == state.end_day {
							if !state.rule.positions.is_empty() and state.period == 0 {
								match state.anchor_index {
									Some(index) => if !selected(state.rule.positions, index, state.buffer.len()) {
										return Err(UnsynchronizedStart)
									}
									None => return Err(UnsynchronizedStart)
								}
							}
							state = { ..state, phase: Emit({ index: 0, advance: Bool.True }) }
						} else {
							match state.day_selected {
								Unknown => {
									date = GregorianDate.from_civil_day(CivilDay.from_day_number(state.day))?
									matches = CalendarPattern.matches(state.rule.calendar, state.period, date)?
									state = {
										..state,
										day_selected: if matches {
											Yes
										} else {
											No
										},
									}
								}
								No => {
									state = next_day(state)
								}
								Yes => {
									if state.clock_index == ClockPattern.count(state.rule.clocks) {
										state = next_day(state)
									}
										else {
											source = local_at(state.day, clock_at(state.rule.clocks, state.clock_index))?
											if state.rule.positions.is_empty() {
												if !before(source, state.window.end) {
													return Ok(ended(state, steps, zone_segments))
												}
												match state.rule.termination {
													Until(end) => if before(end, source) {
														return Ok(ended(state, steps, zone_segments))
													}
													_ => {}
												}
											}
											if state.rule.positions.is_empty() and before(source, state.rule.anchor) {
												state = { ..state, clock_index: state.clock_index + 1 }
											}
												else {
													if state.buffer.len() == limits.max_buffered {
														return Ok(limited(state, steps, zone_segments, BufferLimit))
													}
													pending = ZoneRules.classification_cursor(state.context.rules, source)?
													state = { ..state, clock_index: state.clock_index + 1, pending: Some({ source, cursor: pending }) }
												}
										}
								}
							}
						}
					}
				}
			}
			crash "Timed recurrence loop returns an outcome"
		}
		to_inspect : Cursor -> Str
		to_inspect = |state| "TimedRecurrence.Cursor(period=${state.period.to_str()}, count=${state.count.to_str()}, buffered=${buffered_count(state).to_str()})"
	}
}

before = |a, b| LocalDateTime.compare_position(a, b) == LT

midnight = |_| clock_from_number(0)

clock_from_number = |number| match ClockTime.from_microseconds_since_midnight(number) {
	Ok(value) => value
	Err(_) => crash "clock invariant"
}

day_number = |date| CivilDay.to_day_number(GregorianDate.to_civil_day(date))

local_at = |day, clock| {
	date = GregorianDate.from_civil_day(CivilDay.from_day_number(day))?
	Ok(LocalDateTime.new(CalendarDate.from_gregorian(date), clock))
}

clock_at = |pattern, index| match ClockPattern.at(pattern, index) {
	Ok(value) => value
	Err(_) => crash "Clock candidate index invariant"
}

clock_matches = |pattern, clock| {
	var lower = 0.U64
	var upper = ClockPattern.count(pattern)
	while lower < upper {
		middle = lower + U64.div_trunc_by(upper - lower, 2)
		if clock_at(pattern, middle) < clock {
			lower = middle + 1
		} else {
			upper = middle
		}
	}
	lower < ClockPattern.count(pattern) and clock_at(pattern, lower) == clock
}

selected : List(I16), U64, U64 -> Bool
selected = |positions, index, count| {
	if positions.is_empty() {
		return Bool.True
	}
	var matches = Bool.False
	for position in positions {
		matches = matches or if position > 0 {
			index + 1 == position.to_u64_wrap()
		} else {
			count - index == (-position).to_u64_wrap()
		}
	}
	matches
}

buffer_at = |buffer, index| match List.get(buffer, index) {
	Ok(value) => value
	Err(_) => crash "Timed buffer index invariant"
}

buffered_count = |state| state.buffer.len() + match state.pending {
	None => 0
	Some(_) => 1
}

limited = |state, steps, zone_segments, reason| { steps, zone_segments, buffered: buffered_count(state), zone_buffered: state.zone_buffered, status: Limited({ cursor: state, reason }) }

ended = |state, steps, zone_segments| { steps, zone_segments, buffered: buffered_count(state), zone_buffered: state.zone_buffered, status: End }

next_day = |state| { ..state, day: state.day + 1, day_selected: Unknown, clock_index: 0 }

# The second clock is exactly outside provider validity. Neither a half-open
# query nor inclusive UNTIL should require interpreting that unused label.
test_stopping_boundary = |termination, end_microseconds| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(date), ClockTime.from_microseconds_since_midnight(end_microseconds)?)
	rule = TimedRecurrence.new(
		{ date, clock },
		{
			calendar: CalendarPattern.defaults(Daily),
			clocks: { hours: [0, 1], minutes: [], seconds: [] },
			termination,
			by_set_pos: [],
		},
	)?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-1), PosixBoundary.from_microseconds(3600000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	initial = TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: RequireUnique, gap: RejectGap })?
	var cursor = initial
	var values = []
	var complete = Bool.False
	var valid = Bool.True
	var calls = 0.U64
	while calls < 40 and !complete {
		batch = TimedRecurrence.Cursor.next(cursor, { max_steps: 1, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 1 })?
		valid = valid and batch.steps <= 1 and batch.zone_segments <= 1
		match batch.status {
			End => {
				complete = Bool.True
			}
			Limited(progress) => {
				cursor = progress.cursor
			}
			Item(item) => {
				values = values.append(TimedRecurrence.Occurrence.boundary(item.occurrence))
				cursor = item.cursor
			}
		}
		calls = calls + 1
	}
	Ok(valid and complete and values == [PosixBoundary.from_microseconds(0)])
}

expect test_stopping_boundary(Forever, 3600000000) == Ok(True)

expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	test_stopping_boundary(Until(LocalDateTime.new(CalendarDate.from_gregorian(date), clock)), 7200000000)?
}

# A one-hour forward jump maps 01:00 (using the pre-gap offset) and
# 02:00 (exact) to the same boundary. Both source appointments count.
test_gap_series = |positions, budget| test_series(positions, budget, 3600, First)

test_series = |positions, budget, offset, policy| test_series_with_pauses(positions, budget, offset, policy, [])

test_series_with_pauses = |positions, budget, offset, policy, pauses| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 2 })?), clock)
	rule = TimedRecurrence.new(
		{ date, clock },
		{
			calendar: CalendarPattern.defaults(Daily),
			clocks: { hours: [0, 1, 2], minutes: [], seconds: [] },
			termination: Count(3),
			by_set_pos: positions,
		},
	)?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(172800000000))?
	rules = ZoneRules.new_bounded(
		"Synthetic/Forward",
		"v1",
		validity,
		FixedOffset.from_seconds(0),
		[{ at: PosixBoundary.from_microseconds(3600000000), offset: FixedOffset.from_seconds(offset) }],
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
	)?
	var cursor = TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: policy, gap: UseOffsetBeforeGap })?
	var boundaries = []
	var sources = []
	var adjusted = []
	var complete = Bool.False
	var valid = Bool.True
	var calls = 0.U64
	while calls < 100 and !complete {
		effective = List.get(pauses, calls) ?? budget
		batch = TimedRecurrence.Cursor.next(cursor, effective)?
		valid = valid and batch.steps <= effective.max_steps and batch.zone_segments <= effective.max_zone_segments
		match batch.status {
			End => {
				complete = Bool.True
			}
			Limited(progress) => {
				cursor = progress.cursor
			}
			Item(item) => {
				boundaries = boundaries.append(TimedRecurrence.Occurrence.boundary(item.occurrence))
				sources = sources.append(TimedRecurrence.Occurrence.source(item.occurrence))
				adjusted = adjusted.append(
					match TimedRecurrence.Occurrence.adjustment(item.occurrence) {
						Exact => Bool.False
						BeforeGap(_) => Bool.True
					},
				)
				cursor = item.cursor
			}
		}
		calls = calls + 1
	}
	Ok({ valid: valid and complete, boundaries, sources, adjusted })
}

expect {
	resumed = test_gap_series([], { max_steps: 1, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 2 })?
	uninterrupted = test_gap_series([], { max_steps: 100, max_buffered: 1, max_zone_segments: 100, max_zone_candidates: 2 })?
	resumed == uninterrupted and resumed.valid and resumed.boundaries == [PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(3600000000), PosixBoundary.from_microseconds(3600000000)] and resumed.adjusted == [False, True, False] and resumed.sources.len() == 3
}

expect selected([1, -1], 2, 3)

expect {
	result = test_gap_series([1, -1], { max_steps: 100, max_buffered: 3, max_zone_segments: 100, max_zone_candidates: 2 })?
	result.valid
}

expect {
	result = test_gap_series([1, -1], { max_steps: 1, max_buffered: 3, max_zone_segments: 1, max_zone_candidates: 2 })?
	result.valid and result.boundaries == [PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(3600000000)] and result.adjusted == [False, False]
}

expect {
	resumed = test_gap_series([1, -1], { max_steps: 1, max_buffered: 3, max_zone_segments: 1, max_zone_candidates: 2 })?
	uninterrupted = test_gap_series([1, -1], { max_steps: 100, max_buffered: 3, max_zone_segments: 100, max_zone_candidates: 2 })?
	resumed.boundaries == uninterrupted.boundaries and resumed.adjusted == uninterrupted.adjusted and resumed.sources == uninterrupted.sources and resumed.valid and uninterrupted.valid
}

expect {
	result = test_gap_series([2], { max_steps: 100, max_buffered: 3, max_zone_segments: 100, max_zone_candidates: 2 })
	match result {
		Err(UnsynchronizedStart) => Bool.True
		_ => Bool.False
	}
}

expect {
	result = test_series([], { max_steps: 1, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 2 }, -3600, Last)?
	result.valid and result.boundaries == [PosixBoundary.from_microseconds(3600000000), PosixBoundary.from_microseconds(7200000000), PosixBoundary.from_microseconds(10800000000)] and result.adjusted == [False, False, False]
}

expect {
	result = test_series([], { max_steps: 100, max_buffered: 1, max_zone_segments: 100, max_zone_candidates: 2 }, -3600, RequireUnique)
	match result {
		Err(Ambiguous) => Bool.True
		_ => Bool.False
	}
}

# Stop before work, before buffering, before zone work, at the zone buffer,
# and after retaining a first occurrence. Lowering the buffer limit must retain
# the saved cursor, so increasing it later completes the original period.
expect {
	budget = { max_steps: 100.U64, max_buffered: 3.U64, max_zone_segments: 100.U64, max_zone_candidates: 2.U64 }
	pauses = [
		{ ..budget, max_steps: 0 },
		{ ..budget, max_buffered: 0 },
		{ ..budget, max_zone_segments: 0 },
		{ ..budget, max_zone_candidates: 0 },
		{ ..budget, max_buffered: 1 },
		{ ..budget, max_buffered: 0 },
	]
	result = test_series_with_pauses([1, -1], budget, 3600, First, pauses)?
	expected = test_gap_series([1, -1], budget)?
	result.valid and expected.valid and result.sources == expected.sources and result.boundaries == expected.boundaries and result.adjusted == expected.adjusted
}
