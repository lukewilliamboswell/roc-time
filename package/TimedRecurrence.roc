import CalendarDate
import CalendarPattern
import SubdailyPattern
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
## selectors via new; new_subdaily supplies hourly, minutely or secondly
## periods. Source exclusions are applied after interpretation and COUNT;
## they do not bypass gap/fold validation. Inclusions do not consume COUNT and merge by source position; durations
## are supplied by TimedSchedule.
## Clock candidates are ordered by source label. BYSETPOS indexes that full
## period after explicit interpretation, without deduplicating equal boundaries.
## Construction retains at most 4096 positions and bounded field selectors.
## Cursor work follows examined days/clocks and separately budgeted zone
## segments. Position selection scans at most 4096 supplied positions per item.
## Without positions, buffering holds one occurrence. With positions it holds
## the whole interpreted period, subject to max_buffered. Retained cursors can
## share buffers; resuming a shared buffer can copy it on append.
TimedRecurrence :: { anchor : LocalDateTime, schedule : [Calendar(CalendarPattern), Subdaily(SubdailyPattern)], clocks : ClockPattern, termination : Termination, positions : List(I16), exclusions : List(LocalDateTime), inclusions : List(LocalDateTime) }.{

	## Until is inclusive in source-label order. UntilBoundary is inclusive
	## on the POSIX axis after full-period BYSETPOS selection. Explicit inclusions
	## remain outside rule termination. A boundary before all starts yields no
	## rule occurrences; it cannot be compared to the unresolved anchor at new.
	Termination : [Forever, Count(U64), Until(LocalDateTime), UntilBoundary(PosixBoundary)]
	Spec : { calendar : CalendarPattern.Spec, clocks : ClockPattern.Spec, termination : Termination, by_set_pos : List(I16) }
	new : { date : GregorianDate, clock : ClockTime }, Spec -> Try(TimedRecurrence, [InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), OutOfRange, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidCount, InvalidUntil, InvalidSetPosition, UnsynchronizedStart, ..])
	new = |start, spec| {
		anchor = LocalDateTime.new(CalendarDate.from_gregorian(start.date), start.clock)
		validate_options(anchor, spec.termination, spec.by_set_pos)?
		calendar = CalendarPattern.new(start.date, spec.calendar)?
		clocks = ClockPattern.new(start.clock, spec.clocks)?
		if !CalendarPattern.matches(calendar, 0, start.date)? or !clock_matches(clocks, start.clock) {
			return Err(UnsynchronizedStart)
		}
		Ok({ anchor, schedule: Calendar(calendar), clocks, termination: spec.termination, positions: spec.by_set_pos, exclusions: [], inclusions: [] })
	}
	SubdailySpec : { pattern : SubdailyPattern.Spec, termination : Termination, by_set_pos : List(I16) }
	new_subdaily : { date : GregorianDate, clock : ClockTime }, SubdailySpec -> Try(TimedRecurrence, [InvalidInterval, TooManySelectors, InvalidSelector(Str), InvalidCombination(Str), OutOfRange, InvalidHour, InvalidMinute, InvalidSecond, UnsupportedLeapSecond, InvalidCount, InvalidUntil, InvalidSetPosition, UnsynchronizedStart, ..])
	new_subdaily = |start, spec| {
		anchor = LocalDateTime.new(CalendarDate.from_gregorian(start.date), start.clock)
		validate_options(anchor, spec.termination, spec.by_set_pos)?
		pattern = SubdailyPattern.new(start, spec.pattern)?
		_ = SubdailyPattern.period(pattern, 0)?
		clocks = SubdailyPattern.clocks(pattern)
		if !SubdailyPattern.matches_date(pattern, start.date)? or !clock_matches(clocks, start.clock) {
			return Err(UnsynchronizedStart)
		}
		Ok({ anchor, schedule: Subdaily(pattern), clocks, termination: spec.termination, positions: spec.by_set_pos, exclusions: [], inclusions: [] })
	}

	## Replace the source-position exclusion set; an empty list clears it.
	## Equal local positions match across supported calendar descriptions.
	## Do not confuse source equality with equal resolved boundaries in a gap.
	## At most 4096 inputs; O(n log n) normalization, O(log n) membership.
	## Existing cursors retain their original immutable rule and exclusion set.
	with_exclusions : TimedRecurrence, List(LocalDateTime) -> Try(TimedRecurrence, [TooManySelectors, ..])
	with_exclusions = |rule, labels| {
		if labels.len() > 4096 {
			return Err(TooManySelectors)
		}
		exclusions = sorted_positions(labels)
		Ok({ ..rule, exclusions })
	}

	## Replace at most 4096 explicit Gregorian starts, normalized by position.
	## They may precede the anchor or follow COUNT/UNTIL; the query still applies.
	## Duplicate starts merge with the rule, and exclusions win over both.
	## Existing cursors retain their input set. Construction is O(n log n).
	with_inclusions : TimedRecurrence, List({ date : GregorianDate, clock : ClockTime }) -> Try(TimedRecurrence, [TooManySelectors, ..])
	with_inclusions = |rule, starts| {
		if starts.len() > 4096 {
			return Err(TooManySelectors)
		}
		labels = starts.map(|start| LocalDateTime.new(CalendarDate.from_gregorian(start.date), start.clock))
		Ok({ ..rule, inclusions: sorted_positions(labels) })
	}

	## Add explicit starts while retaining existing inclusions and exclusions.
	## Existing normalized entries plus supplied inputs must total at most 4096
	## before deduplication. Construction sorts the combined bounded collection.
	add_inclusions : TimedRecurrence, List({ date : GregorianDate, clock : ClockTime }) -> Try(TimedRecurrence, [TooManySelectors, ..])
	add_inclusions = |rule, starts| {
		if starts.len() > 4096 - rule.inclusions.len() {
			return Err(TooManySelectors)
		}
		labels = starts.map(|start| LocalDateTime.new(CalendarDate.from_gregorian(start.date), start.clock))
		Ok({ ..rule, inclusions: sorted_positions(rule.inclusions.concat(labels)) })
	}

	Window : { start : LocalDateTime, end : LocalDateTime }
	Context : { rules : ZoneRules, occurrence : ZoneRules.OccurrencePolicy, gap : [RejectGap, UseOffsetBeforeGap] }
	Limits : { max_steps : U64, max_buffered : U64, max_zone_segments : U64, max_zone_candidates : U64 }
	Limit : [WorkLimit, BufferLimit, ZoneWorkLimit, ZoneBufferLimit, OutputLimit]
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
	CollectLimits : { work : Limits, max_occurrences : U64 }
	Batch : { occurrences : List(Occurrence), steps : U64, zone_segments : U64, buffered : U64, zone_buffered : U64, status : [Complete, Limited({ cursor : Cursor, reason : Limit })] }
	cursor : TimedRecurrence, Window, Context -> Try(Cursor, [EmptyWindow, ReversedWindow, OutOfRange, ..])
	cursor = |rule, window, context| {
		match LocalDateTime.compare_position(window.start, window.end) {
			EQ => return Err(EmptyWindow)
			GT => return Err(ReversedWindow)
			LT => {}
		}
		# L resolves using an offset no greater than maximum. Consequently,
		# L > cutoff + maximum cannot produce an in-limit boundary, including
		# before-gap adjustment. Keep the cutoff for individual result filtering;
		# the local envelope alone must not replace its meaning.
		(effective_rule, boundary_cutoff) = match rule.termination {
			UntilBoundary(boundary) => {
				maximum = ZoneRules.offset_bounds(context.rules).maximum
				last_source = FixedOffset.project(FixedOffset.from_seconds(maximum), boundary, Gregorian)?
				({ ..rule, termination: Until(last_source) }, Some(boundary))
			}
			_ => (rule, None)
		}
		frame = timed_frame(effective_rule, 0)?
		Ok({ rule: effective_rule, boundary_cutoff, window, context, period: 0, day: frame.start_day, end_day: frame.end_day, period_end: frame.end, day_selected: Unknown, clock_index: frame.clock_start, clock_start: frame.clock_start, clock_end: frame.clock_end, buffer: [], phase: Build, pending: None, anchor_index: None, count: 0, zone_buffered: 0, inclusion_index: 0, held: None, rule_ended: Bool.False, inclusion_pending: None })
	}
	Cursor :: {
		rule : TimedRecurrence,
		boundary_cutoff : [None, Some(PosixBoundary)],
		window : Window,
		context : Context,
		period : U64,
		day : I64,
		end_day : I64,
		day_selected : [Unknown, Yes, No],
		clock_index : U64,
		clock_start : U64,
		clock_end : U64,
		period_end : LocalDateTime,
		buffer : List(Occurrence),
		phase : [Build, Emit({ index : U64, advance : Bool }), Advance],
		pending : [None, Some({ source : LocalDateTime, cursor : ZoneRules.ClassificationCursor })],
		anchor_index : [None, Some(U64)],
		count : U64,
		zone_buffered : U64,
		inclusion_index : U64,
		# Keep optional merge payloads out of every cursor copy. Boxes are
		# allocated only when inclusions require lookahead or interpretation.
		held : [None, Some(Box(Occurrence))],
		rule_ended : Bool,
		inclusion_pending : [None, Some(Box({ source : LocalDateTime, cursor : ZoneRules.ClassificationCursor }))],
	}.{

		## Work counts date tests, clock candidates, period boundaries and
		## emitted/filtered candidates. Zone work has a separate total budget.
		## BYSETPOS buffers the whole period and validates DTSTART's position
		## before any first-period output. Without BYSETPOS, only one pending
		## occurrence is retained. Caller-retained cursors may share buffers.
		## Merge explicit starts after rule selection/COUNT, retaining at most
		## one rule lookahead and one pending inclusion classification. Looking
		## ahead may examine a full BYSETPOS period under the same budgets.
		next : Cursor, Limits -> Try(Next, [OutOfRange, OutsideValidity, Gap, Ambiguous, AmbiguousGap, OffsetConflict, UnsynchronizedStart, ..])
		next = |initial, limits| {
			if initial.rule.inclusions.is_empty() {
				return next_rule(initial, limits)
			}
			var state = initial
			var steps = 0.U64
			var zone_segments = 0.U64
			while True {
				if buffered_count(state) > limits.max_buffered {
					return Ok(limited(state, steps, zone_segments, BufferLimit))
				}
				match state.inclusion_pending {
					Some(boxed) => {
						pending = Box.unbox(boxed)
						batch = ZoneRules.ClassificationCursor.collect(pending.cursor, { max_segments: limits.max_zone_segments - zone_segments, max_candidates: limits.max_zone_candidates })?
						zone_segments = zone_segments + batch.segments
						state = { ..state, zone_buffered: batch.buffered }
						match batch.status {
							Limited(progress) => return Ok(
								limited(
									{ ..state, inclusion_pending: Some(Box.box({ ..pending, cursor: progress.cursor })) },
									steps,
									zone_segments,
									match progress.reason {
										WorkLimit => ZoneWorkLimit
										BufferLimit => ZoneBufferLimit
									},
								),
							)
							Complete(classification) => {
								choice = ZoneRules.Classification.choose(classification, { occurrence: state.context.occurrence, gap: state.context.gap })?
								occurrence : Occurrence
								occurrence = { source: pending.source, choice, rules: state.context.rules }
								state = { ..state, inclusion_pending: None, inclusion_index: state.inclusion_index + 1, zone_buffered: 0 }
								if !excluded(state.rule.exclusions, pending.source) {
									return Ok({ steps, zone_segments, buffered: buffered_count(state), zone_buffered: 0, status: Item({ occurrence, cursor: state }) })
								}
							}
						}
					}
					None => {}
				}
				match state.held {
					None => if !state.rule_ended {
						batch = next_rule(state, { ..limits, max_steps: limits.max_steps - steps, max_zone_segments: limits.max_zone_segments - zone_segments })?
						steps = steps + batch.steps
						zone_segments = zone_segments + batch.zone_segments
						match batch.status {
							Limited(progress) => return Ok(limited(progress.cursor, steps, zone_segments, progress.reason))
							End => {
								state = { ..state, rule_ended: Bool.True, buffer: [], pending: None, zone_buffered: 0 }
							}
							Item(item) => {
								state = { ..item.cursor, held: Some(Box.box(item.occurrence)) }
							}
						}
					}
					Some(_) => {}
				}
				explicit = state.rule.inclusions.get(state.inclusion_index)
				match (state.held, explicit) {
					(None, Err(_)) => return Ok(ended(state, steps, zone_segments))
					(None, Ok(source)) => if !before(source, state.window.end) {
						return Ok(ended(state, steps, zone_segments))
					}
					_ => {}
				}
				if steps == limits.max_steps {
					return Ok(limited(state, steps, zone_segments, WorkLimit))
				}
				steps = steps + 1
				match state.held {
					Some(boxed) => {
						occurrence = Box.unbox(boxed)
						use_rule = match explicit {
							Err(_) => Bool.True
							Ok(source) => !before(source, occurrence.source)
						}
						if use_rule {
							index = match explicit {
								Ok(source) => if LocalDateTime.same_position(source, occurrence.source) {
									state.inclusion_index + 1
								} else {
									state.inclusion_index
								}
								Err(_) => state.inclusion_index
							}
							state = { ..state, held: None, inclusion_index: index }
							return Ok({ steps, zone_segments, buffered: buffered_count(state), zone_buffered: state.zone_buffered, status: Item({ occurrence, cursor: state }) })
						}
					}
					None => {}
				}
				source = match explicit {
					Ok(value) => value
					Err(_) => crash "merge has an inclusion"
				}
				if before(source, state.window.start) {
					state = { ..state, inclusion_index: state.inclusion_index + 1 }
				} else {
					if buffered_count(state) == limits.max_buffered {
						return Ok(limited(state, steps, zone_segments, BufferLimit))
					}
					pending = ZoneRules.classification_cursor(state.context.rules, source)?
					state = { ..state, inclusion_pending: Some(Box.box({ source, cursor: pending })) }
				}
			}
			crash "merge loop returns an outcome"
		}

		## Budgets apply to the entire batch, not separately to each output.
		## Output capacity is a separate bound from pending candidate buffers.
		## At capacity return Limited(OutputLimit) without looking ahead; even
		## an exactly full final batch needs resumption to prove completion.
		collect : Cursor, CollectLimits -> Try(Batch, [OutOfRange, OutsideValidity, Gap, Ambiguous, AmbiguousGap, OffsetConflict, UnsynchronizedStart, ..])
		collect = |initial, limits| {
			var current = initial
			var occurrences = []
			var steps = 0.U64
			var zone_segments = 0.U64
			while occurrences.len() < limits.max_occurrences {
				result = next(current, { ..limits.work, max_steps: limits.work.max_steps - steps, max_zone_segments: limits.work.max_zone_segments - zone_segments })?
				steps = steps + result.steps
				zone_segments = zone_segments + result.zone_segments
				match result.status {
					End => return Ok({ occurrences, steps, zone_segments, buffered: result.buffered, zone_buffered: result.zone_buffered, status: Complete })
					Limited(progress) => return Ok({ occurrences, steps, zone_segments, buffered: result.buffered, zone_buffered: result.zone_buffered, status: Limited(progress) })
					Item(item) => {
						occurrences = occurrences.append(item.occurrence)
						current = item.cursor
					}
				}
			}
			Ok({ occurrences, steps, zone_segments, buffered: buffered_count(current), zone_buffered: current.zone_buffered, status: Limited({ cursor: current, reason: OutputLimit }) })
		}

		## A lazy stream of next outcomes. Budgets apply per advancement.
		## End, errors and Limited are terminal items. Resume a Limited cursor
		## explicitly; iterating a zero-work stream cannot retry forever.
		outcomes : Cursor, Limits -> Iter(Try(Next, [OutOfRange, OutsideValidity, Gap, Ambiguous, AmbiguousGap, OffsetConflict, UnsynchronizedStart]))
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

buffered_count = |state| state.buffer.len() + (match state.pending {
	None => 0
	Some(_) => 1
}) + (match state.inclusion_pending {
	None => 0
	Some(_) => 1
}) + (
	if state.buffer.is_empty() {
		match state.held {
			None => 0
			Some(_) => 1
		}
	} else {
		0
	}
)

limited = |state, steps, zone_segments, reason| { steps, zone_segments, buffered: buffered_count(state), zone_buffered: state.zone_buffered, status: Limited({ cursor: state, reason }) }

ended = |state, steps, zone_segments| { steps, zone_segments, buffered: buffered_count(state), zone_buffered: state.zone_buffered, status: End }

next_day = |state| { ..state, day: state.day + 1, day_selected: Unknown, clock_index: state.clock_start }

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

test_series = |positions, budget, offset, policy| test_series_with_pauses(positions, budget, offset, policy, [], [])

test_series_with_pauses = |positions, budget, offset, policy, pauses, exclusions| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 2 })?), clock)
	base_rule = TimedRecurrence.new(
		{ date, clock },
		{
			calendar: CalendarPattern.defaults(Daily),
			clocks: { hours: [0, 1, 2], minutes: [], seconds: [] },
			termination: Count(3),
			by_set_pos: positions,
		},
	)?
	rule = TimedRecurrence.with_exclusions(base_rule, exclusions)?
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
	result = test_series_with_pauses([1, -1], budget, 3600, First, pauses, [])?
	expected = test_gap_series([1, -1], budget)?
	result.valid and expected.valid and result.sources == expected.sources and result.boundaries == expected.boundaries and result.adjusted == expected.adjusted
}

# A tiny explicit UTC grid isolates collection/output budgeting from date
# selection. Its expected boundaries are zero and one hour after the epoch.
test_stream_cursor = |count| test_stream_cursor_with_validity(count, 172800000000)

test_stream_cursor_with_validity = |count, validity_end| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 2 })?), clock)
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [0, 1, 2], minutes: [], seconds: [] }, termination: Count(count), by_set_pos: [] })?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(validity_end))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: RequireUnique, gap: RejectGap })
}

expect {
	initial = test_stream_cursor(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 100.U64, max_zone_candidates: 1.U64 }
	zero = TimedRecurrence.Cursor.collect(initial, { work, max_occurrences: 0 })?
	var valid = zero.steps == 0 and zero.zone_segments == 0 and zero.occurrences.is_empty()
	resume = match zero.status {
		Limited(progress) => {
			valid = valid and progress.reason == OutputLimit
			progress.cursor
		}
		Complete => crash "zero-output collection must not infer completion"
	}
	full = TimedRecurrence.Cursor.collect(resume, { work, max_occurrences: 2 })?
	boundaries = full.occurrences.map(TimedRecurrence.Occurrence.boundary)
	rest = match full.status {
		Limited(progress) => {
			valid = valid and progress.reason == OutputLimit
			progress.cursor
		}
		Complete => crash "exact capacity must not look ahead"
	}
	final = TimedRecurrence.Cursor.collect(rest, { work, max_occurrences: 2 })?
	valid and boundaries == [PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(3600000000)] and final.occurrences.is_empty() and match final.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}
}

expect {
	initial = test_stream_cursor(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 1.U64, max_zone_candidates: 1.U64 }
	first = TimedRecurrence.Cursor.collect(initial, { work, max_occurrences: 10 })?
	var valid = first.zone_segments == 1 and first.occurrences.map(TimedRecurrence.Occurrence.boundary) == [PosixBoundary.from_microseconds(0)]
	rest = match first.status {
		Limited(progress) => {
			valid = valid and progress.reason == ZoneWorkLimit
			progress.cursor
		}
		Complete => crash "zone work is shared by the entire batch"
	}
	second = TimedRecurrence.Cursor.collect(rest, { work, max_occurrences: 10 })?
	valid and second.zone_segments == 1 and second.occurrences.map(TimedRecurrence.Occurrence.boundary) == [PosixBoundary.from_microseconds(3600000000)] and match second.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}
}

expect {
	initial = test_stream_cursor(2)?
	work = { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 1.U64, max_zone_candidates: 1.U64 }
	var zero_count = 0.U64
	var valid = Bool.True
	for result in TimedRecurrence.Cursor.outcomes(initial, { ..work, max_steps: 0 }) {
		batch = result?
		zero_count = zero_count + 1
		valid = valid and batch.steps == 0 and match batch.status {
			Limited(progress) => progress.reason == WorkLimit
			_ => Bool.False
		}
	}
	var boundaries = []
	var end_count = 0.U64
	for result in TimedRecurrence.Cursor.outcomes(initial, work) {
		batch = result?
		match batch.status {
			End => {
				end_count = end_count + 1
			}
			Item(item) => {
				boundaries = boundaries.append(TimedRecurrence.Occurrence.boundary(item.occurrence))
			}
			Limited(_) => {
				valid = Bool.False
			}
		}
	}
	valid and zero_count == 1 and end_count == 1 and boundaries == [PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(3600000000)]
}

expect {
	initial = test_stream_cursor_with_validity(2, 0)?
	var errors = 0.U64
	var valid = Bool.True
	for result in TimedRecurrence.Cursor.outcomes(initial, { max_steps: 100, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 1 }) {
		errors = errors + 1
		valid = valid and match result {
			Err(OutsideValidity) => Bool.True
			_ => Bool.False
		}
	}
	valid and errors == 1
}

validate_options = |anchor, termination, positions| {
	match termination {
		Count(0) => return Err(InvalidCount)
		Until(end) => if before(end, anchor) {
			return Err(InvalidUntil)
		}
		_ => {}
	}
	if positions.len() > 4096 {
		return Err(TooManySelectors)
	}
	for position in positions {
		if position == 0 or position < -366 or position > 366 {
			return Err(InvalidSetPosition)
		}
	}
	Ok({})
}

timed_frame : TimedRecurrence, U64 -> Try({ start_day : I64, end_day : I64, clock_start : U64, clock_end : U64, end : LocalDateTime }, [OutOfRange, ..])
timed_frame = |rule, index| match rule.schedule {
	Calendar(pattern) => {
		period = CalendarPattern.period(pattern, index)?
		end_day = day_number(period.end)
		Ok({ start_day: day_number(period.start), end_day, clock_start: 0, clock_end: ClockPattern.count(rule.clocks), end: local_at(end_day, midnight({}))? })
	}
	Subdaily(pattern) => {
		period = SubdailyPattern.period(pattern, index)?
		start_day = day_number(period.date)
		Ok({ start_day, end_day: start_day + 1, clock_start: period.start_index, clock_end: period.end_index, end: period.end })
	}
}

matches_day : TimedRecurrence, U64, GregorianDate -> Try(Bool, [OutOfRange, ..])
matches_day = |rule, index, date| match rule.schedule {
	Calendar(pattern) => CalendarPattern.matches(pattern, index, date)
	Subdaily(pattern) => SubdailyPattern.matches_date(pattern, date)
}

# Independent nominal-second grids in fixed UTC. These include expansion,
# period filtering, microsecond retention and a midnight crossing.
test_subdaily = |clock_fields, pattern, positions, count| {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_fields(clock_fields)?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = local_at(3, midnight({}))?
	rule = TimedRecurrence.new_subdaily({ date, clock }, { pattern, termination: Count(count), by_set_pos: positions })?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(432000000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	var current = TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: RequireUnique, gap: RejectGap })?
	var boundaries = []
	var calls = 0.U64
	while calls < 2000 {
		batch = TimedRecurrence.Cursor.collect(current, { work: { max_steps: 1, max_buffered: 60, max_zone_segments: 1, max_zone_candidates: 1 }, max_occurrences: 2 })?
		if batch.steps > 1 or batch.zone_segments > 1 {
			crash "subdaily work limit"
		}
		for occurrence in batch.occurrences {
			boundaries = boundaries.append(PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(occurrence)))
		}
		match batch.status {
			Complete => return Ok(boundaries)
			Limited(progress) => {
				current = progress.cursor
			}
		}
		calls = calls + 1
	}
	crash "subdaily finite grid did not terminate"
}

test_subdaily_filters = { by_month: [], by_month_day: [], by_year_day: [], by_day: [] }

expect {
	test_subdaily(
		{ hour: 9, minute: 15, second: 30, microsecond: 7 },
		{
			frequency: Hourly,
			interval: 3,
			calendar: test_subdaily_filters,
			clocks: { hours: [], minutes: [45, 15], seconds: [] },
		},
		[],
		4,
	)? == [33330000007, 35130000007, 44130000007, 45930000007]
}

expect {
	test_subdaily(
		{ hour: 23, minute: 45, second: 20, microsecond: 7 },
		{
			frequency: Minutely,
			interval: 15,
			calendar: test_subdaily_filters,
			clocks: { hours: [], minutes: [], seconds: [50, 20] },
		},
		[],
		4,
	)? == [85520000007, 85550000007, 86420000007, 86450000007]
}

expect {
	test_subdaily(
		{ hour: 23, minute: 59, second: 50, microsecond: 7 },
		{
			frequency: Secondly,
			interval: 17,
			calendar: test_subdaily_filters,
			clocks: { hours: [], minutes: [], seconds: [] },
		},
		[],
		3,
	)? == [86390000007, 86407000007, 86424000007]
}

expect {
	test_subdaily(
		{ hour: 9, minute: 30, second: 30, microsecond: 0 },
		{
			frequency: Hourly,
			interval: 1,
			calendar: test_subdaily_filters,
			clocks: { hours: [], minutes: [0, 30], seconds: [0, 30] },
		},
		[-1],
		2,
	)? == [34230000000, 37830000000]
}

expect {
	test_subdaily(
		{ hour: 0, minute: 0, second: 0, microsecond: 0 },
		{
			frequency: Hourly,
			interval: 24,
			calendar: { ..test_subdaily_filters, by_year_day: [1] },
			clocks: { hours: [], minutes: [], seconds: [] },
		},
		[],
		2,
	)? == [0]
}

expect {
	# A huge interval must stop at this finite query before trying to construct
	# an irrelevant future period. Provider-extreme starts are tested in
	# SubdailyPattern without requiring a resolved axis of that larger range.
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = local_at(1, clock)?
	rule = TimedRecurrence.new_subdaily(
		{ date, clock },
		{
			pattern: {
				frequency: Hourly,
				interval: 2147483647,
				calendar: test_subdaily_filters,
				clocks: { hours: [], minutes: [], seconds: [] },
			},
			termination: Forever,
			by_set_pos: [],
		},
	)?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-1), PosixBoundary.from_microseconds(86400000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	cursor = TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: RequireUnique, gap: RejectGap })?
	result = TimedRecurrence.Cursor.collect(cursor, { work: { max_steps: 100, max_buffered: 1, max_zone_segments: 1, max_zone_candidates: 1 }, max_occurrences: 2 })?
	result.occurrences.len() == 1 and match result.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}
}

expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = { date, clock }
	pattern = { frequency: Hourly, interval: 1.I64, calendar: test_subdaily_filters, clocks: { hours: [], minutes: [], seconds: [] } }
	test_subdaily_status(start, { ..pattern, interval: 0 }) == Err(InvalidInterval) and
		test_subdaily_status(start, { ..pattern, interval: 2147483648 }) == Err(InvalidInterval) and
			test_subdaily_status(start, { ..pattern, clocks: { hours: [24], minutes: [], seconds: [] } }) == Err(InvalidHour) and
				test_subdaily_status(start, { ..pattern, clocks: { hours: [], minutes: [], seconds: [60] } }) == Err(UnsupportedLeapSecond) and
					test_subdaily_status(start, { ..pattern, clocks: { hours: [], minutes: [1], seconds: [] } }) == Err(UnsynchronizedStart) and
						test_subdaily_status(start, { ..pattern, calendar: { ..test_subdaily_filters, by_year_day: [367] } }) == Err(InvalidSelector("BYYEARDAY")) and
							test_subdaily_status(start, { ..pattern, calendar: { ..test_subdaily_filters, by_day: List.repeat(Monday, 4097) } }) == Err(TooManySelectors)
}

test_subdaily_status = |start, pattern| match TimedRecurrence.new_subdaily(start, { pattern, termination: Forever, by_set_pos: [] }) {
	Ok(_) => Ok({})
	Err(error) => Err(error)
}

excluded : List(LocalDateTime), LocalDateTime -> Bool
excluded = |labels, source| {
	var lower = 0.U64
	var upper = labels.len()
	while lower < upper {
		middle = lower + U64.div_trunc_by(upper - lower, 2)
		label = label_at(labels, middle)
		if before(label, source) {
			lower = middle + 1
		} else {
			upper = middle
		}
	}
	lower < labels.len() and LocalDateTime.same_position(label_at(labels, lower), source)
}

label_at = |labels, index| match List.get(labels, index) {
	Ok(value) => value
	Err(_) => crash "exclusion index invariant"
}

expect {
	gap_label = local_at(0, clock_from_number(3600000000))?
	exact_label = local_at(0, clock_from_number(7200000000))?
	budget = { max_steps: 1.U64, max_buffered: 1.U64, max_zone_segments: 1.U64, max_zone_candidates: 2.U64 }
	without_gap = test_series_with_pauses([], budget, 3600, First, [], [gap_label, gap_label])?
	without_exact = test_series_with_pauses([], budget, 3600, First, [], [exact_label])?
	without_gap.valid and without_exact.valid and without_gap.boundaries == [PosixBoundary.from_microseconds(0), PosixBoundary.from_microseconds(3600000000)] and without_gap.boundaries == without_exact.boundaries and without_gap.adjusted == [False, False] and without_exact.adjusted == [False, True]
}

expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_microseconds_since_midnight(0)?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = local_at(1, clock)?
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [0, 1, 2], minutes: [], seconds: [] }, termination: Count(1), by_set_pos: [] })?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-1), PosixBoundary.from_microseconds(86400000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	context = { rules, occurrence: RequireUnique, gap: RejectGap }
	original = TimedRecurrence.cursor(rule, { start, end }, context)?
	other_description = LocalDateTime.in_calendar(start, Julian)?
	later = local_at(0, clock_from_number(7200000000))?
	excluded_rule = TimedRecurrence.with_exclusions(rule, [later, other_description, start, later])?
	excluded_cursor = TimedRecurrence.cursor(excluded_rule, { start, end }, context)?
	cleared_rule = TimedRecurrence.with_exclusions(excluded_rule, [])?
	cleared_cursor = TimedRecurrence.cursor(cleared_rule, { start, end }, context)?
	limits = { work: { max_steps: 100.U64, max_buffered: 1.U64, max_zone_segments: 100.U64, max_zone_candidates: 1.U64 }, max_occurrences: 4.U64 }
	removed = TimedRecurrence.Cursor.collect(excluded_cursor, limits)?
	original_result = TimedRecurrence.Cursor.collect(original, limits)?
	cleared_result = TimedRecurrence.Cursor.collect(cleared_cursor, limits)?
	too_many = match TimedRecurrence.with_exclusions(rule, List.repeat(start, 4097)) {
		Err(TooManySelectors) => Bool.True
		_ => Bool.False
	}
	too_many and removed.occurrences.is_empty() and (match removed.status {
		Complete => Bool.True
		Limited(_) => Bool.False
	}) and original_result.occurrences.map(TimedRecurrence.Occurrence.source) == [start] and cleared_result.occurrences.map(TimedRecurrence.Occurrence.source) == [start]
}

expect {
	source = local_at(0, clock_from_number(0))?
	result = test_series_with_pauses([], { max_steps: 100, max_buffered: 1, max_zone_segments: 100, max_zone_candidates: 2 }, -3600, RequireUnique, [], [source])
	# Exclusions operate after interpretation; they cannot hide a missing
	# occurrence policy while determining the counted candidate sequence.
	match result {
		Err(Ambiguous) => Bool.True
		_ => Bool.False
	}
}

# Internal rule execution: only Cursor.next performs inclusion merging.

next_rule : TimedRecurrence.Cursor, TimedRecurrence.Limits -> Try(TimedRecurrence.Next, [OutOfRange, OutsideValidity, Gap, Ambiguous, AmbiguousGap, OffsetConflict, UnsynchronizedStart, ..])
next_rule = |initial, limits| {
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
						occurrence : TimedRecurrence.Occurrence
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
						within_cutoff = match state.boundary_cutoff {
							None => Bool.True
							Some(boundary) => occurrence.choice.boundary <= boundary
						}
						if within_cutoff {
							state = { ..state, count: state.count + 1 }
							if !before(occurrence.source, state.window.start) and !excluded(state.rule.exclusions, occurrence.source) {
								return Ok({ steps, zone_segments, buffered: buffered_count(state), zone_buffered: state.zone_buffered, status: Item({ occurrence, cursor: state }) })
							}
						}
					}
				}
			}
			Advance => {
				boundary = state.period_end
				if !before(boundary, state.window.end) {
					return Ok(ended(state, steps, zone_segments))
				}
				match state.rule.termination {
					Until(end) => if before(end, boundary) {
						return Ok(ended(state, steps, zone_segments))
					}
					_ => {}
				}
				match state.rule.schedule {
					Subdaily(pattern) => if !SubdailyPattern.starts_before(pattern, state.period + 1, state.window.end) {
						return Ok(ended(state, steps, zone_segments))
					}
					Calendar(_) => {}
				}
				frame = timed_frame(state.rule, state.period + 1)?
				state = { ..state, period: state.period + 1, day: frame.start_day, end_day: frame.end_day, period_end: frame.end, day_selected: Unknown, clock_index: frame.clock_start, clock_start: frame.clock_start, clock_end: frame.clock_end, phase: Build, anchor_index: None }
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
							matches = matches_day(state.rule, state.period, date)?
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
							if state.clock_index == state.clock_end {
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

sorted_positions : List(LocalDateTime) -> List(LocalDateTime)
sorted_positions = |labels| {
	sorted = labels.sort_with(
		|a, b| match LocalDateTime.compare_position(a, b) {
			LT => Before
			EQ => Same
			GT => After
		},
	)
	var exclusions = []
	var previous = None
	for label in sorted {
		distinct = match previous {
			None => Bool.True
			Some(value) => !LocalDateTime.same_position(value, label)
		}
		if distinct {
			exclusions = exclusions.append(label)
		}
		previous = Some(label)
	}
	exclusions
}

# R11/R12: explicit starts precede DTSTART and outlive COUNT; duplicates and
# exclusions operate on the merged positions, and one-unit resumes agree.
test_inclusion_cursor = |_| {
	clock = clock_from_number(0)
	start = |day| Ok({ date: GregorianDate.from_fields({ year: 1970, month: 1, day })?, clock })
	anchor = start(2)?
	raw = TimedRecurrence.new(anchor, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [], minutes: [], seconds: [] }, termination: Count(2), by_set_pos: [] })?
	included = TimedRecurrence.with_inclusions(raw, [start(4)?, start(2)?, start(1)?, start(4)?, start(5)?])?
	rule = TimedRecurrence.with_exclusions(included, [local_at(1, clock)?])?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(518400000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	TimedRecurrence.cursor(rule, { start: local_at(0, clock)?, end: local_at(4, clock)? }, { rules, occurrence: RequireUnique, gap: RejectGap })
}

test_inclusions = |budget| {
	var cursor = test_inclusion_cursor({})?
	var observed = []
	var calls = 0.U64
	while calls < 1000 {
		batch = TimedRecurrence.Cursor.next(cursor, budget)?
		if batch.steps > budget.max_steps or batch.zone_segments > budget.max_zone_segments {
			return Ok(Bool.False)
		}
		match batch.status {
			End => return Ok(observed == [0.I64, 172800000000, 259200000000])
			Limited(progress) => {
				cursor = progress.cursor
			}
			Item(item) => {
				observed = observed.append(PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(item.occurrence)))
				cursor = item.cursor
			}
		}
		calls = calls + 1
	}
	Ok(Bool.False)
}

expect test_inclusions({ max_steps: 1, max_buffered: 2, max_zone_segments: 1, max_zone_candidates: 1 }) == Ok(Bool.True)
expect test_inclusions({ max_steps: 100, max_buffered: 2, max_zone_segments: 100, max_zone_candidates: 1 }) == Ok(Bool.True)

expect {
	initial = test_inclusion_cursor({})?
	full = { max_steps: 100.U64, max_buffered: 2.U64, max_zone_segments: 100.U64, max_zone_candidates: 1.U64 }
	var valid = Bool.True
	for work in [{ ..full, max_steps: 0 }, { ..full, max_buffered: 0 }, { ..full, max_buffered: 1 }, { ..full, max_zone_segments: 0 }, { ..full, max_zone_candidates: 0 }] {
		paused = TimedRecurrence.Cursor.next(initial, work)?
		rest = match paused.status {
			Limited(progress) => progress.cursor
			_ => crash "merge needs more budget"
		}
		completed = TimedRecurrence.Cursor.collect(rest, { work: full, max_occurrences: 10 })?
		observed = completed.occurrences.map(|value| PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(value)))
		valid = valid and observed == [0.I64, 172800000000, 259200000000] and match completed.status {
			Complete => Bool.True
			_ => Bool.False
		}
	}
	valid
}

# R07/R11/R12: a source after a rejected gap label can map back below UNTIL.
# Direct two-segment model: at 02:00Z offset changes from 0 to +1h.
# 02:30 local uses the pre-gap offset (02:30Z), but 03:00 is 02:00Z.
expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_fields({ hour: 2, minute: 30, second: 0, microsecond: 0 })?
	cutoff = PosixBoundary.from_microseconds(8100000000)
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [2, 3], minutes: [0, 30], seconds: [] }, termination: UntilBoundary(cutoff), by_set_pos: [] })?
	four = ClockTime.from_fields({ hour: 4, minute: 0, second: 0, microsecond: 0 })?
	with_extra = TimedRecurrence.with_inclusions(rule, [{ date, clock: four }])?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-86400000000), PosixBoundary.from_microseconds(172800000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC-cutoff", "v1", validity, FixedOffset.from_seconds(0), [{ at: PosixBoundary.from_microseconds(7200000000), offset: FixedOffset.from_seconds(3600) }], { minimum: 0, maximum: 3600 })?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 2 })?), clock)
	var cursor = TimedRecurrence.cursor(with_extra, { start, end }, { rules, occurrence: First, gap: UseOffsetBeforeGap })?
	var boundaries = []
	var hours = []
	var calls = 0.U64
	var complete = Bool.False
	while calls < 100 and !complete {
		batch = TimedRecurrence.Cursor.collect(cursor, { work: { max_steps: 1, max_buffered: 2, max_zone_segments: 1, max_zone_candidates: 2 }, max_occurrences: 1 })?
		for value in batch.occurrences {
			boundaries = boundaries.append(PosixBoundary.to_microseconds(TimedRecurrence.Occurrence.boundary(value)))
			hours = hours.append(ClockTime.to_fields(LocalDateTime.clock(TimedRecurrence.Occurrence.source(value))).hour)
		}
		match batch.status {
			Complete => {
				complete = Bool.True
			}
			Limited(progress) => {
				cursor = progress.cursor
			}
		}
		calls = calls + 1
	}
	complete and boundaries == [7200000000.I64, 10800000000] and hours == [3.U8, 4]
}

# BYSETPOS observes the whole day before boundary termination. Cutting the
# second day's clock list at 01:30 would incorrectly make 01:00 its last item.
expect {
	date = GregorianDate.from_fields({ year: 1970, month: 1, day: 1 })?
	clock = ClockTime.from_fields({ hour: 2, minute: 0, second: 0, microsecond: 0 })?
	cutoff = PosixBoundary.from_microseconds(91800000000)
	rule = TimedRecurrence.new({ date, clock }, { calendar: CalendarPattern.defaults(Daily), clocks: { hours: [0, 1, 2], minutes: [], seconds: [] }, termination: UntilBoundary(cutoff), by_set_pos: [-1] })?
	validity = PosixSpan.new(PosixBoundary.from_microseconds(-1), PosixBoundary.from_microseconds(259200000000))?
	rules = ZoneRules.new_bounded("Synthetic/UTC", "v1", validity, FixedOffset.from_seconds(0), [], { minimum: 0, maximum: 0 })?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(GregorianDate.from_fields({ year: 1970, month: 1, day: 3 })?), clock)
	cursor = TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: First, gap: UseOffsetBeforeGap })?
	batch = TimedRecurrence.Cursor.collect(cursor, { work: { max_steps: 100, max_buffered: 3, max_zone_segments: 20, max_zone_candidates: 1 }, max_occurrences: 10 })?
	match batch.status {
		Complete => batch.occurrences.len() == 1 and TimedRecurrence.Occurrence.boundary(batch.occurrences.get(0)?) == PosixBoundary.from_microseconds(7200000000)
		Limited(_) => Bool.False
	}
}

# RFC 5545 section 3.8.5.3, corrected by verified erratum 3883 (2014-02-14).
# https://www.rfc-editor.org/errata/eid3883
# New York 1997-09-02 is UTC-04:00: corrected 21:00Z includes 09/12/15
# local; original 17:00Z includes only 09/12. 19:00Z tests exact inclusion.
expect {
	date = GregorianDate.from_fields({ year: 1997, month: 9, day: 2 })?
	clock = ClockTime.from_fields({ hour: 9, minute: 0, second: 0, microsecond: 0 })?
	start = LocalDateTime.new(CalendarDate.from_gregorian(date), clock)
	end = LocalDateTime.new(CalendarDate.from_gregorian(GregorianDate.from_fields({ year: 1997, month: 9, day: 3 })?), clock)
	midnight_label = LocalDateTime.new(CalendarDate.from_gregorian(date), midnight({}))
	base = PosixBoundary.to_microseconds(FixedOffset.resolve(FixedOffset.from_seconds(0), midnight_label)?)
	validity = PosixSpan.new(PosixBoundary.from_microseconds(base - 86400000000), PosixBoundary.from_microseconds(base + 172800000000))?
	rules = ZoneRules.new_bounded("RFC5545/New_York", "1997-example", validity, FixedOffset.from_seconds(-14400), [], { minimum: -14400, maximum: -14400 })?
	var valid = Bool.True
	for case in [{ cutoff_hour: 21.I64, expected: [9.U8, 12, 15] }, { cutoff_hour: 17, expected: [9, 12] }, { cutoff_hour: 19, expected: [9, 12, 15] }] {
		rule = TimedRecurrence.new_subdaily({ date, clock }, { pattern: { frequency: Hourly, interval: 3, calendar: { by_month: [], by_month_day: [], by_year_day: [], by_day: [] }, clocks: { hours: [], minutes: [], seconds: [] } }, termination: UntilBoundary(PosixBoundary.from_microseconds(base + case.cutoff_hour * 3600000000)), by_set_pos: [] })?
		cursor = TimedRecurrence.cursor(rule, { start, end }, { rules, occurrence: First, gap: UseOffsetBeforeGap })?
		batch = TimedRecurrence.Cursor.collect(cursor, { work: { max_steps: 100, max_buffered: 1, max_zone_segments: 10, max_zone_candidates: 1 }, max_occurrences: 10 })?
		valid = valid and batch.occurrences.map(|value| ClockTime.to_fields(LocalDateTime.clock(TimedRecurrence.Occurrence.source(value))).hour) == case.expected and match batch.status {
			Complete => Bool.True
			Limited(_) => Bool.False
		}
	}
	valid
}
